import { isTruthyEnvValue } from "../infra/env.js";

let cachedIngestOnly: boolean | undefined;

export function isIngestOnlyMode(): boolean {
  if (cachedIngestOnly === undefined) {
    cachedIngestOnly = isTruthyEnvValue(process.env.OPENCLAW_INGEST_ONLY);
  }
  return cachedIngestOnly;
}

export function resetIngestOnlyCache(): void {
  cachedIngestOnly = undefined;
}
