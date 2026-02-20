import fs from "node:fs";
import path from "node:path";
import { resolveStateDir } from "../../config/paths.js";
import { logVerbose } from "../../globals.js";

export interface IngestLogEntry {
  receivedAt: string;
  messageId: string | undefined;
  sessionKey: string | undefined;
  accountId: string | undefined;
  channel: string;
  chatType: string | undefined;
  from: string | undefined;
  to: string | undefined;
  senderId: string | undefined;
  senderName: string | undefined;
  senderE164: string | undefined;
  rawBody: string | undefined;
  body: string | undefined;
  mediaType: string | undefined;
  correlationId: string | undefined;
  originatingChannel: string | undefined;
  originatingTo: string | undefined;
}

function resolveIngestLogPath(): string {
  const envPath = process.env.OPENCLAW_INGEST_LOG_JSON_PATH?.trim();
  if (envPath) {
    return envPath;
  }
  return path.join(resolveStateDir(), "ingest-log.jsonl");
}

let ensuredDir = false;

export function appendIngestLog(entry: IngestLogEntry): void {
  const logPath = resolveIngestLogPath();
  try {
    if (!ensuredDir) {
      fs.mkdirSync(path.dirname(logPath), { recursive: true });
      ensuredDir = true;
    }
    const line = JSON.stringify(entry) + "\n";
    fs.appendFileSync(logPath, line, { encoding: "utf-8" });
    logVerbose(`ingest-only: logged message to ${logPath}`);
  } catch (err) {
    // Fail-open: never block inbound pipeline on log write failure
    logVerbose(
      `ingest-only: failed to write ingest log: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}
