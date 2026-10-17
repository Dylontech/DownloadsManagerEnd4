// ============================================================================
// Transport — Abstracción del canal JSON-RPC
// ============================================================================
//
// El servidor JSON-RPC no sabe nada del canal: solo habla con esta interfaz.
// Hay dos implementaciones:
//
//   · StdioTransport  → stdin/stderr de un proceso hijo de QuickShell
//                       (comportamiento histórico, `npm start`).
//   · SocketTransport → socket Unix del demonio independiente, con varios
//                       clientes simultáneos y sin morir al desconectarse.
//
// Cada conexión se representa con un TransportPeer: un objeto capaz de
// escribir de vuelta SOLO a ese cliente. Las respuestas van al peer que hizo
// la petición; las notificaciones se difunden a todos (send sin peer).
//
// ============================================================================

export interface TransportPeer {
  /** Identificador estable dentro del transporte (para logs). */
  readonly id: string;
  /** Escribe datos crudos al cliente asociado a este peer. */
  write(data: string): void;
}

export interface TransportHandlers {
  /** Una línea completa recibida de un cliente. */
  onLine(line: string, peer: TransportPeer): void;
  /** Un cliente nuevo se ha conectado (o el canal se ha abierto). */
  onClientConnected?(peer: TransportPeer): void;
  /** Un cliente se ha ido. Puede volver: el servidor decide qué hacer. */
  onClientDisconnected?(peer: TransportPeer): void;
}

export interface ITransport {
  /** Empieza a escuchar. A partir de aquí se llaman los handlers. */
  start(handlers: TransportHandlers): void;
  /**
   * Envía un mensaje ya serializado.
   * Sin `peer` se difunde a todos los clientes conectados.
   */
  send(data: string, peer?: TransportPeer): void;
  /** Cierra el canal y libera recursos (socket, PID file del sistema, etc.). */
  stop(): void;
  /** Número de clientes conectados en este momento. */
  readonly peerCount: number;
}
