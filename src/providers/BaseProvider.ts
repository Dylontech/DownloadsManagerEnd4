// ============================================================================
// BaseProvider — Clase base para todos los providers
// ============================================================================

import type { IProvider } from "./IProvider.js";
import type {
  ProviderInfo,
  MediaInfo,
  DownloadOptions,
} from "../types/index.js";
import { QualityLevel } from "../types/index.js";

/**
 * Clase base que implementa la lógica común a todos los providers.
 * Los providers concretos extienden esta clase y sobrescriben:
 * - `match()`: detección de URLs
 * - `info`: metadatos del provider
 * - Opcionalmente `buildDownloadArgs()` para flags específicos
 */
export abstract class BaseProvider implements IProvider {
  abstract readonly info: ProviderInfo;

  abstract match(url: string): boolean;

  /**
   * Extrae info del media usando yt-dlp.
   * El adapter se pasa como dependencia (inyección de dependencia manual).
   */
  abstract getInfo(url: string, options?: Partial<DownloadOptions>): Promise<MediaInfo>;

  /**
   * Construye args base de yt-dlp.
   * Los providers pueden sobrescribir para añadir flags específicos.
   */
  buildDownloadArgs(options: DownloadOptions): string[] {
    const args: string[] = [];

    // Output template
    if (options.outputPath) {
      const template = options.filename
        ? `${options.outputPath}/${options.filename}`
        : `${options.outputPath}/%(title)s.%(ext)s`;
      args.push("-o", template);
    }

    // Formato/calidad
    if (options.extractAudio) {
      args.push("-x");
      args.push("--audio-format", options.format);
      if (options.audioQuality) {
        args.push("--audio-quality", options.audioQuality);
      }
    } else if (options.customFormat) {
      args.push("-f", options.customFormat);
    } else {
      args.push("-f", this.resolveFormatString(options));
    }

    // Subtítulos
    if (options.downloadSubtitles) {
      args.push("--write-subs", "--sub-langs", options.subtitleLanguages.join(","));
      if (options.embedMetadata) {
        args.push("--embed-subs");
      }
    }

    // Miniaturas
    if (options.downloadThumbnail) {
      args.push("--write-thumbnail");
    }
    if (options.embedThumbnail) {
      args.push("--embed-thumbnail");
    }

    // Metadatos
    if (options.embedMetadata) {
      args.push("--embed-metadata");
    }

    // Límite de velocidad
    if (options.speedLimit && options.speedLimit > 0) {
      args.push("--limit-rate", `${options.speedLimit}K`);
    }

    // Conexiones concurrentes
    if (options.concurrentConnections && options.concurrentConnections > 1) {
      args.push("--concurrent-fragments", String(options.concurrentConnections));
    }

    // La URL siempre al final
    args.push(options.url);

    return args;
  }

  /**
   * Resuelve el formato de yt-dlp basado en la calidad seleccionada.
   */
  protected resolveFormatString(options: DownloadOptions): string {
    if (options.quality === QualityLevel.Custom && options.customFormat) {
      return options.customFormat;
    }

    if (options.quality === QualityLevel.Auto) {
      return "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best";
    }

    const height = this.qualityToHeight(options.quality);
    return `bestvideo[height<=${height}][ext=mp4]+bestaudio[ext=m4a]/best[height<=${height}][ext=mp4]/best[height<=${height}]`;
  }

  /**
   * Convierte un nivel de calidad a altura en píxeles.
   */
  protected qualityToHeight(quality: QualityLevel | string): number {
    const map: Record<string, number> = {
      [QualityLevel.p144]: 144,
      [QualityLevel.p240]: 240,
      [QualityLevel.p360]: 360,
      [QualityLevel.p480]: 480,
      [QualityLevel.p720]: 720,
      [QualityLevel.p1080]: 1080,
      [QualityLevel.p1440]: 1440,
      [QualityLevel.p2160]: 2160,
      [QualityLevel.p4320]: 4320,
    };
    return map[quality] ?? 1080;
  }

  /**
   * Valida que la URL no contenga caracteres peligrosos.
   */
  protected validateUrl(url: string): boolean {
    try {
      const parsed = new URL(url);
      return ["http:", "https:"].includes(parsed.protocol);
    } catch {
      return false;
    }
  }

  /**
   * Sanitiza un nombre de archivo para eliminar caracteres problemáticos.
   */
  protected sanitizeFilename(name: string): string {
    return name.replace(/[<>:"/\\|?*\x00-\x1F]/g, "_").trim();
  }
}
