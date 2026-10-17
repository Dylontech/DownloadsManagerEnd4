// ============================================================================
// DownloadQueue — Cola de descargas con control de estado
// ============================================================================

import { EventEmitter } from "node:events";
import type { DownloadTask, DownloadProgress } from "../types/index.js";
import { TaskStatus } from "../types/index.js";
import { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";

export interface QueueEvents {
  "task.added": [task: DownloadTask];
  "task.removed": [taskId: string];
  "task.status": [taskId: string, status: TaskStatus, previous: TaskStatus];
  "task.progress": [taskId: string, progress: DownloadProgress];
  "queue.drained": [];
  "queue.error": [taskId: string, error: string];
}

/**
 * Destino de persistencia de la cola.
 *
 * Se inyecta desde fuera para que el núcleo no dependa de SQLite (y siga
 * siendo testeable en memoria con un doble).
 */
export interface QueuePersistence {
  upsert(task: DownloadTask): void;
  remove(taskId: string): void;
}

export class DownloadQueue extends EventEmitter {
  private tasks: Map<string, DownloadTask> = new Map();
  private queueOrder: string[] = [];
  private activeTaskIds: Set<string> = new Set();
  private maxConcurrent: number;
  private ytDlpAdapter: YtDlpAdapter;
  private persistence?: QueuePersistence;

  constructor(
    ytDlpAdapter: YtDlpAdapter,
    maxConcurrent = 3,
    persistence?: QueuePersistence
  ) {
    super();
    this.ytDlpAdapter = ytDlpAdapter;
    this.maxConcurrent = maxConcurrent;
    this.persistence = persistence;
    this.setupAdapterListeners();
  }

  private releaseSlot(taskId: string): void {
    this.activeTaskIds.delete(taskId);
  }

  private setupAdapterListeners(): void {
    this.ytDlpAdapter.on("progress", ({ taskId, progress }) => {
      const task = this.tasks.get(taskId);
      if (task) {
        task.progress = progress;
        this.emit("task.progress", taskId, progress);
      }
    });

    this.ytDlpAdapter.on("completed", ({ taskId, filePath, fileSize }) => {
      this.releaseSlot(taskId);
      const task = this.tasks.get(taskId);
      if (task) {
        const previous = task.status;
        task.status = TaskStatus.Completed;
        task.completedAt = Date.now();
        task.filePath = filePath;
        task.fileSize = fileSize;
        task.progress = { ...task.progress, percent: 100 };
        this.persist(task);
        this.emit("task.status", taskId, TaskStatus.Completed, previous);
        this.processNext();
      }
    });

    this.ytDlpAdapter.on("error", ({ taskId, error }) => {
      this.releaseSlot(taskId);
      const task = this.tasks.get(taskId);
      if (!task) return;

      // Descarga cancelada o eliminada a propósito: no reintentar,
      // de lo contrario se reiniciaría sola y dejaría el archivo a medias.
      if (task.status === TaskStatus.Cancelled) return;

      const previous = task.status;
      task.status = TaskStatus.Failed;
      task.error = error;
      task.retries++;

      // Reintentar si es posible
      if (task.retries < task.maxRetries) {
        this.retryTask(task, previous);
      } else {
        this.persist(task);
        this.emit("task.status", taskId, TaskStatus.Failed, previous);
        this.emit("queue.error", taskId, error);
        this.processNext();
      }
    });
  }

  // ─── Gestión de Tareas ─────────────────────────────────────────────────

  enqueue(task: DownloadTask): string {
    this.tasks.set(task.id, task);
    this.queueOrder.push(task.id);
    this.emit("task.added", task);
    this.emit("task.status", task.id, TaskStatus.Queued, TaskStatus.Queued);
    this.persist(task);
    this.processNext();
    return task.id;
  }

  remove(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    const wasActive = this.activeTaskIds.has(taskId);
    if (wasActive) {
      this.ytDlpAdapter.cancelDownload(taskId);
    }

    this.tasks.delete(taskId);
    this.queueOrder = this.queueOrder.filter((id) => id !== taskId);
    this.releaseSlot(taskId);
    this.persistence?.remove(taskId);
    this.emit("task.removed", taskId);

    if (wasActive) {
      this.processNext();
    }
    return true;
  }

  pause(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task || task.status !== TaskStatus.Running) return false;

    const paused = this.ytDlpAdapter.pauseDownload(taskId);
    if (paused) {
      const prev = task.status;
      task.status = TaskStatus.Paused;
      this.persist(task);
      this.emit("task.status", taskId, TaskStatus.Paused, prev);
    }
    return paused;
  }

  resume(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task || task.status !== TaskStatus.Paused) return false;

    const resumed = this.ytDlpAdapter.resumeDownload(taskId);
    if (resumed) {
      const prev = task.status;
      task.status = TaskStatus.Running;
      this.persist(task);
      this.emit("task.status", taskId, TaskStatus.Running, prev);
    }
    return resumed;
  }

  cancel(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;
    if (
      task.status === TaskStatus.Completed ||
      task.status === TaskStatus.Failed ||
      task.status === TaskStatus.Cancelled
    ) {
      return false;
    }

    const wasActive = this.activeTaskIds.has(taskId);
    if (wasActive) {
      this.ytDlpAdapter.cancelDownload(taskId);
    }

    const prev = task.status;
    task.status = TaskStatus.Cancelled;
    this.releaseSlot(taskId);
    this.persist(task);
    this.emit("task.status", taskId, TaskStatus.Cancelled, prev);

    if (wasActive) {
      this.processNext();
    }
    return true;
  }

  // ─── Consultas ─────────────────────────────────────────────────────────

  getTask(taskId: string): DownloadTask | undefined {
    return this.tasks.get(taskId);
  }

  listTasks(status?: TaskStatus): DownloadTask[] {
    const all = this.queueOrder
      .map((id) => this.tasks.get(id)!)
      .filter(Boolean);

    if (status) {
      return all.filter((t) => t.status === status);
    }
    return all;
  }

  listActive(): DownloadTask[] {
    return this.listTasks(TaskStatus.Running);
  }

  listQueued(): DownloadTask[] {
    return this.listTasks(TaskStatus.Queued);
  }

  clearCompleted(): number {
    let count = 0;
    for (const [id, task] of this.tasks) {
      if (task.status === TaskStatus.Completed || task.status === TaskStatus.Cancelled || task.status === TaskStatus.Failed) {
        this.tasks.delete(id);
        this.queueOrder = this.queueOrder.filter((qId) => qId !== id);
        count++;
      }
    }
    return count;
  }

  get size(): number {
    return this.tasks.size;
  }

  get activeCount(): number {
    return this.activeTaskIds.size;
  }

  setMaxConcurrent(max: number): void {
    this.maxConcurrent = max;
    this.processNext();
  }

  // ─── Persistencia y recuperación ─────────────────────────────────────────

  /**
   * Refleja el estado de una tarea en el almacén persistente.
   *
   * Los estados terminales BORRAN la fila: una tarea terminada pertenece al
   * historial, no a la cola recuperable.
   */
  private persist(task: DownloadTask): void {
    if (!this.persistence) return;

    if (
      task.status === TaskStatus.Completed ||
      task.status === TaskStatus.Cancelled ||
      task.status === TaskStatus.Failed
    ) {
      this.persistence.remove(task.id);
      return;
    }

    try {
      this.persistence.upsert(task);
    } catch (err) {
      console.error("[DownloadQueue] No se pudo persistir la tarea:", err);
    }
  }

  /**
   * Re-encola tareas recuperadas de un arranque anterior.
   *
   * Se insertan directamente en la cola en lugar de pasar por
   * `DownloadManager.startDownload` para no volver a analizar la URL con
   * `yt-dlp -J` (lento y dependiente de la red): los `options` ya persistidos
   * bastan para reconstruir el comando. Como yt-dlp continúa los `.part`
   * existentes, la descarga sigue donde se quedó.
   */
  restore(tasks: DownloadTask[]): number {
    let restored = 0;

    for (const task of tasks) {
      if (!task?.id || this.tasks.has(task.id)) continue;

      const previous = task.status;

      task.status = TaskStatus.Queued;
      task.retries = 0;
      task.error = undefined;
      task.startedAt = undefined;
      task.completedAt = undefined;
      // Se conserva la forma del progreso persistido (por si el tipo cambia),
      // pero se pone a cero: los datos de la ejecución anterior ya no valen.
      task.progress = {
        ...task.progress,
        percent: 0,
        speed: 0,
        downloadedBytes: 0,
        totalBytes: 0,
      };

      this.tasks.set(task.id, task);
      this.queueOrder.push(task.id);
      this.emit("task.added", task);
      this.emit("task.status", task.id, TaskStatus.Queued, previous);
      this.persist(task);
      restored++;
    }

    if (restored > 0) {
      this.processNext();
    }

    return restored;
  }

  // ─── Procesamiento Interno ─────────────────────────────────────────────

  private processNext(): void {
    while (this.activeTaskIds.size < this.maxConcurrent) {
      const nextTask = this.findNextQueued();
      if (!nextTask) {
        if (this.activeTaskIds.size === 0 && this.size === 0) {
          this.emit("queue.drained");
        }
        return;
      }

      this.activeTaskIds.add(nextTask.id);
      const prev = nextTask.status;
      nextTask.status = TaskStatus.Running;
      nextTask.startedAt = Date.now();
      this.persist(nextTask);
      this.emit("task.status", nextTask.id, TaskStatus.Running, prev);

      this.ytDlpAdapter.startDownload(nextTask);
    }
  }

  private findNextQueued(): DownloadTask | undefined {
    for (const id of this.queueOrder) {
      const task = this.tasks.get(id);
      if (task?.status === TaskStatus.Queued) {
        return task;
      }
    }
    return undefined;
  }

  private retryTask(task: DownloadTask, previous: TaskStatus): void {
    task.status = TaskStatus.Queued;
    task.error = undefined;
    this.persist(task);
    this.emit("task.status", task.id, TaskStatus.Queued, previous);
    this.processNext();
  }

  // ─── Limpieza ──────────────────────────────────────────────────────────

  destroy(): void {
    this.ytDlpAdapter.removeAllListeners();
    this.ytDlpAdapter.killAll();
    this.tasks.clear();
    this.queueOrder = [];
    this.activeTaskIds.clear();
    this.removeAllListeners();
  }
}
