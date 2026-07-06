// ============================================================================
// HistoryRepository — CRUD para historial de descargas
// ============================================================================

import type { AppDatabase } from "./Database.js";
import type { HistoryEntry } from "../types/index.js";
import { TaskStatus } from "../types/index.js";

export class HistoryRepository {
  constructor(private db: AppDatabase) {}

  /**
   * Inserta una entrada en el historial.
   */
  insert(entry: Omit<HistoryEntry, "id">): number {
    const result = this.db.execute(
      `INSERT INTO history (task_id, url, provider, title, author, format, quality, file_path, file_size, duration, thumbnail, status, error, is_favorite, created_at, completed_at)
       VALUES (@taskId, @url, @provider, @title, @author, @format, @quality, @filePath, @fileSize, @duration, @thumbnail, @status, @error, @isFavorite, @createdAt, @completedAt)`,
      {
        taskId: entry.task_id || entry.url,
        url: entry.url,
        provider: entry.provider,
        title: entry.title,
        author: entry.author,
        format: entry.format,
        quality: entry.quality,
        filePath: entry.filePath || "",
        fileSize: entry.fileSize || 0,
        duration: entry.duration || 0,
        thumbnail: entry.thumbnail || "",
        status: entry.status || TaskStatus.Completed,
        error: null,
        isFavorite: entry.isFavorite ? 1 : 0,
        createdAt: entry.createdAt || Date.now(),
        completedAt: entry.completedAt || null,
      }
    );
    return Number(result.lastInsertRowid);
  }

  /**
   * Lista todo el historial, ordenado por fecha descendente.
   */
  listAll(limit = 50, offset = 0): HistoryEntry[] {
    return this.db.queryAll<HistoryEntry>(
      `SELECT id, task_id as taskId, url, provider, title, author, format, quality, file_path as filePath, file_size as fileSize, duration, thumbnail, status, error, is_favorite as isFavorite, created_at as createdAt, completed_at as completedAt
       FROM history
       ORDER BY created_at DESC
       LIMIT @limit OFFSET @offset`,
      { limit, offset }
    );
  }

  /**
   * Lista los favoritos.
   */
  listFavorites(limit = 50, offset = 0): HistoryEntry[] {
    return this.db.queryAll<HistoryEntry>(
      `SELECT id, task_id as taskId, url, provider, title, author, format, quality, file_path as filePath, file_size as fileSize, duration, thumbnail, status, error, is_favorite as isFavorite, created_at as createdAt, completed_at as completedAt
       FROM history
       WHERE is_favorite = 1
       ORDER BY created_at DESC
       LIMIT @limit OFFSET @offset`,
      { limit, offset }
    );
  }

  /**
   * Busca en el historial por título o URL.
   */
  search(query: string, limit = 20): HistoryEntry[] {
    return this.db.queryAll<HistoryEntry>(
      `SELECT id, task_id as taskId, url, provider, title, author, format, quality, file_path as filePath, file_size as fileSize, duration, thumbnail, status, error, is_favorite as isFavorite, created_at as createdAt, completed_at as completedAt
       FROM history
       WHERE title LIKE @query OR url LIKE @query
       ORDER BY created_at DESC
       LIMIT @limit`,
      { query: `%${query}%`, limit }
    );
  }

  /**
   * Marca/desmarca una entrada como favorita.
   */
  toggleFavorite(id: number): boolean {
    const entry = this.db.queryOne<{ is_favorite: number }>(
      "SELECT is_favorite FROM history WHERE id = @id",
      { id }
    );
    if (!entry) return false;

    this.db.execute(
      "UPDATE history SET is_favorite = @val WHERE id = @id",
      { id, val: entry.is_favorite ? 0 : 1 }
    );
    return true;
  }

  /**
   * Actualiza el estado de una entrada.
   */
  updateStatus(taskId: string, status: TaskStatus, error?: string): void {
    this.db.execute(
      "UPDATE history SET status = @status, error = @error WHERE task_id = @taskId",
      { taskId, status, error: error || null }
    );
  }

  /**
   * Elimina una entrada del historial.
   */
  delete(id: number): boolean {
    const result = this.db.execute("DELETE FROM history WHERE id = @id", { id });
    return result.changes > 0;
  }

  /**
   * Limpia todo el historial.
   */
  clearAll(): number {
    const result = this.db.execute("DELETE FROM history");
    return result.changes;
  }

  /**
   * Obtiene el conteo total del historial.
   */
  count(): number {
    const result = this.db.queryOne<{ count: number }>("SELECT COUNT(*) as count FROM history");
    return result?.count ?? 0;
  }
}
