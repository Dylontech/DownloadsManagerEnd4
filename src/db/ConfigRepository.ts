// ============================================================================
// ConfigRepository — Persistencia de configuración
// ============================================================================

import type { AppDatabase } from "./Database.js";
import type { AppConfig } from "../types/index.js";
import { VideoFormat, AudioFormat, QualityLevel, WidgetMode } from "../types/index.js";

export class ConfigRepository {
  constructor(private db: AppDatabase) {}

  /**
   * Obtiene un valor de configuración.
   */
  get(key: string): string | undefined {
    const row = this.db.queryOne<{ value: string }>(
      "SELECT value FROM config WHERE key = @key",
      { key }
    );
    return row?.value;
  }

  /**
   * Establece un valor de configuración.
   */
  set(key: string, value: string): void {
    this.db.execute(
      `INSERT INTO config (key, value, updated_at) VALUES (@key, @value, unixepoch())
       ON CONFLICT(key) DO UPDATE SET value = @value, updated_at = unixepoch()`,
      { key, value }
    );
  }

  /**
   * Obtiene múltiples valores a la vez.
   */
  getMany(keys: string[]): Record<string, string> {
    const placeholders = keys.map(() => "?").join(",");
    const rows = this.db.queryAll<{ key: string; value: string }>(
      `SELECT key, value FROM config WHERE key IN (${placeholders})`,
      keys as any
    );
    const result: Record<string, string> = {};
    for (const row of rows) {
      result[row.key] = row.value;
    }
    return result;
  }

  /**
   * Obtiene toda la configuración como objeto tipado.
   */
  getAll(): AppConfig {
    const all = this.db.queryAll<{ key: string; value: string }>("SELECT key, value FROM config");
    const map: Record<string, string> = {};
    for (const row of all) {
      map[row.key] = row.value;
    }
    return this.mapToConfig(map);
  }

  /**
   * Restaura valores por defecto.
   */
  resetToDefaults(): void {
    this.db.execute("DELETE FROM config");
    // Las defaults se insertan en la migración, la DB las recrea
    this.db.execute(`
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
        ('enable_notifications', 'true')
    `);
  }

  /**
   * Obtiene el path de descarga por defecto, expandiendo ~
   */
  getDefaultDownloadPath(): string {
    const path = this.get("default_download_path") || "~/Descargas/MediaDownloadCenter";
    return path.replace(/^~/, process.env.HOME || "/tmp");
  }

  private mapToConfig(map: Record<string, string>): AppConfig {
    return {
      defaultDownloadPath: map.default_download_path || "~/Descargas/MediaDownloadCenter",
      maxConcurrentDownloads: parseInt(map.max_concurrent_downloads) || 3,
      speedLimit: parseInt(map.speed_limit) || 0,
      maxConnections: parseInt(map.max_connections) || 4,
      autoDownloadThumbnail: map.auto_download_thumbnail !== "false",
      autoDownloadSubtitles: map.auto_download_subtitles === "true",
      autoEmbedThumbnail: map.auto_embed_thumbnail !== "false",
      autoEmbedMetadata: map.auto_embed_metadata !== "false",
      defaultVideoFormat: (map.default_video_format as VideoFormat) || VideoFormat.MP4,
      defaultAudioFormat: (map.default_audio_format as AudioFormat) || AudioFormat.MP3,
      defaultQuality: (map.default_quality as QualityLevel) || QualityLevel.Auto,
      defaultSubtitleLanguages: (map.default_subtitle_languages || "en,es").split(","),
      theme: (map.theme as "dark" | "light") || "dark",
      widgetMode: (map.widget_mode as WidgetMode) || WidgetMode.Tab,
      checkUpdates: true,
      enableNotifications: map.enable_notifications !== "false",
    };
  }
}
