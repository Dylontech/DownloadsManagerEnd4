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

export class DownloadQueue extends EventEmitter {
  private tasks: Map<string, DownloadTask> = new Map();
  private queueOrder: string[] = [];
  private activeCount = 0;
  private maxConcurrent: number;
  private ytDlpAdapter: YtDlpAdapter;

  constructor(ytDlpAdapter: YtDlpAdapter, maxConcurrent = 3) {
    super();
    this.ytDlpAdapter = ytDlpAdapter;
    this.maxConcurrent = maxConcurrent;
    this.setupAdapterListeners();
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
      const task = this.tasks.get(taskId);
      if (task) {
        task.status = TaskStatus.Completed;
        task.completedAt = Date.now();
        task.filePath = filePath;
        task.fileSize = fileSize;
        task.progress = { ...task.progress, percent: 100 };
        this.activeCount--;
        this.emit("task.status", taskId, TaskStatus.Completed, TaskStatus.Running);
        this.processNext();
      }
    });

    this.ytDlpAdapter.on("error", ({ taskId, error }) => {
      const task = this.tasks.get(taskId);
      if (task) {
        task.status = TaskStatus.Failed;
        task.error = error;
        task.retries++;
        this.activeCount--;

        // Reintentar si es posible
        if (task.retries < task.maxRetries) {
          this.retryTask(task);
        } else {
          this.emit("task.status", taskId, TaskStatus.Failed, TaskStatus.Running);
          this.emit("queue.error", taskId, error);
          this.processNext();
        }
      }
    });
  }

  // ─── Gestión de Tareas ─────────────────────────────────────────────────

  enqueue(task: DownloadTask): string {
    this.tasks.set(task.id, task);
    this.queueOrder.push(task.id);
    this.emit("task.added", task);
    this.emit("task.status", task.id, TaskStatus.Queued, TaskStatus.Queued);
    this.processNext();
    return task.id;
  }

  remove(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    if (task.status === TaskStatus.Running) {
      this.ytDlpAdapter.cancelDownload(taskId);
    }

    this.tasks.delete(taskId);
    this.queueOrder = this.queueOrder.filter((id) => id !== taskId);
    this.emit("task.removed", taskId);
    return true;
  }

  pause(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task || task.status !== TaskStatus.Running) return false;

    const paused = this.ytDlpAdapter.pauseDownload(taskId);
    if (paused) {
      const prev = task.status;
      task.status = TaskStatus.Paused;
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
      this.emit("task.status", taskId, TaskStatus.Running, prev);
    }
    return resumed;
  }

  cancel(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    const cancelled = this.ytDlpAdapter.cancelDownload(taskId);
    if (cancelled) {
      const prev = task.status;
      task.status = TaskStatus.Cancelled;
      this.activeCount--;
      this.emit("task.status", taskId, TaskStatus.Cancelled, prev);
      this.processNext();
    }
    return cancelled;
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

  setMaxConcurrent(max: number): void {
    this.maxConcurrent = max;
    this.processNext();
  }

  // ─── Procesamiento Interno ─────────────────────────────────────────────

  private processNext(): void {
    while (this.activeCount < this.maxConcurrent) {
      const nextTask = this.findNextQueued();
      if (!nextTask) {
        if (this.activeCount === 0 && this.size === 0) {
          this.emit("queue.drained");
        }
        return;
      }

      this.activeCount++;
      const prev = nextTask.status;
      nextTask.status = TaskStatus.Running;
      nextTask.startedAt = Date.now();
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

  private retryTask(task: DownloadTask): void {
    task.status = TaskStatus.Queued;
    task.error = undefined;
    this.emit("task.status", task.id, TaskStatus.Queued, TaskStatus.Failed);
    this.processNext();
  }

  // ─── Limpieza ──────────────────────────────────────────────────────────

  destroy(): void {
    this.ytDlpAdapter.removeAllListeners();
    this.ytDlpAdapter.killAll();
    this.tasks.clear();
    this.queueOrder = [];
    this.activeCount = 0;
    this.removeAllListeners();
  }
}
