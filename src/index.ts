// ============================================================================
// Media Download Center — Entry Point
// ============================================================================
//
// Inicializa todos los componentes, registra handlers IPC y
// comienza a escuchar en stdin/stdout via JSON-RPC.
//
// ============================================================================

import { homedir } from "node:os";
import { join } from "node:path";
import { existsSync, mkdirSync } from "node:fs";
import process from "node:process";
import { JsonRpcServer } from "./ipc/JsonRpcServer.js";
import { DownloadManager } from "./core/DownloadManager.js";
import { AppDatabase } from "./db/Database.js";
import { HistoryRepository } from "./db/HistoryRepository.js";
import { ConfigRepository } from "./db/ConfigRepository.js";
import { HistoryService } from "./services/HistoryService.js";
import { ConfigService } from "./services/ConfigService.js";
import { createAllProviders } from "./providers/index.js";
import { TaskStatus } from "./types/index.js";

// ─── Configuración Global ──────────────────────────────────────────────────

const DATA_DIR = join(homedir(), ".local", "share", "media-download-center");
if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true });
}

const DB_PATH = join(DATA_DIR, "data.db");

// ─── Inicialización ────────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Forzar stdout sin buffer para IPC con QuickShell
  (process.stdout as any)._handle?.setBlocking(true);

  // ── Capa de persistencia ──
  const db = new AppDatabase(DB_PATH);
  const historyRepo = new HistoryRepository(db);
  const configRepo = new ConfigRepository(db);
  const historyService = new HistoryService(historyRepo);
  const configService = new ConfigService(configRepo);

  // ── Motor de descargas ──
  const downloadManager = new DownloadManager();

  // ── Registrar providers ──
  const providers = createAllProviders(downloadManager.ytDlpAdapter);
  downloadManager.providerManager.registerAll(providers);

  // ── Verificar yt-dlp ──
  const ytDlpAvailable = await downloadManager.ytDlpAdapter.checkAvailability();
  if (!ytDlpAvailable) {
    console.error("[MediaDownloadCenter] yt-dlp is not installed or not in PATH");
    console.error("[MediaDownloadCenter] Install it with: sudo pacman -S yt-dlp");
    process.exit(1);
  }

  const ytDlpVersion = await downloadManager.ytDlpAdapter.getVersion();
  console.log(`[MediaDownloadCenter] yt-dlp version: ${ytDlpVersion}`);
  console.log(`[MediaDownloadCenter] Providers loaded: ${providers.length}`);
  console.log(`[MediaDownloadCenter] Data directory: ${DATA_DIR}`);

  // ── Servidor IPC ──
  const server = new JsonRpcServer();

  // ==========================================================================
  // REGISTRO DE HANDLERS JSON-RPC
  // ==========================================================================

  // ─── Sistema ─────────────────────────────────────────────────────────────

  server.on("ping", () => ({
    status: "ok",
    timestamp: Date.now(),
    ytDlpVersion,
    uptime: process.uptime(),
  }), "Health check");

  // ─── Providers ───────────────────────────────────────────────────────────

  server.on("providers.list", () => {
    return downloadManager.listProviders();
  }, "List all registered providers");

  server.on("providers.detect", (params: { url: string }) => {
    const { url } = params as { url: string };
    const provider = downloadManager.detectProvider(url);
    return provider ?? { error: "No provider found" };
  }, "Detect provider for URL");

  // ─── Media Info ──────────────────────────────────────────────────────────

  server.on("media.info", async (params: { url: string }) => {
    const { url } = params as { url: string };
    return downloadManager.getMediaInfo(url);
  }, "Get media information from URL");

  server.on("media.formats", async (params: { url: string }) => {
    const { url } = params as { url: string };
    return downloadManager.getFormats(url);
  }, "Get available formats for URL");

  server.on("media.subtitles", async (params: { url: string }) => {
    const { url } = params as { url: string };
    return downloadManager.getSubtitles(url);
  }, "Get available subtitles for URL");

  // ─── Descargas ───────────────────────────────────────────────────────────

  server.on("download.start", async (params: {
    url: string;
    format?: string;
    quality?: string;
    extractAudio?: boolean;
    outputPath?: string;
    filename?: string;
    downloadSubtitles?: boolean;
    subtitleLanguages?: string[];
    downloadThumbnail?: boolean;
    embedThumbnail?: boolean;
    embedMetadata?: boolean;
    speedLimit?: number;
    concurrentConnections?: number;
    customFormat?: string;
    audioQuality?: string;
  }) => {
    const config = configService.getAll();
    const p = params as NonNullable<typeof params>;

    const task = await downloadManager.startDownload({
      url: p.url,
      format: (p.format as any) || config.defaultVideoFormat,
      quality: (p.quality as any) || config.defaultQuality,
      extractAudio: p.extractAudio ?? false,
      outputPath: p.outputPath || configService.getDownloadPath(),
      filename: p.filename,
      downloadSubtitles: p.downloadSubtitles ?? config.autoDownloadSubtitles,
      subtitleLanguages: p.subtitleLanguages || config.defaultSubtitleLanguages,
      downloadThumbnail: p.downloadThumbnail ?? config.autoDownloadThumbnail,
      embedThumbnail: p.embedThumbnail ?? config.autoEmbedThumbnail,
      embedMetadata: p.embedMetadata ?? config.autoEmbedMetadata,
      speedLimit: p.speedLimit || config.speedLimit,
      concurrentConnections: p.concurrentConnections || config.maxConnections,
      customFormat: p.customFormat,
      audioQuality: p.audioQuality,
    });

    return {
      taskId: task.id,
      status: task.status,
      mediaInfo: task.mediaInfo
        ? {
            title: task.mediaInfo.title,
            author: task.mediaInfo.author,
            duration: task.mediaInfo.duration,
            thumbnail: task.mediaInfo.thumbnail,
          }
        : null,
    };
  }, "Start a download");

  server.on("download.pause", (params: { taskId: string }) => {
    const { taskId } = params as { taskId: string };
    return { success: downloadManager.pauseDownload(taskId) };
  }, "Pause a download");

  server.on("download.resume", (params: { taskId: string }) => {
    const { taskId } = params as { taskId: string };
    return { success: downloadManager.resumeDownload(taskId) };
  }, "Resume a paused download");

  server.on("download.cancel", (params: { taskId: string }) => {
    const { taskId } = params as { taskId: string };
    return { success: downloadManager.cancelDownload(taskId) };
  }, "Cancel a download");

  server.on("download.remove", (params: { taskId: string }) => {
    const { taskId } = params as { taskId: string };
    return { success: downloadManager.removeDownload(taskId) };
  }, "Remove a task from queue");

  server.on("download.list", (params?: { status?: string }) => {
    const p = params as { status?: string } | undefined;
    const status = p?.status ? (p.status as TaskStatus) : undefined;
    const tasks = downloadManager.listTasks(status);
    return tasks.map((t) => ({
      id: t.id,
      status: t.status,
      progress: t.progress,
      options: {
        url: t.options.url,
        format: t.options.format,
        quality: t.options.quality,
        extractAudio: t.options.extractAudio,
      },
      mediaInfo: t.mediaInfo
        ? {
            title: t.mediaInfo.title,
            author: t.mediaInfo.author,
            duration: t.mediaInfo.duration,
            thumbnail: t.mediaInfo.thumbnail,
          }
        : null,
      createdAt: t.createdAt,
      error: t.error,
      retries: t.retries,
    }));
  }, "List download tasks");

  server.on("download.get", (params: { taskId: string }) => {
    const { taskId } = params as { taskId: string };
    const task = downloadManager.getTask(taskId);
    if (!task) return null;
    return {
      id: task.id,
      status: task.status,
      progress: task.progress,
      options: task.options,
      mediaInfo: task.mediaInfo,
      createdAt: task.createdAt,
      completedAt: task.completedAt,
      filePath: task.filePath,
      fileSize: task.fileSize,
      error: task.error,
      retries: task.retries,
    };
  }, "Get a specific download task");

  // ─── Progreso (suscripción vía notificaciones) ──────────────────────────

  downloadManager.downloadQueue.on("task.progress", (taskId, progress) => {
    server.sendNotification("download.progress", { taskId, progress });
  });

  downloadManager.downloadQueue.on("task.status", (taskId, status, previous) => {
    server.sendNotification("download.status", { taskId, status, previous });

    // Si completó, registrar en historial
    if (status === TaskStatus.Completed) {
      const task = downloadManager.getTask(taskId);
      if (task) {
        try {
          historyService.recordDownload(task);
        } catch (err) {
          console.error("[MediaDownloadCenter] Error recording history:", err);
        }
        server.sendNotification("download.completed", {
          taskId,
          title: task.mediaInfo?.title || "",
          filePath: task.filePath,
        });
      }
    }

    if (status === TaskStatus.Failed) {
      const task = downloadManager.getTask(taskId);
      server.sendNotification("download.failed", {
        taskId,
        error: task?.error || "Unknown error",
      });
    }
  });

  downloadManager.downloadQueue.on("queue.drained", () => {
    server.sendNotification("queue.drained");
  });

  // ─── Historial ───────────────────────────────────────────────────────────

  server.on("history.list", (params?: { limit?: number; offset?: number }) => {
    const p = params as { limit?: number; offset?: number } | undefined;
    return historyService.listRecent(p?.limit ?? 50, p?.offset ?? 0);
  }, "List download history");

  server.on("history.favorites", (params?: { limit?: number; offset?: number }) => {
    const p = params as { limit?: number; offset?: number } | undefined;
    return historyService.listFavorites(p?.limit ?? 50, p?.offset ?? 0);
  }, "List favorite downloads");

  server.on("history.search", (params: { query: string }) => {
    const { query } = params as { query: string };
    return historyService.search(query);
  }, "Search history");

  server.on("history.toggleFavorite", (params: { id: number }) => {
    const { id } = params as { id: number };
    return { success: historyService.toggleFavorite(id) };
  }, "Toggle favorite status");

  server.on("history.delete", (params: { id: number }) => {
    const { id } = params as { id: number };
    return { success: historyService.deleteEntry(id) };
  }, "Delete history entry");

  server.on("history.clear", () => {
    return { deleted: historyService.clearAll() };
  }, "Clear all history");

  server.on("history.count", () => {
    return { count: historyService.count() };
  }, "Get history count");

  // ─── Configuración ───────────────────────────────────────────────────────

  server.on("config.get", (params?: { key?: string }) => {
    const p = params as { key?: string } | undefined;
    if (p?.key) {
      return { [p.key]: configService.get(p.key) };
    }
    return configService.getAll();
  }, "Get configuration");

  server.on("config.set", (params: { key: string; value: string } | Record<string, string>) => {
    const p = params as Record<string, string>;
    if ("key" in p && "value" in p) {
      configService.set(p.key, p.value);
      return { success: true };
    }
    configService.setMany(p);
    return { success: true };
  }, "Set configuration");

  server.on("config.reset", () => {
    configService.resetToDefaults();
    return { success: true };
  }, "Reset configuration to defaults");

  // ─── Estado del Sistema ──────────────────────────────────────────────────

  server.on("system.status", () => {
    return {
      ...downloadManager.getSystemStatus(),
      historyCount: historyService.count(),
      dataDir: DATA_DIR,
    };
  }, "Get system status");

  server.on("system.clearCompleted", () => {
    return { removed: downloadManager.clearCompleted() };
  }, "Clear completed downloads from queue");

  // ─── Iniciar ─────────────────────────────────────────────────────────────

  console.log("[MediaDownloadCenter] Starting IPC server...");
  // Debug: escribir también a stderr para verificar pipes
  console.error("[MediaDownloadCenter] stderr: server starting");
  process.stderr.write("STDERR_READY_TEST\n");
  server.start();

  // Heartbeat a stderr cada 5s para verificar que el proceso vive
  setInterval(() => {
    process.stderr.write("HEARTBEAT\n");
  }, 5000);

  // Manejar cierre graceful
  const shutdown = () => {
    console.log("[MediaDownloadCenter] Shutting down...");
    downloadManager.destroy();
    db.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  process.on("SIGHUP", shutdown);
}

main().catch((err) => {
  console.error("[MediaDownloadCenter] Fatal error:", err);
  process.exit(1);
});
