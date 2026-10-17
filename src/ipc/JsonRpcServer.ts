// ============================================================================
// JSON-RPC 2.0 Server — Comunicación a través de un transporte inyectable
// ============================================================================
//
// El transporte decide el canal: stdio (proceso hijo de QuickShell) o socket
// Unix (demonio independiente). El servidor solo conoce la interfaz ITransport,
// de modo que la misma lógica de handlers sirve para `npm start` y para el modo
// --daemon. En modo daemon la marcha de un cliente NO termina el proceso.
//
// ============================================================================

import { SERVER_VERSION } from "./version.js";
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
import type { ITransport, TransportPeer } from "./Transport.js";
import type { IpcHandler } from "../types/index.js";

// ─── Handler Registrado ────────────────────────────────────────────────────

interface RegisteredHandler {
  handler: IpcHandler;
  description: string;
}

// ─── Opciones ──────────────────────────────────────────────────────────────

export interface JsonRpcServerOptions {
  /**
   * true  → si se cierra el canal de entrada, el proceso termina (modo stdio).
   * false → modo daemon: el cliente puede marcharse y el trabajo continúa.
   * Por defecto false.
   */
  exitOnClientDisconnect?: boolean;
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
  private transport: ITransport;
  private exitOnClientDisconnect: boolean;
  /** Último cliente visto: destino por defecto de las respuestas. */
  private lastPeer: TransportPeer | null = null;

  constructor(transport: ITransport, options: JsonRpcServerOptions = {}) {
    this.transport = transport;
    this.exitOnClientDisconnect = options.exitOnClientDisconnect ?? false;
  }

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

  sendResponse(response: JsonRpcResponse, peer?: TransportPeer): void {
    this.transport.send(serializeMessage(response), peer ?? this.lastPeer ?? undefined);
  }

  sendNotification(method: string, params?: unknown): void {
    const notification = createNotification(method, params);
    // Sin peer destino: el transporte lo difunde a todos los clientes.
    this.transport.send(serializeMessage(notification));
  }

  // ─── Llamada remota (desde el servidor hacia el cliente) ──────────────

  async call(method: string, params?: unknown, timeout = 5000): Promise<unknown> {
    const id = ++this.requestIdCounter;
    const request: JsonRpcRequest = { jsonrpc: "2.0", id, method, params };
    this.transport.send(serializeMessage(request), this.lastPeer ?? undefined);

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
    this.transport.start({
      onLine: (line: string, peer: TransportPeer) => {
        this.lastPeer = peer;
        this.processLine(line.trim(), peer);
      },
      onClientConnected: (peer: TransportPeer) => {
        // Con varios clientes posibles (barra lateral y panel flotante a la
        // vez), cada uno necesita su propio `server.ready`.
        this.transport.send(
          serializeMessage(
            createNotification("server.ready", {
              version: SERVER_VERSION,
              pid: process.pid,
              transport: this.transport.constructor.name,
            })
          ),
          peer
        );
      },
      onClientDisconnected: () => {
        this.handleClientDisconnected();
      },
    });
  }

  // ─── Procesamiento de línea ─────────────────────────────────────────────

  private processLine(line: string, peer: TransportPeer): void {
    if (!line) return;

    const msg = parseMessage(line);
    if (!msg) {
      // Línea inválida — podría ser output de yt-dlp, ignorar
      return;
    }

    if ("id" in msg && msg.id !== undefined && msg.id !== null) {
      // Es un request o response
      if ("method" in msg) {
        this.handleRequest(msg as JsonRpcRequest, peer);
      } else {
        this.handleResponse(msg as JsonRpcResponse);
      }
    } else if ("method" in msg) {
      // Es una notificación
      this.handleNotification(msg as JsonRpcNotification);
    }
  }

  // ─── Manejo de requests entrantes ──────────────────────────────────────

  private async handleRequest(request: JsonRpcRequest, peer: TransportPeer): Promise<void> {
    const registered = this.handlers.get(request.method);

    if (!registered) {
      this.sendResponse(
        createErrorResponse(
          request.id,
          JsonRpcErrorCode.MethodNotFound,
          `Method not found: ${request.method}`
        ),
        peer
      );
      return;
    }

    try {
      const result = await registered.handler(request.params);
      this.sendResponse(createSuccessResponse(request.id, result), peer);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.sendResponse(
        createErrorResponse(
          request.id,
          JsonRpcErrorCode.InternalError,
          message,
          process.env.NODE_ENV === "development" ? { stack: (error as Error).stack } : undefined
        ),
        peer
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

  // ─── Desconexión de clientes ────────────────────────────────────────────

  private handleClientDisconnected(): void {
    // Puede quedar otro cliente conectado: no hacer nada hasta que se vayan
    // todos.
    if (this.transport.peerCount > 0) return;

    if (this.exitOnClientDisconnect) {
      // Modo stdio histórico: sin padre no hay nada que hacer.
      for (const [, pending] of this.pendingRequests) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Server shutting down"));
      }
      this.pendingRequests.clear();
      this.sendNotification("server.shutdown");
      process.exit(0);
    }

    // Modo daemon: esto ocurre cada vez que se cierra la barra lateral o el
    // panel flotante. El trabajo en curso NO se cancela; solo se descarta el
    // peer que se ha ido. La UI se resincroniza al reconectar.
    this.lastPeer = null;
    console.error("[MediaDownloadCenter] Cliente desconectado: el daemon sigue activo");
  }

  /**
   * Cierre ordenado: avisa a los clientes y libera el transporte.
   * No llama a process.exit(): de eso se encarga el arranque, que además debe
   * cerrar la base de datos y terminar los procesos de yt-dlp.
   */
  shutdown(): void {
    this.sendNotification("server.shutdown");
    this.transport.stop();
  }

  stop(): void {
    this.transport.stop();
  }
}
