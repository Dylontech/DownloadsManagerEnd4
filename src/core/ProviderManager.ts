// ============================================================================
// ProviderManager — Registro y detección de providers
// ============================================================================

import type { IProvider } from "../providers/IProvider.js";
import type { ProviderInfo, MediaInfo, DownloadOptions } from "../types/index.js";

/**
 * Gestiona el registro, detección y resolución de providers.
 * Implementa el patrón Service Locator para los providers.
 */
export class ProviderManager {
  private providers: Map<string, IProvider> = new Map();

  /**
   * Registra un provider en el gestor.
   */
  register(provider: IProvider): void {
    const name = provider.info.name.toLowerCase();
    if (this.providers.has(name)) {
      console.warn(`[ProviderManager] Provider "${name}" already registered, overwriting`);
    }
    this.providers.set(name, provider);
  }

  /**
   * Registra múltiples providers a la vez.
   */
  registerAll(providers: IProvider[]): void {
    for (const provider of providers) {
      this.register(provider);
    }
  }

  /**
   * Detecta el provider apropiado para una URL.
   * Retorna null si ningún provider coincide.
   */
  detectProvider(url: string): IProvider | null {
    for (const provider of this.providers.values()) {
      if (provider.match(url)) {
        return provider;
      }
    }
    return null;
  }

  /**
   * Obtiene un provider por nombre.
   */
  getProvider(name: string): IProvider | undefined {
    return this.providers.get(name.toLowerCase());
  }

  /**
   * Obtiene información del media detectando automáticamente el provider.
   */
  async getMediaInfo(url: string, options?: Partial<DownloadOptions>): Promise<MediaInfo> {
    const provider = this.detectProvider(url);
    if (!provider) {
      throw new Error(`No provider found for URL: ${url}`);
    }
    return provider.getInfo(url, options);
  }

  /**
   * Retorna la lista de información de todos los providers registrados.
   */
  listProviders(): ProviderInfo[] {
    return Array.from(this.providers.values()).map((p) => p.info);
  }

  /**
   * Verifica si hay providers registrados.
   */
  hasProviders(): boolean {
    return this.providers.size > 0;
  }

  /**
   * Retorna el número de providers registrados.
   */
  get count(): number {
    return this.providers.size;
  }
}
