// ============================================================================
// YtDlpAdapter — Capa de abstracción sobre yt-dlp
// ============================================================================

import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import { statSync } from "node:fs";
import type {
  MediaInfo,
  FormatInfo,
  SubtitleInfo,
  DownloadTask,
  DownloadProgress,
} from "../types/index.js";
import { validateUrl } from "../utils/UrlValidator.js";

// ─── Eventos de Progreso ───────────────────────────────────────────────────

export interface ProgressEvent {
  taskId: string;
  progress: DownloadProgress;
}

export interface CompletionEvent {
  taskId: string;
  filePath: string;
  fileSize: number;
}

export interface ErrorEvent {
  taskId: string;
  error: string;
  exitCode: number | null;
}

/**
 * Cookies para yt-dlp. Algunos servicios (YouTube, Instagram, Vimeo) exigen
 * sesión iniciada y responden con "Sign in to confirm you're not a bot".
 */
export interface CookieOptions {
  /** Navegador del que importar las cookies: firefox, chrome, chromium, brave, edge, opera, vivaldi */
  fromBrowser?: string;
  /** Ruta a un archivo cookies.txt (formato Netscape). Tiene prioridad sobre el navegador */
  file?: string;
}

// ─── Constantes ────────────────────────────────────────────────────────────

const YT_DLP_BIN = "yt-dlp";
const DEFAULT_TIMEOUT = 45_000; // 45s para info extraction (el cliente espera 75s)
const DOWNLOAD_TIMEOUT = 0; // Sin timeout para descargas largas
const SOCKET_TIMEOUT = 15; // yt-dlp: aborta conexiones que se quedan colgadas

// Marcador literal de las líneas de progreso (ver --progress-template)
const PROGRESS_PREFIX = "progress:";
const FILEPATH_PREFIX = "filepath:";

// ─── Adapter ───────────────────────────────────────────────────────────────

export class YtDlpAdapter extends EventEmitter {
  private activeProcesses: Map<string, ChildProcess> = new Map();
  private cookies: CookieOptions = {};

  // ─── Cookies ───────────────────────────────────────────────────────────

  /**
   * Configura las cookies usadas por todas las invocaciones de yt-dlp.
   * Vacío = sin cookies (comportamiento por defecto).
   */
  setCookieOptions(options: CookieOptions): void {
    this.cookies = {
      fromBrowser: options.fromBrowser?.trim() || undefined,
      file: options.file?.trim() || undefined,
    };
  }

  private cookieArgs(): string[] {
    if (this.cookies.file) return ["--cookies", this.cookies.file];
    if (this.cookies.fromBrowser) return ["--cookies-from-browser", this.cookies.fromBrowser];
    return [];
  }

  // ─── Extraer Información ───────────────────────────────────────────────

  /**
   * Extrae información completa de un media usando yt-dlp -J.
   */
  async extractInfo(url: string, timeout = DEFAULT_TIMEOUT): Promise<MediaInfo> {
    if (!validateUrl(url)) {
      throw new Error(`Invalid or unsafe URL: ${url}`);
    }

    const args = [
      "--no-warnings",
      "--no-progress",
      "--socket-timeout", String(SOCKET_TIMEOUT),
      "--dump-json",
      "--no-download",
      "--skip-download",
      "--ignore-errors",
      ...this.cookieArgs(),
      url,
    ];

    const result = await this.execYtDlp(args, timeout);
    const data = this.parseJsonOutput(result);

    return this.mapToMediaInfo(data, url);
  }

  // ─── Iniciar Descarga ──────────────────────────────────────────────────

  /**
   * Inicia una descarga y emite eventos de progreso.
   * Retorna el ID del proceso para poder cancelarlo/pausarlo.
   */
  startDownload(task: DownloadTask): string {
    const { options } = task;

    // Argumentos base
    const args: string[] = [
      "--no-warnings",
      "--newline",
      // Reanudar el .part existente si lo hay. Es lo que permite continuar una
      // descarga interrumpida (por ejemplo tras reiniciar el demonio) en vez
      // de empezarla de cero. yt-dlp ya lo hace por defecto; queda explícito.
      "--continue",
      // --print implica --quiet y en modo silencioso yt-dlp no imprime el
      // progreso: sin --progress la UI nunca recibe actualizaciones.
      "--progress",
      "--progress-template",
      // El prefijo antes del primer ":" es el TIPO de plantilla (no se imprime).
      // Por eso el literal "progress:" va dentro de la plantilla: es lo único
      // que permite distinguir el progreso del resto de líneas de stdout.
      "download:progress:%(progress._percent)s|%(progress._speed_bytes_per_second)s|%(progress._eta)s|%(progress._downloaded_bytes)s|%(progress._total_bytes_estimate)s|%(progress._speed_str)s|%(progress._total_bytes)s",
      "--print",
      "after_move:filepath:%(filepath)s",
      ...this.cookieArgs(),
      ...this.buildCommonArgs(options),
      options.url,
    ];

    const process = spawn(YT_DLP_BIN, args, {
      stdio: ["ignore", "pipe", "pipe"],
      timeout: DOWNLOAD_TIMEOUT,
    });

    const taskId = task.id;
    this.activeProcesses.set(taskId, process);

    let stderrBuffer = "";
    let stdoutBuffer = "";
    let pendingLine = "";
    let filePath = "";

    process.stdout?.on("data", (chunk: Buffer) => {
      const text = chunk.toString();
      stdoutBuffer += text;

      // Los fragmentos no respetan los saltos de línea: solo procesar
      // líneas completas y guardar el resto para el siguiente fragmento.
      const lines = (pendingLine + text).split("\n");
      pendingLine = lines.pop() ?? "";

      for (const line of lines) {
        if (line.startsWith(FILEPATH_PREFIX)) {
          filePath = line.slice(FILEPATH_PREFIX.length).trim();
          continue;
        }
        if (line.startsWith(PROGRESS_PREFIX)) {
          const progress = this.parseProgressLine(line.slice(PROGRESS_PREFIX.length), taskId);
          if (progress) {
            this.emit("progress", { taskId, progress } as ProgressEvent);
          }
        }
      }
    });

    process.stderr?.on("data", (chunk: Buffer) => {
      stderrBuffer += chunk.toString();
    });

    process.on("close", (exitCode) => {
      this.activeProcesses.delete(taskId);

      // Última línea sin salto final
      if (pendingLine.startsWith(FILEPATH_PREFIX)) {
        filePath = pendingLine.slice(FILEPATH_PREFIX.length).trim();
      }

      if (exitCode === 0) {
        // Buscar el path del archivo descargado
        const sizeMatch = stdoutBuffer.match(/Destination:\s*(.+)/);
        const finalPath = filePath || (sizeMatch ? sizeMatch[1].trim() : "");
        this.emit("completed", {
          taskId,
          filePath: finalPath,
          fileSize: this.readFileSize(finalPath),
        } as CompletionEvent);
      } else {
        const errorMsg = this.parseError(stderrBuffer, exitCode);
        this.emit("error", { taskId, error: errorMsg, exitCode } as ErrorEvent);
      }
    });

    process.on("error", (err) => {
      this.activeProcesses.delete(taskId);
      this.emit("error", { taskId, error: err.message, exitCode: null } as ErrorEvent);
    });

    return taskId;
  }

  // ─── Cancelar Descarga ─────────────────────────────────────────────────

  cancelDownload(taskId: string): boolean {
    const process = this.activeProcesses.get(taskId);
    if (!process) return false;

    // Un proceso detenido con SIGSTOP (pausa) no procesa SIGTERM:
    // hay que reanudarlo primero o quedaría vivo escribiendo el .part.
    process.kill("SIGCONT");
    process.kill("SIGTERM");
    setTimeout(() => {
      if (this.activeProcesses.has(taskId)) {
        process.kill("SIGKILL");
      }
    }, 3000);

    return true;
  }

  // ─── Pausar/Reanudar (via SIGSTOP/SIGCONT) ────────────────────────────

  pauseDownload(taskId: string): boolean {
    const process = this.activeProcesses.get(taskId);
    if (!process || !process.pid) return false;
    process.kill("SIGSTOP");
    return true;
  }

  resumeDownload(taskId: string): boolean {
    const process = this.activeProcesses.get(taskId);
    if (!process || !process.pid) return false;
    process.kill("SIGCONT");
    return true;
  }

  // ─── Obtener Formatos Disponibles ──────────────────────────────────────

  async getFormats(url: string): Promise<FormatInfo[]> {
    if (!validateUrl(url)) throw new Error("Invalid URL");

    const args = [
      "--no-warnings",
      "--no-progress",
      "--socket-timeout", String(SOCKET_TIMEOUT),
      "-J",
      "--no-download",
      "--skip-download",
      ...this.cookieArgs(),
      url,
    ];

    const result = await this.execYtDlp(args, DEFAULT_TIMEOUT);
    const data = this.parseJsonOutput(result);
    return (data.formats ?? []).map((f: any) => this.mapFormat(f));
  }

  // ─── Obtener Subtítulos ────────────────────────────────────────────────

  async getSubtitles(url: string): Promise<SubtitleInfo[]> {
    if (!validateUrl(url)) throw new Error("Invalid URL");

    const args = [
      "--no-warnings",
      "--no-progress",
      "--socket-timeout", String(SOCKET_TIMEOUT),
      "--list-subs",
      "--skip-download",
      "--no-download",
      ...this.cookieArgs(),
      url,
    ];

    try {
      const result = await this.execYtDlp(args, DEFAULT_TIMEOUT);
      return this.parseSubtitlesOutput(result);
    } catch {
      return [];
    }
  }

  // ─── Verificar Disponibilidad ──────────────────────────────────────────

  async checkAvailability(): Promise<boolean> {
    try {
      await this.execYtDlp(["--version"], 5000);
      return true;
    } catch {
      return false;
    }
  }

  async getVersion(): Promise<string> {
    try {
      return (await this.execYtDlp(["--version"], 5000)).trim();
    } catch {
      return "unknown";
    }
  }

  // ─── Limpieza ──────────────────────────────────────────────────────────

  killAll(): void {
    const taskIds = [...this.activeProcesses.keys()];
    for (const id of taskIds) {
      const process = this.activeProcesses.get(id);
      if (!process) continue;

      // Reanudar antes de terminar: los procesos en pausa (SIGSTOP)
      // ignorarían SIGTERM y quedarían huérfanos.
      process.kill("SIGCONT");
      process.kill("SIGTERM");
      setTimeout(() => {
        if (this.activeProcesses.has(id)) {
          process.kill("SIGKILL");
        }
      }, 2000);
    }
  }

  get activeCount(): number {
    return this.activeProcesses.size;
  }

  // ─── Métodos Privados ──────────────────────────────────────────────────

  private execYtDlp(args: string[], timeout: number): Promise<string> {
    return new Promise((resolve, reject) => {
      const startedAt = Date.now();
      const process = spawn(YT_DLP_BIN, args, {
        stdio: ["ignore", "pipe", "pipe"],
        timeout,
      });

      let stdout = "";
      let stderr = "";

      process.stdout?.on("data", (chunk: Buffer) => {
        stdout += chunk.toString();
      });

      process.stderr?.on("data", (chunk: Buffer) => {
        stderr += chunk.toString();
      });

      process.on("close", (exitCode, signal) => {
        if (exitCode === 0) {
          resolve(stdout);
          return;
        }
        // El timeout de spawn mata el proceso con SIGTERM: sin esto el
        // usuario vería un críptico "Exit code: null".
        if (signal === "SIGTERM" && Date.now() - startedAt >= timeout - 100) {
          reject(new Error(`yt-dlp no respondió en ${Math.round(timeout / 1000)}s (tiempo de espera agotado)`));
          return;
        }
        reject(new Error(this.parseError(stderr, exitCode)));
      });

      process.on("error", (err) => {
        reject(new Error(`Failed to spawn yt-dlp: ${err.message}`));
      });
    });
  }

  /**
   * Parsea el JSON de yt-dlp con un mensaje entendible cuando no hay salida.
   */
  private parseJsonOutput(raw: string): any {
    const trimmed = raw.trim();
    if (!trimmed) {
      throw new Error("yt-dlp no devolvió información del enlace (¿no disponible, privado o bloqueado por el servicio?)");
    }

    const jsonStart = trimmed.indexOf("{");
    if (jsonStart < 0) {
      throw new Error("Respuesta inesperada de yt-dlp al analizar el enlace");
    }

    try {
      return JSON.parse(trimmed.slice(jsonStart));
    } catch {
      throw new Error("Respuesta inesperada de yt-dlp al analizar el enlace");
    }
  }

  /**
   * Tamaño real del archivo descargado.
   *
   * Antes se emitía siempre `fileSize: 0` con el comentario "se actualizará
   * después", pero nadie lo actualizaba y el historial acababa usando el
   * total estimado del progreso. Con un path válido, este es el dato exacto.
   */
  private readFileSize(filePath: string): number {
    if (!filePath) return 0;
    try {
      return statSync(filePath).size;
    } catch {
      return 0;
    }
  }

  private buildCommonArgs(options: Record<string, any>): string[] {
    const args: string[] = [];

    if (options.outputPath) {
      const template = options.filename
        ? `${options.outputPath}/${options.filename}`
        : `${options.outputPath}/%(title)s.%(ext)s`;
      args.push("-o", template);
    }

    if (options.extractAudio) {
      args.push("-x");
      args.push("--audio-format", options.format);
      if (options.audioQuality) args.push("--audio-quality", options.audioQuality);
    } else if (options.customFormat) {
      args.push("-f", options.customFormat);
    } else {
      args.push("-f", this.resolveFormat(options.quality));
    }

    if (options.downloadSubtitles) {
      args.push("--write-subs", "--sub-langs", (options.subtitleLanguages ?? ["en"]).join(","));
      if (options.embedMetadata) args.push("--embed-subs");
    }
    if (options.downloadThumbnail) args.push("--write-thumbnail");
    if (options.embedThumbnail) args.push("--embed-thumbnail");
    if (options.embedMetadata) args.push("--embed-metadata");
    if (options.speedLimit && options.speedLimit > 0) args.push("--limit-rate", `${options.speedLimit}K`);
    if (options.concurrentConnections && options.concurrentConnections > 1) {
      args.push("--concurrent-fragments", String(options.concurrentConnections));
    }

    return args;
  }

  private resolveFormat(quality: string): string {
    if (quality === "auto") return "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best";
    if (quality === "custom") return "";

    const height = quality.replace("p", "");
    return `bestvideo[height<=${height}][ext=mp4]+bestaudio[ext=m4a]/best[height<=${height}][ext=mp4]/best[height<=${height}]`;
  }

  private parseProgressLine(line: string, _taskId: string): DownloadProgress | null {
    try {
      const parts = line.split("|");
      if (parts.length < 7) return null;

      return {
        percent: parseFloat(parts[0]) || 0,
        speed: parseInt(parts[1]) || 0,
        eta: parseInt(parts[2]) || 0,
        downloadedBytes: parseInt(parts[3]) || 0,
        totalBytes: parseInt(parts[6]) || parseInt(parts[4]) || 0,
        speedFormatted: parts[5]?.trim() || "",
        etaFormatted: this.formatEta(parseInt(parts[2]) || 0),
        downloadedFormatted: this.formatBytes(parseInt(parts[3]) || 0),
        totalFormatted: this.formatBytes(parseInt(parts[6]) || parseInt(parts[4]) || 0),
      };
    } catch {
      return null;
    }
  }

  private parseSubtitlesOutput(output: string): SubtitleInfo[] {
    const subtitles: SubtitleInfo[] = [];
    const lines = output.split("\n");
    let parsingSubtitles = false;

    for (const line of lines) {
      if (line.includes("Available subtitles")) {
        parsingSubtitles = true;
        continue;
      }
      if (parsingSubtitles && line.trim() && line.includes("---")) {
        parsingSubtitles = false;
        continue;
      }
      if (parsingSubtitles && line.trim()) {
        const match = line.trim().match(/^(\w+)\s+(vtt|srt|ass|txt)/);
        if (match) {
          subtitles.push({
            language: match[1],
            extension: match[2],
            isAutoGenerated: match[1].endsWith("-orig") || false,
          });
        }
      }
    }

    return subtitles;
  }

  private mapToMediaInfo(data: any, url: string): MediaInfo {
    return {
      url,
      provider: data.extractor_key?.toLowerCase() || "unknown",
      title: data.title || "Unknown Title",
      author: data.uploader || data.creator || data.channel || "Unknown",
      duration: data.duration || 0,
      thumbnail: data.thumbnail || "",
      webpageUrl: data.webpage_url || url,
      description: data.description,
      uploadDate: data.upload_date,
      viewCount: data.view_count,
      likeCount: data.like_count,
      isLive: data.is_live || false,
      formats: (data.formats ?? []).map((f: any) => this.mapFormat(f)),
      subtitles: this.mapSubtitles(data.subtitles ?? {}),
      chapters: data.chapters?.map((c: any) => ({
        title: c.title,
        startTime: c.start_time,
        endTime: c.end_time,
      })),
    };
  }

  private mapFormat(f: any): FormatInfo {
    return {
      formatId: f.format_id || "unknown",
      extension: f.ext || "unknown",
      resolution: f.resolution,
      width: f.width,
      height: f.height,
      filesize: f.filesize || 0,
      filesizeApprox: f.filesize_approx || 0,
      bitrate: f.bitrate || 0,
      audioBitrate: f.abr,
      videoBitrate: f.vbr,
      hasVideo: f.vcodec !== "none" && !!f.vcodec,
      hasAudio: f.acodec !== "none" && !!f.acodec,
      fps: f.fps,
      codec: f.vcodec,
      audioCodec: f.acodec,
      formatNote: f.format_note,
    };
  }

  private mapSubtitles(subtitles: Record<string, any[]>): SubtitleInfo[] {
    const result: SubtitleInfo[] = [];
    for (const [lang, subs] of Object.entries(subtitles)) {
      if (Array.isArray(subs) && subs.length > 0) {
        result.push({
          language: lang,
          extension: subs[0].ext || "vtt",
          isAutoGenerated: lang.includes("-orig"),
          url: subs[0].url,
        });
      }
    }
    return result;
  }

  private parseError(stderr: string, exitCode: number | null): string {
    const lines = stderr
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean);

    // yt-dlp imprime el motivo real en la línea "ERROR: ..."; el resto
    // (avisos, trazas) solo añade ruido al mensaje que ve el usuario.
    const errorLine = lines.find((l) => l.includes("ERROR:"));
    if (errorLine) {
      return errorLine.replace(/^ERROR:\s*/, "");
    }

    return lines[lines.length - 1] ?? `Exit code: ${exitCode}`;
  }

  private formatEta(seconds: number): string {
    if (seconds <= 0) return "—";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}h ${m}m ${s}s`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return "—";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let value = bytes;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return `${value.toFixed(1)} ${units[unitIndex]}`;
  }
}
