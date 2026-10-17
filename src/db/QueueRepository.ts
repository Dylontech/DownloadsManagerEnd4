// ============================================================================
// QueueRepository — Persistencia de la cola de descargas
// ============================================================================
//
// Usa la tabla `persistent_queue` creada en la migración v1 (Database.ts) que
// hasta ahora no se utilizaba. Su objetivo: que un reinicio del demonio (o un
// reinicio de sesión) no borre las descargas en curso.
//
// Las tareas terminadas NO se guardan aquí: desaparecen de la cola persistente
// y quedan en la tabla `history`, que es la fuente de verdad del historial.
//
// ============================================================================

import type { AppDatabase } from "./Database.js";
import type { DownloadTask } from "../types/index.js";

export interface PersistedQueueRow {
  id: string;
  task_json: string;
  status: string;
  created_at: number;
}

export class QueueRepository {
  constructor(private db: AppDatabase) {}

  /**
   * Inserta o actualiza una tarea de la cola.
   */
  upsert(task: DownloadTask): void {
    this.db.execute(
      `INSERT INTO persistent_queue (id, task_json, status, created_at)
       VALUES (@id, @taskJson, @status, @createdAt)
       ON CONFLICT(id) DO UPDATE SET
         task_json = excluded.task_json,
         status = excluded.status`,
      {
        id: task.id,
        taskJson: JSON.stringify(task),
        status: task.status,
        createdAt: task.createdAt ?? Date.now(),
      }
    );
  }

  /**
   * Elimina una tarea de la cola persistente (terminada, cancelada o borrada).
   */
  remove(taskId: string): void {
    this.db.execute("DELETE FROM persistent_queue WHERE id = @id", { id: taskId });
  }

  /**
   * Devuelve todas las filas ordenadas por antigüedad, que es el orden en el
   * que se deben re-encolar.
   */
  listAll(): PersistedQueueRow[] {
    return this.db.queryAll<PersistedQueueRow>(
      `SELECT id, task_json, status, created_at
       FROM persistent_queue
       ORDER BY created_at ASC`
    );
  }

  /**
   * Vacía la cola persistente (tras rehidratarla o al limpiar todo).
   */
  clear(): number {
    const result = this.db.execute("DELETE FROM persistent_queue");
    return result.changes;
  }

  count(): number {
    const row = this.db.queryOne<{ count: number }>(
      "SELECT COUNT(*) as count FROM persistent_queue"
    );
    return row?.count ?? 0;
  }
}
