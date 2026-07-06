// ============================================================================
// JSON-RPC 2.0 Protocol — Tipos y utilidades
// ============================================================================

// ─── Códigos de Error JSON-RPC ─────────────────────────────────────────────

export enum JsonRpcErrorCode {
  ParseError = -32700,
  InvalidRequest = -32600,
  MethodNotFound = -32601,
  InvalidParams = -32602,
  InternalError = -32603,
  // Custom codes (range -32000 to -32099)
  ProviderNotFound = -32000,
  DownloadFailed = -32001,
  InvalidUrl = -32002,
  QueueFull = -32003,
  DownloadNotFound = -32004,
  ValidationError = -32005,
}

// ─── Tipos Base ────────────────────────────────────────────────────────────

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: number | string | null;
  method: string;
  params?: unknown;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: number | string | null;
  result?: unknown;
  error?: JsonRpcError;
}

export interface JsonRpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

// ─── Factory ───────────────────────────────────────────────────────────────

export function createSuccessResponse(
  id: number | string | null,
  result: unknown
): JsonRpcResponse {
  return { jsonrpc: "2.0", id, result };
}

export function createErrorResponse(
  id: number | string | null,
  code: number,
  message: string,
  data?: unknown
): JsonRpcResponse {
  return { jsonrpc: "2.0", id, error: { code, message, data } };
}

export function createNotification(
  method: string,
  params?: unknown
): JsonRpcNotification {
  return { jsonrpc: "2.0", method, params };
}

// ─── Serialización ─────────────────────────────────────────────────────────

export function serializeMessage(msg: JsonRpcRequest | JsonRpcResponse | JsonRpcNotification): string {
  return JSON.stringify(msg) + "\n";
}

export function parseMessage(line: string): JsonRpcRequest | JsonRpcResponse | JsonRpcNotification | null {
  try {
    const parsed = JSON.parse(line);
    if (parsed && typeof parsed === "object" && parsed.jsonrpc === "2.0") {
      return parsed as JsonRpcRequest | JsonRpcResponse | JsonRpcNotification;
    }
    return null;
  } catch {
    return null;
  }
}
