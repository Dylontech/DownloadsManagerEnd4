// ============================================================================
// JSON-RPC 2.0 Server — Comunicación via stdin/stdout
// ============================================================================

import { createInterface } from "node:readline";
import { stdin, stderr } from "node:process";
import {
  JsonRpcRequest,
  JsonRpcResponse,
  JsonRpcNotification,
  JsonRpcErrorCode,
  createSuccessResponse,
  createErrorResponse,
  createNotification,
  serializeMessage,
  parseMessage,
} from "./JsonRpcProtocol.js";
import type { IpcHandler } from "../types/index.js";

// ─── Handler Registrado ────────────────────────────────────────────────────

interface RegisteredHandler {
  handler: IpcHandler;
  description: string;
}

// ─── Server ────────────────────────────────────────────────────────────────

export class JsonRpcServer {
  private handlers: Map<string, RegisteredHandler> = new Map();
  private notificationHandlers: Map<string, IpcHandler[]> = new Map();
  private requestIdCounter = 0;
  private pendingRequests: Map<
    number | string,
    { resolve: (result: unknown) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }
  > = new Map();
  private rl: ReturnType<typeof createInterface> | null = null;

  // ─── Registro de handlers ──────────────────────────────────────────────

  on(method: string, handler: IpcHandler, description = ""): void {
    this.handlers.set(method, { handler, description });
  }

  onNotification(method: string, handler: IpcHandler): void {
    const existing = this.notificationHandlers.get(method) ?? [];
    existing.push(handler);
    this.notificationHandlers.set(method, existing);
  }

  // ─── Envío de mensajes ─────────────────────────────────────────────────

  sendResponse(response: JsonRpcResponse): void {
    const msg = serializeMessage(response);
    stderr.write(msg, () => {});
  }

  sendNotification(method: string, params?: unknown): void {
    const notification = createNotification(method, params);
    const msg = serializeMessage(notification);
    stderr.write(msg, () => {});
  }

  // ─── Llamada remota (desde el servidor hacia el cliente) ──────────────

  async call(method: string, params?: unknown, timeout = 5000): Promise<unknown> {
    const id = ++this.requestIdCounter;
    const request: JsonRpcRequest = { jsonrpc: "2.0", id, method, params };
    stderr.write(serializeMessage(request));

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`RPC call "${method}" timed out after ${timeout}ms`));
      }, timeout);

      this.pendingRequests.set(id, { resolve, reject, timer });
    });
  }

  // ─── Inicio del servidor ──────────────────────────────────────────────

  start(): void {
    this.rl = createInterface({
      input: stdin,
      crlfDelay: Infinity,
    });

    this.rl.on("line", (line: string) => {
      this.processLine(line.trim());
    });

    this.rl.on("close", () => {
      this.handleShutdown();
    });

    // Signal ready
    this.sendNotification("server.ready", { version: "1.0.0" });
  }

  // ─── Procesamiento de línea ─────────────────────────────────────────────

  private processLine(line: string): void {
    if (!line) return;

    const msg = parseMessage(line);
    if (!msg) {
      // Línea inválida — podría ser output de yt-dlp, ignorar
      return;
    }

    if ("id" in msg && msg.id !== undefined && msg.id !== null) {
      // Es un request o response
      if ("method" in msg) {
        this.handleRequest(msg as JsonRpcRequest);
      } else {
        this.handleResponse(msg as JsonRpcResponse);
      }
    } else if ("method" in msg) {
      // Es una notificación
      this.handleNotification(msg as JsonRpcNotification);
    }
  }

  // ─── Manejo de requests entrantes ──────────────────────────────────────

  private async handleRequest(request: JsonRpcRequest): Promise<void> {
    const registered = this.handlers.get(request.method);

    if (!registered) {
      this.sendResponse(
        createErrorResponse(
          request.id,
          JsonRpcErrorCode.MethodNotFound,
          `Method not found: ${request.method}`
        )
      );
      return;
    }

    try {
      const result = await registered.handler(request.params);
      this.sendResponse(createSuccessResponse(request.id, result));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.sendResponse(
        createErrorResponse(
          request.id,
          JsonRpcErrorCode.InternalError,
          message,
          process.env.NODE_ENV === "development" ? { stack: (error as Error).stack } : undefined
        )
      );
    }
  }

  // ─── Manejo de responses (para llamadas remotas) ───────────────────────

  private handleResponse(response: JsonRpcResponse): void {
    const pending = this.pendingRequests.get(response.id!);
    if (!pending) return;

    clearTimeout(pending.timer);
    this.pendingRequests.delete(response.id!);

    if (response.error) {
      pending.reject(new Error(response.error.message));
    } else {
      pending.resolve(response.result);
    }
  }

  // ─── Manejo de notificaciones entrantes ─────────────────────────────────

  private handleNotification(notification: JsonRpcNotification): void {
    const handlers = this.notificationHandlers.get(notification.method);
    if (handlers) {
      for (const handler of handlers) {
        try {
          handler(notification.params);
        } catch {
          // Ignorar errores en notificaciones
        }
      }
    }
  }

  // ─── Shutdown ───────────────────────────────────────────────────────────

  private handleShutdown(): void {
    // Cancelar todos los pending requests
    for (const [, pending] of this.pendingRequests) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Server shutting down"));
    }
    this.pendingRequests.clear();

    this.sendNotification("server.shutdown");
    process.exit(0);
  }

  stop(): void {
    if (this.rl) {
      this.rl.close();
    }
  }
}
