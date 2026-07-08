// ============================================================================
// YtDlpAdapter — Capa de abstracción sobre yt-dlp
// ============================================================================

import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
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

// ─── Constantes ────────────────────────────────────────────────────────────

const YT_DLP_BIN = "yt-dlp";
const DEFAULT_TIMEOUT = 30_000; // 30s para info extraction
const DOWNLOAD_TIMEOUT = 0; // Sin timeout para descargas largas

// ─── Adapter ───────────────────────────────────────────────────────────────

export class YtDlpAdapter extends EventEmitter {
  private activeProcesses: Map<string, ChildProcess> = new Map();

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
      "--dump-json",
      "--no-download",
      "--skip-download",
      "--ignore-errors",
      url,
    ];

    const result = await this.execYtDlp(args, timeout);
    const data = JSON.parse(result);

    return this.mapToMediaInfo(data, url);
  }

  // ─── Iniciar Descarga ──────────────────────────────────────────────────

  /**
   * Inicia una descarga y emite eventos de progreso.
   * Retorna el ID del proceso para poder cancelarlo/pausarlo.
   */
  startDownload(task: DownloadTask): string {
    const { options } = task;

    // Obtener argumentos específicos del provider (si el provider existe en el task)
    const providerArgs: string[] = [];

    // Argumentos base
    const args: string[] = [
      "--no-warnings",
      "--newline",
      "--progress-template",
      "download:%(progress._percent)s|%(progress._speed_bytes_per_second)s|%(progress._eta)s|%(progress._downloaded_bytes)s|%(progress._total_bytes_estimate)s|%(progress._speed)s|%(progress._total_bytes)s",
      "--print",
      "after_move:filepath:%(filepath)s",
      ...providerArgs,
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
    let filePath = "";

    process.stdout?.on("data", (chunk: Buffer) => {
      const lines = chunk.toString().split("\n");
      for (const line of lines) {
        if (line.startsWith("filepath:")) {
          filePath = line.slice(9).trim();
          continue;
        }
        if (line.startsWith("download:")) {
          const progress = this.parseProgressLine(line.slice(9), taskId);
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

      if (exitCode === 0) {
        // Buscar el path del archivo descargado
        const sizeMatch = stdoutBuffer.match(/Destination:\s*(.+)/);
        const finalPath = filePath || (sizeMatch ? sizeMatch[1].trim() : "");
        this.emit("completed", {
          taskId,
          filePath: finalPath,
          fileSize: 0, // Se actualizará después
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
      "-J",
      "--no-download",
      "--skip-download",
      url,
    ];

    const result = await this.execYtDlp(args, DEFAULT_TIMEOUT);
    const data = JSON.parse(result);
    return (data.formats ?? []).map((f: any) => this.mapFormat(f));
  }

  // ─── Obtener Subtítulos ────────────────────────────────────────────────

  async getSubtitles(url: string): Promise<SubtitleInfo[]> {
    if (!validateUrl(url)) throw new Error("Invalid URL");

    const args = [
      "--no-warnings",
      "--list-subs",
      "--skip-download",
      "--no-download",
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
    for (const [id, process] of this.activeProcesses) {
      process.kill("SIGTERM");
      setTimeout(() => {
        if (this.activeProcesses.has(id)) {
          process.kill("SIGKILL");
        }
      }, 2000);
    }
    this.activeProcesses.clear();
  }

  get activeCount(): number {
    return this.activeProcesses.size;
  }

  // ─── Métodos Privados ──────────────────────────────────────────────────

  private execYtDlp(args: string[], timeout: number): Promise<string> {
    return new Promise((resolve, reject) => {
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

      process.on("close", (exitCode) => {
        if (exitCode === 0) {
          resolve(stdout);
        } else {
          reject(new Error(this.parseError(stderr, exitCode)));
        }
      });

      process.on("error", (err) => {
        reject(new Error(`Failed to spawn yt-dlp: ${err.message}`));
      });
    });
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
    const lines = stderr.split("\n").filter((l) => l.trim());
    // Buscar líneas de error relevantes
    const errorLines = lines.filter(
      (l) =>
        l.includes("ERROR:") ||
        l.includes("Error:") ||
        l.includes("WARNING:") === false
    );
    const lastError = errorLines[errorLines.length - 1] || `Exit code: ${exitCode}`;
    return lastError.trim();
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
