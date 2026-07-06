// ============================================================================
// UrlValidator — Validación y sanitización de URLs
// ============================================================================

const MAX_URL_LENGTH = 2048;

/**
 * Valida que una URL sea segura para procesar con yt-dlp.
 */
export function validateUrl(url: string): boolean {
  if (!url || typeof url !== "string") return false;
  if (url.length > MAX_URL_LENGTH) return false;
  if (url.includes("\0")) return false;

  try {
    const parsed = new URL(url);

    // Solo permitir HTTP(S)
    if (!["http:", "https:"].includes(parsed.protocol)) return false;

    // Verificar que el hostname no sea una IP privada
    const hostname = parsed.hostname.toLowerCase();
    if (isPrivateHost(hostname)) return false;

    return true;
  } catch {
    return false;
  }
}

/**
 * Verifica si el host es una IP/rango privado o localhost.
 */
function isPrivateHost(hostname: string): boolean {
  // Localhost
  if (hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1") return true;

  // IPs privadas (IPv4)
  const ipv4Match = hostname.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (ipv4Match) {
    const [_, a, b] = ipv4Match.map(Number);
    if (a === 10) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
  }

  return false;
}

/**
 * Sanitiza los argumentos para evitar inyección de comandos.
 */
export function sanitizeArg(arg: string): string {
  // Eliminar caracteres de control y shell special chars
  return arg
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "")
    .replace(/[&|;`$(){}[\]!#~<>]/g, "")
    .trim();
}

/**
 * Extrae el dominio principal de una URL.
 */
export function extractDomain(url: string): string | null {
  try {
    const parsed = new URL(url);
    return parsed.hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}
