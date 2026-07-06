// ============================================================================
// ConfigService — Lógica de negocio para configuración
// ============================================================================

import { ConfigRepository } from "../db/ConfigRepository.js";
import type { AppConfig } from "../types/index.js";

export class ConfigService {
  constructor(private configRepo: ConfigRepository) {}

  /**
   * Obtiene toda la configuración.
   */
  getAll(): AppConfig {
    return this.configRepo.getAll();
  }

  /**
   * Obtiene un valor específico.
   */
  get(key: string): string | undefined {
    return this.configRepo.get(key);
  }

  /**
   * Establece un valor.
   */
  set(key: string, value: string): void {
    this.configRepo.set(key, value);
  }

  /**
   * Actualiza múltiples valores a la vez.
   */
  setMany(entries: Record<string, string>): void {
    for (const [key, value] of Object.entries(entries)) {
      this.configRepo.set(key, value);
    }
  }

  /**
   * Obtiene el path de descarga por defecto.
   */
  getDownloadPath(): string {
    return this.configRepo.getDefaultDownloadPath();
  }

  /**
   * Actualiza el path de descarga.
   */
  setDownloadPath(path: string): void {
    this.configRepo.set("default_download_path", path);
  }

  /**
   * Restaura configuración por defecto.
   */
  resetToDefaults(): void {
    this.configRepo.resetToDefaults();
  }
}
