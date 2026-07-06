// ============================================================================
// HistoryService — Lógica de negocio para el historial
// ============================================================================

import { HistoryRepository } from "../db/HistoryRepository.js";
import type { HistoryEntry, DownloadTask } from "../types/index.js";

export class HistoryService {
  constructor(private historyRepo: HistoryRepository) {}

  /**
   * Registra una descarga completada en el historial.
   */
  recordDownload(task: DownloadTask): number {
    const entry: Omit<HistoryEntry, "id"> = {
      task_id: task.id,
      url: task.options.url,
      provider: task.options.provider || task.mediaInfo?.provider || "unknown",
      title: task.mediaInfo?.title || "Unknown",
      author: task.mediaInfo?.author || "Unknown",
      format: task.options.format,
      quality: task.options.quality,
      filePath: task.filePath || "",
      fileSize: task.fileSize || task.progress.totalBytes || 0,
      duration: task.mediaInfo?.duration || 0,
      thumbnail: task.mediaInfo?.thumbnail || "",
      status: task.status,
      error: task.error,
      isFavorite: false,
      createdAt: task.createdAt,
      completedAt: task.completedAt,
    };

    return this.historyRepo.insert(entry);
  }

  /**
   * Lista el historial reciente.
   */
  listRecent(limit = 50, offset = 0): HistoryEntry[] {
    return this.historyRepo.listAll(limit, offset);
  }

  /**
   * Lista favoritos.
   */
  listFavorites(limit = 50, offset = 0): HistoryEntry[] {
    return this.historyRepo.listFavorites(limit, offset);
  }

  /**
   * Busca en el historial.
   */
  search(query: string): HistoryEntry[] {
    return this.historyRepo.search(query);
  }

  /**
   * Marca/desmarca favorito.
   */
  toggleFavorite(id: number): boolean {
    return this.historyRepo.toggleFavorite(id);
  }

  /**
   * Elimina una entrada del historial.
   */
  deleteEntry(id: number): boolean {
    return this.historyRepo.delete(id);
  }

  /**
   * Limpia todo el historial.
   */
  clearAll(): number {
    return this.historyRepo.clearAll();
  }

  /**
   * Conteo total.
   */
  count(): number {
    return this.historyRepo.count();
  }
}
