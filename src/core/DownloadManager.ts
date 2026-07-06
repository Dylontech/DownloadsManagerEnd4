// ============================================================================
// DownloadManager — Orquestador principal del sistema
// ============================================================================

import { randomUUID } from "node:crypto";
import { ProviderManager } from "./ProviderManager.js";
import { DownloadQueue } from "./DownloadQueue.js";
import { YtDlpAdapter } from "../adapters/YtDlpAdapter.js";
import type {
  MediaInfo,
  DownloadTask,
  DownloadOptions,
  FormatInfo,
  SubtitleInfo,
} from "../types/index.js";
import { TaskStatus } from "../types/index.js";
import { validateUrl } from "../utils/UrlValidator.js";

/**
 * DownloadManager es la fachada principal del backend.
 * Orquesta: ProviderManager + DownloadQueue + YtDlpAdapter.
 * Es el punto de entrada para todos los RPC handlers.
 */
export class DownloadManager {
  readonly providerManager: ProviderManager;
  readonly downloadQueue: DownloadQueue;
  readonly ytDlpAdapter: YtDlpAdapter;

  constructor() {
    this.ytDlpAdapter = new YtDlpAdapter();
    this.providerManager = new ProviderManager();
    this.downloadQueue = new DownloadQueue(this.ytDlpAdapter);
  }

  // ─── Información de Media ──────────────────────────────────────────────

  /**
   * Obtiene información detallada de un media desde su URL.
   * Detecta automáticamente el provider.
   */
  async getMediaInfo(url: string): Promise<MediaInfo> {
    if (!validateUrl(url)) {
      throw new Error("URL inválida o no segura");
    }
    return this.providerManager.getMediaInfo(url);
  }

  /**
   * Obtiene los formatos disponibles para una URL.
   */
  async getFormats(url: string): Promise<FormatInfo[]> {
    if (!validateUrl(url)) throw new Error("URL inválida");
    return this.ytDlpAdapter.getFormats(url);
  }

  /**
   * Obtiene los subtítulos disponibles para una URL.
   */
  async getSubtitles(url: string): Promise<SubtitleInfo[]> {
    if (!validateUrl(url)) throw new Error("URL inválida");
    return this.ytDlpAdapter.getSubtitles(url);
  }

  // ─── Descargas ─────────────────────────────────────────────────────────

  /**
   * Inicia una descarga. Detecta provider, extrae info y encola.
   */
  async startDownload(options: DownloadOptions): Promise<DownloadTask> {
    // Validar URL
    if (!validateUrl(options.url)) {
      throw new Error("URL inválida o no segura");
    }

    // Detectar provider
    const provider = this.providerManager.detectProvider(options.url);
    if (!provider) {
      throw new Error(`No se encontró un provider para: ${options.url}`);
    }

    // Extraer información del media
    let mediaInfo: MediaInfo | undefined;
    try {
      mediaInfo = await provider.getInfo(options.url);
    } catch (err) {
      // Si falla la extracción, continuamos sin info (descarga a ciegas)
      console.warn("[DownloadManager] Could not extract media info:", err);
    }

    // Construir task
    const task: DownloadTask = {
      id: randomUUID(),
      options,
      mediaInfo,
      status: TaskStatus.Queued,
      progress: {
        percent: 0,
        speed: 0,
        eta: 0,
        downloadedBytes: 0,
        totalBytes: 0,
        speedFormatted: "",
        etaFormatted: "",
        downloadedFormatted: "",
        totalFormatted: "",
      },
      retries: 0,
      maxRetries: 3,
      createdAt: Date.now(),
    };

    // Encolar
    this.downloadQueue.enqueue(task);
    return task;
  }

  /**
   * Pausa una descarga activa.
   */
  pauseDownload(taskId: string): boolean {
    return this.downloadQueue.pause(taskId);
  }

  /**
   * Reanuda una descarga pausada.
   */
  resumeDownload(taskId: string): boolean {
    return this.downloadQueue.resume(taskId);
  }

  /**
   * Cancela una descarga (activa o en cola).
   */
  cancelDownload(taskId: string): boolean {
    return this.downloadQueue.cancel(taskId);
  }

  /**
   * Elimina una tarea de la cola.
   */
  removeDownload(taskId: string): boolean {
    return this.downloadQueue.remove(taskId);
  }

  // ─── Consultas ─────────────────────────────────────────────────────────

  /**
   * Obtiene una tarea por ID.
   */
  getTask(taskId: string): DownloadTask | undefined {
    return this.downloadQueue.getTask(taskId);
  }

  /**
   * Lista todas las tareas (opcionalmente filtradas por estado).
   */
  listTasks(status?: TaskStatus): DownloadTask[] {
    return this.downloadQueue.listTasks(status);
  }

  /**
   * Lista providers disponibles.
   */
  listProviders() {
    return this.providerManager.listProviders();
  }

  /**
   * Detecta y retorna el proveedor para una URL (sin extraer info).
   */
  detectProvider(url: string) {
    return this.providerManager.detectProvider(url)?.info ?? null;
  }

  // ─── Estado del Sistema ────────────────────────────────────────────────

  /**
   * Obtiene el estado completo del sistema.
   */
  getSystemStatus() {
    return {
      activeDownloads: this.downloadQueue.listActive().length,
      queuedDownloads: this.downloadQueue.listQueued().length,
      totalDownloads: this.downloadQueue.size,
      maxConcurrent: (this.downloadQueue as any).maxConcurrent,
      providersCount: this.providerManager.count,
      ytDlpActive: this.ytDlpAdapter.activeCount,
    };
  }

  /**
   * Limpia descargas completadas/fallidas/canceladas de la cola.
   */
  clearCompleted(): number {
    return this.downloadQueue.clearCompleted();
  }

  // ─── Limpieza ──────────────────────────────────────────────────────────

  /**
   * Detiene todo y libera recursos.
   */
  destroy(): void {
    this.downloadQueue.destroy();
  }
}
