// ============================================================================
// StdioTransport — Canal histórico: stdin del proceso / stderr de salida
// ============================================================================
//
// Se mantiene para `npm start`, para el smoke test del instalador y para
// cualquier consumidor que lance el backend como proceso hijo y converse por
// tuberías. Solo admite un cliente (el proceso padre).
//
// Las respuestas y notificaciones salen por STDERR a propósito: stdout queda
// reservado por si en el futuro se quiere leer la salida de yt-dlp.
//
// ============================================================================

import { createInterface, type Interface } from "node:readline";
import { stdin, stderr } from "node:process";
import type { ITransport, TransportHandlers, TransportPeer } from "./Transport.js";

export class StdioTransport implements ITransport {
  private rl: Interface | null = null;
  private attached = false;

  private readonly peer: TransportPeer = {
    id: "stdio",
    write: (data: string): void => {
      stderr.write(data, () => {});
    },
  };

  get peerCount(): number {
    return this.attached ? 1 : 0;
  }

  start(handlers: TransportHandlers): void {
    this.rl = createInterface({ input: stdin, crlfDelay: Infinity });
    this.rl.on("line", (line: string) => handlers.onLine(line, this.peer));
    this.rl.on("close", () => {
      // El padre cerró las tuberías. El servidor decide si terminar o seguir.
      this.attached = false;
      handlers.onClientDisconnected?.(this.peer);
    });

    this.attached = true;
    handlers.onClientConnected?.(this.peer);
  }

  send(data: string, peer?: TransportPeer): void {
    // Con un solo cliente, cualquier destino se resuelve a la tubería única.
    (peer ?? this.peer).write(data);
  }

  stop(): void {
    this.rl?.close();
    this.rl = null;
    this.attached = false;
  }
}
