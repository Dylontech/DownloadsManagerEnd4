// ============================================================================
// Interfaz Abstracta de Provider
// ============================================================================

import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";

/**
 * Interfaz que todo provider debe implementar.
 * Cada provider es responsable de:
 * 1. Detectar si una URL le pertenece (match)
 * 2. Extraer información del media (getInfo)
 * 3. Proporcionar argumentos específicos para yt-dlp (buildDownloadArgs)
 */
export interface IProvider {
  /** Información estática del proveedor */
  readonly info: ProviderInfo;

  /**
   * Determina si la URL dada pertenece a este provider.
   * Debe usar el patrones de URL específicos del servicio.
   */
  match(url: string): boolean;

  /**
   * Extrae información detallada del media desde la URL.
   * Internamente usa YtDlpAdapter para obtener los datos.
   */
  getInfo(url: string, options?: Partial<DownloadOptions>): Promise<MediaInfo>;

  /**
   * Construye los argumentos específicos para yt-dlp.
   * Cada provider puede añadir flags particulares (ej: --extract-audio, --embed-thumbnail).
   */
  buildDownloadArgs(options: DownloadOptions): string[];
}

/**
 * Información ligera del provider (sin necesidad de instanciarlo).
 */
export interface ProviderRegistration {
  name: string;
  displayName: string;
  icon: string;
  color: string;
  urlPatterns: string[];
}
