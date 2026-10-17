// ============================================================================
// SocketTransport — Socket Unix para el demonio independiente
// ============================================================================
//
// A diferencia del transporte stdio, aquí el backend NO es hijo de nadie: vive
// por su cuenta y admite varios clientes (p. ej. la barra lateral y el panel
// flotante de QuickShell a la vez). Si todos los clientes se desconectan, el
// servidor sigue escuchando y las descargas continúan.
//
// Protocolo: JSON-RPC 2.0 delimitado por saltos de línea, idéntico al de
// stdio, de modo que JsonRpcProtocol no necesita ningún cambio.
//
// ============================================================================

import { createServer, createConnection, type Server, type Socket as NetSocket } from "node:net";
import { chmodSync, existsSync, unlinkSync } from "node:fs";
import type { ITransport, TransportHandlers, TransportPeer } from "./Transport.js";

/** Límite defensivo: una línea sin `\n` más larga que esto se descarta. */
const MAX_LINE_BUFFER = 1024 * 1024;

interface SocketPeer extends TransportPeer {
  socket: NetSocket;
  buffer: string;
}

/**
 * Comprueba si ya hay un servidor escuchando en la ruta indicada.
 * Se usa como cerrojo de instancia única antes de arrancar el demonio.
 */
export function isSocketAlive(socketPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    if (!existsSync(socketPath)) {
      resolve(false);
      return;
    }

    const probe = createConnection(socketPath);
    let settled = false;
    const finish = (alive: boolean): void => {
      if (settled) return;
      settled = true;
      probe.removeAllListeners();
      probe.destroy();
      resolve(alive);
    };

    probe.once("connect", () => finish(true));
    probe.once("error", () => finish(false));
    // Un socket presente pero colgado (proceso zombi) no debe bloquearnos.
    setTimeout(() => finish(false), 700);
  });
}

/** Borra un socket huérfano (el proceso anterior murió sin limpiar). */
export function removeStaleSocket(socketPath: string): void {
  try {
    if (existsSync(socketPath)) {
      unlinkSync(socketPath);
    }
  } catch {
    // Si no se puede borrar, `listen` fallará y se reportará el error real.
  }
}

export class SocketTransport implements ITransport {
  private readonly socketPath: string;
  private server: Server | null = null;
  private handlers: TransportHandlers | null = null;
  private peers = new Map<string, SocketPeer>();
  private counter = 0;
  private listening = false;

  constructor(socketPath: string) {
    this.socketPath = socketPath;
  }

  get path(): string {
    return this.socketPath;
  }

  get peerCount(): number {
    return this.peers.size;
  }

  get isListening(): boolean {
    return this.listening;
  }

  start(handlers: TransportHandlers): void {
    this.handlers = handlers;
    this.server = createServer((socket) => this.accept(socket));

    this.server.on("error", (err: Error) => {
      console.error("[MediaDownloadCenter] Socket server error:", err.message);
    });

    this.server.listen(this.socketPath, () => {
      this.listening = true;
      try {
        // Solo el usuario propietario puede hablar con el demonio.
        chmodSync(this.socketPath, 0o600);
      } catch {
        // En sistemas de ficheros que no soportan permisos, seguir.
      }
      console.error(`[MediaDownloadCenter] Listening on ${this.socketPath}`);
    });
  }

  send(data: string, peer?: TransportPeer): void {
    if (peer) {
      peer.write(data);
      return;
    }
    for (const client of this.peers.values()) {
      client.write(data);
    }
  }

  stop(): void {
    for (const peer of [...this.peers.values()]) {
      try {
        peer.socket.end();
      } catch {
        // Ignorar: ya estaba cerrado.
      }
    }
    this.peers.clear();

    this.server?.close();
    this.server = null;
    this.listening = false;

    removeStaleSocket(this.socketPath);
  }

  // ─── Gestión de conexiones ─────────────────────────────────────────────

  private accept(socket: NetSocket): void {
    const id = `peer-${++this.counter}`;
    const peer: SocketPeer = {
      id,
      socket,
      buffer: "",
      write: (data: string): void => {
        if (!socket.destroyed) {
          socket.write(data);
        }
      },
    };

    socket.setEncoding("utf8");
    this.peers.set(id, peer);

    // Los fragmentos no respetan los saltos de línea: acumular y emitir solo
    // líneas completas, igual que hace el adaptador con la salida de yt-dlp.
    socket.on("data", (chunk: string) => this.consume(peer, chunk));
    socket.on("close", () => this.drop(peer));
    socket.on("error", () => this.drop(peer));

    this.handlers?.onClientConnected?.(peer);
  }

  private consume(peer: SocketPeer, chunk: string): void {
    peer.buffer += chunk;

    let index = peer.buffer.indexOf("\n");
    while (index >= 0) {
      const line = peer.buffer.slice(0, index);
      peer.buffer = peer.buffer.slice(index + 1);
      if (line.trim()) {
        this.handlers?.onLine(line, peer);
      }
      index = peer.buffer.indexOf("\n");
    }

    if (peer.buffer.length > MAX_LINE_BUFFER) {
      peer.buffer = "";
    }
  }

  private drop(peer: SocketPeer): void {
    if (!this.peers.delete(peer.id)) return;
    peer.buffer = "";
    this.handlers?.onClientDisconnected?.(peer);
  }
}
