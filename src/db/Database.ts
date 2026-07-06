// ============================================================================
// Database — SQLite connection and migrations
// ============================================================================

import Database from "better-sqlite3";
import { mkdirSync, existsSync } from "node:fs";
import { dirname } from "node:path";

export class AppDatabase {
  private db: Database.Database;

  constructor(dbPath: string) {
    // Ensure directory exists
    const dir = dirname(dbPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    this.db = new Database(dbPath);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("foreign_keys = ON");
    this.migrate();
  }

  private migrate(): void {
    // Create schema version table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY,
        applied_at TEXT DEFAULT (datetime('now'))
      );
    `);

    const currentVersion = this.db.prepare(
      "SELECT MAX(version) as version FROM schema_version"
    ).get() as { version: number | null };

    const version = currentVersion?.version ?? 0;

    if (version < 1) {
      this.migrationV1();
    }
    // Future migrations go here (v2, v3, ...)
  }

  private migrationV1(): void {
    this.db.exec(`
      -- Historial de descargas
      CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT NOT NULL UNIQUE,
        url TEXT NOT NULL,
        provider TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        format TEXT NOT NULL DEFAULT '',
        quality TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        thumbnail TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'completed',
        error TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      );

      -- Favoritos (vista materializada para joins rápidos)
      CREATE INDEX IF NOT EXISTS idx_history_favorite ON history(is_favorite);
      CREATE INDEX IF NOT EXISTS idx_history_created ON history(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_history_provider ON history(provider);
      CREATE INDEX IF NOT EXISTS idx_history_status ON history(status);

      -- Cola persistente (para recuperación en crash)
      CREATE TABLE IF NOT EXISTS persistent_queue (
        id TEXT PRIMARY KEY,
        task_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        created_at INTEGER NOT NULL
      );

      -- Configuración
      CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (unixepoch())
      );

      -- Insertar configuración por defecto
      INSERT OR IGNORE INTO config (key, value) VALUES
        ('default_download_path', '~/Descargas/MediaDownloadCenter'),
        ('max_concurrent_downloads', '3'),
        ('speed_limit', '0'),
        ('max_connections', '4'),
        ('auto_download_thumbnail', 'true'),
        ('auto_download_subtitles', 'false'),
        ('auto_embed_thumbnail', 'true'),
        ('auto_embed_metadata', 'true'),
        ('default_video_format', 'mp4'),
        ('default_audio_format', 'mp3'),
        ('default_quality', 'auto'),
        ('default_subtitle_languages', 'en,es'),
        ('theme', 'dark'),
        ('widget_mode', 'tab'),
        ('enable_notifications', 'true');

      -- Schema version
      INSERT INTO schema_version (version) VALUES (1);
    `);
  }

  // ─── Accessors ────────────────────────────────────────────────────────

  get raw(): Database.Database {
    return this.db;
  }

  /**
   * Ejecuta una consulta de lectura y retorna un solo resultado.
   */
  queryOne<T = any>(sql: string, params?: Record<string, unknown>): T | undefined {
    const stmt = this.db.prepare(sql);
    return stmt.get(params ?? {}) as T | undefined;
  }

  /**
   * Ejecuta una consulta de lectura y retorna todos los resultados.
   */
  queryAll<T = any>(sql: string, params?: Record<string, unknown>): T[] {
    const stmt = this.db.prepare(sql);
    return stmt.all(params ?? {}) as T[];
  }

  /**
   * Ejecuta una consulta de escritura.
   */
  execute(sql: string, params?: Record<string, unknown>): Database.RunResult {
    const stmt = this.db.prepare(sql);
    return stmt.run(params ?? {});
  }

  /**
   * Ejecuta múltiples operaciones en una transacción.
   */
  transaction<T>(fn: () => T): T {
    return this.db.transaction(fn)();
  }

  /**
   * Cierra la conexión a la base de datos.
   */
  close(): void {
    this.db.close();
  }
}
