# OpenClaw Architecture: Agent and Auto-Reply

This document maps the runtime structure relevant to:

- understanding how messages flow through the system,
- where AI agent execution is triggered, and
- where to disable or bypass auto-reply and agent behavior.

## 1) High-level structure

Core modules involved in chat/agent behavior:

- Entrypoints:
  - `openclaw.mjs`
  - `src/entry.ts`
  - `src/cli/run-main.ts`
- Gateway runtime:
  - `src/gateway/server.impl.ts`
  - `src/gateway/server-startup.ts`
  - `src/gateway/server-channels.ts`
- Channel message ingress (example WhatsApp):
  - `src/web/auto-reply/monitor/on-message.ts`
  - `src/web/auto-reply/monitor/process-message.ts`
- Auto-reply orchestration:
  - `src/auto-reply/dispatch.ts`
  - `src/auto-reply/reply/dispatch-from-config.ts`
  - `src/auto-reply/reply/get-reply.ts`
  - `src/auto-reply/reply/get-reply-run.ts`
  - `src/auto-reply/reply/agent-runner.ts`
- Agent execution:
  - `src/commands/agent.ts`
  - `src/agents/pi-embedded.js` (called indirectly from multiple paths)
- Gateway RPC methods:
  - `src/gateway/server-methods/agent.ts`
  - `src/gateway/server-methods/chat.ts`

## 2) Runtime flow (startup -> auto reply)

### Startup

1. `openclaw.mjs` loads compiled entry.
2. `src/entry.ts` initializes runtime env and runs CLI.
3. Gateway starts via `startGatewayServer()` in `src/gateway/server.impl.ts`.
4. Sidecars start via `startGatewaySidecars()` in `src/gateway/server-startup.ts`.
5. Channel plugins start through `startChannels()` in `src/gateway/server-channels.ts`.

### Inbound message to reply (WhatsApp path)

1. Channel monitor receives message.
2. `createWebOnMessageHandler()` in `src/web/auto-reply/monitor/on-message.ts`:
   - resolves route with `resolveAgentRoute()`,
   - applies group gating,
   - calls `processMessage()`.
3. `processMessage()` in `src/web/auto-reply/monitor/process-message.ts`:
   - builds context,
   - calls buffered dispatch helper (`dispatchReplyWithBufferedBlockDispatcher`).
4. Dispatch enters `dispatchReplyFromConfig()` in `src/auto-reply/reply/dispatch-from-config.ts`.
5. `dispatchReplyFromConfig()` calls `getReplyFromConfig()` in `src/auto-reply/reply/get-reply.ts`.
6. `getReplyFromConfig()` prepares directives/session state and calls `runPreparedReply()` in `src/auto-reply/reply/get-reply-run.ts`.
7. `runPreparedReply()` calls `runReplyAgent()` in `src/auto-reply/reply/agent-runner.ts`.
8. `runReplyAgent()` executes the embedded agent run (via the agent execution layer) and returns payloads.

## 3) Where AI agent execution is invoked

Primary invocation points:

- Auto-reply path:
  - `src/auto-reply/reply/get-reply-run.ts` -> `runReplyAgent(...)`
- Direct command path:
  - `src/commands/agent.ts` -> `runEmbeddedPiAgent(...)`
- Gateway RPC path:
  - `src/gateway/server-methods/agent.ts` -> `agentCommand(...)`
  - `src/gateway/server-methods/chat.ts` -> `dispatchInboundMessage(...)` -> auto-reply pipeline

## 4) Where auto-reply is triggered

Main triggers:

- Incoming channel messages:
  - `src/web/auto-reply/monitor/on-message.ts`
- Heartbeat-generated prompts/messages:
  - `src/web/auto-reply/heartbeat-runner.ts` (calls `getReplyFromConfig(..., { isHeartbeat: true })`)
- Gateway chat send (internal channel):
  - `src/gateway/server-methods/chat.ts` (`chat.send` uses `dispatchInboundMessage(...)`)

## 5) Current built-in skip/disable controls (no code changes)

### Global channel startup skip

- `OPENCLAW_SKIP_CHANNELS=1`
- Legacy alias: `OPENCLAW_SKIP_PROVIDERS=1`
- Checked in `src/gateway/server-startup.ts`.
- Effect: channel monitors do not start, so channel-driven auto-reply does not run.

### Channel/account disable

- Channel manager checks account enabled state in `src/gateway/server-channels.ts`.
- Disabled accounts are not started (`enabled: false` behavior).
- Effect: disable specific channels/accounts without disabling gateway entirely.

### Group gating

- Group policy checks in:
  - `src/web/auto-reply/monitor/group-gating.ts`
  - `src/web/inbound/access-control.ts`
  - similar policy checks in Telegram/Slack/Signal modules.
- `groupPolicy: "disabled"` blocks group processing.

### Silent reply token

- `NO_REPLY` token in `src/auto-reply/tokens.ts`.
- Normalization strips/suppresses replies in `src/auto-reply/reply/normalize-reply.ts`.
- Effect: agent may still run, but final outbound message can be suppressed.

### Session send policy (gateway command/chat path)

- Evaluated in `src/sessions/send-policy.ts`.
- Used in `src/commands/agent.ts` and `src/gateway/server-methods/chat.ts` / `agent.ts` request paths.
- Can block delivery (`deny`) for matching sessions/channels.

## 6) Recommended bypass points (code-level, low-risk)

If your goal is a hard bypass switch, these are the most contained insertion points.

### A) Global auto-reply kill switch (best first patch)

Add an early return at top of `dispatchReplyFromConfig()` in:

- `src/auto-reply/reply/dispatch-from-config.ts`

Suggested guard:

```ts
if (process.env.OPENCLAW_DISABLE_AUTO_REPLY === "1") {
  return { queuedFinal: false, counts: params.dispatcher.getQueuedCounts() };
}
```

Why this point:

- One chokepoint for most inbound auto-reply dispatch paths.
- Avoids touching every channel implementation.

### B) Hard-disable gateway `agent` RPC

Add a guard in:

- `src/gateway/server-methods/agent.ts` (`agent` handler)

Return an error when disabled (for example `OPENCLAW_DISABLE_AGENT_RPC=1`).

Why this point:

- Prevents explicit agent invocations via gateway clients.
- Keeps chat/history endpoints intact.

### C) Hard-disable gateway `chat.send` AI execution

Add a guard in:

- `src/gateway/server-methods/chat.ts` (`chat.send` path before `dispatchInboundMessage`)

Why this point:

- Stops internal chat UI from driving AI runs, while still allowing other gateway ops.

## 7) Practical strategy for your stated goal

If your immediate goal is to "skip the ai agent and auto reply":

1. Use env/config toggles first:
   - `OPENCLAW_SKIP_CHANNELS=1` for channel auto-reply suppression.
2. Add one explicit code switch:
   - `OPENCLAW_DISABLE_AUTO_REPLY=1` in `dispatch-from-config.ts`.
3. If needed, lock down explicit gateway AI entrypoints:
   - add guards to `agent` and `chat.send` handlers.

This gives you layered control:

- channel ingestion off,
- auto-reply generation off,
- explicit RPC agent/chat invocation off.

## 8) Notes and caveats

- `NO_REPLY` suppresses output but does not inherently skip the run itself.
- Heartbeat logic can still call reply generation unless separately gated.
- `sendPolicy: deny` blocks sending in key gateway paths, but it is not a universal replacement for an auto-reply kill switch.

## 9) Ingest-only mode (`OPENCLAW_INGEST_ONLY=1`)

A strict mode that preserves all inbound preprocessing and metadata but prevents any local AI execution or auto-reply delivery. Inbound WhatsApp messages are logged to a JSONL file instead.

### Activation

Set environment variable:

```
OPENCLAW_INGEST_ONLY=1
```

Optional log path override (defaults to `~/.openclaw/ingest-log.jsonl`):

```
OPENCLAW_INGEST_LOG_JSON_PATH=/path/to/ingest.jsonl
```

### Toggle module

- `src/auto-reply/ingest-only.ts` exports `isIngestOnlyMode()`.
- Uses existing `isTruthyEnvValue()` from `src/infra/env.ts`.

### Guard locations (layered)

| File | Guard point | Effect |
|------|------------|--------|
| `src/web/auto-reply/monitor/process-message.ts` | Before `dispatchReplyWithBufferedBlockDispatcher(...)` | Logs inbound message to JSONL, returns early; all preprocessing/metadata preserved. |
| `src/auto-reply/reply/dispatch-from-config.ts` | Top of `dispatchReplyFromConfig()` | Safety net: returns `{ queuedFinal: false }` if any path still reaches this function. |
| `src/web/auto-reply/heartbeat-runner.ts` | Before `replyResolver(...)` | Skips heartbeat AI generation; emits `skipped` heartbeat event. |
| `src/gateway/server-methods/chat.ts` | `chat.send` handler, before dispatch | Rejects with error: "ingest-only mode is active". |
| `src/gateway/server-methods/agent.ts` | `agent` handler, after param validation | Rejects with error: "ingest-only mode is active". |

### What still runs in ingest-only mode

- Channel monitor startup and inbound message receipt.
- Route resolution (`resolveAgentRoute`).
- Group gating and echo detection.
- Ack reaction (`maybeSendAckReaction`).
- Inbound logging and correlation ID assignment.
- Session metadata writes (`recordSessionMetaFromInbound`).
- Context payload construction (`finalizeInboundContext`).

### What is stopped

- All reply dispatching and AI model/agent runs.
- All auto-reply message delivery (outbound).
- Heartbeat AI content generation.
- Gateway `agent` and `chat.send` AI execution paths.

### JSONL log format

Each line is a JSON object with fields:

- `receivedAt` (ISO 8601 timestamp)
- `messageId`, `sessionKey`, `accountId`, `channel`, `chatType`
- `from`, `to`, `senderId`, `senderName`, `senderE164`
- `rawBody`, `body`, `mediaType`
- `correlationId`, `originatingChannel`, `originatingTo`

### JSONL logger

- `src/web/auto-reply/ingest-log.ts` provides `appendIngestLog()`.
- Append-only; creates parent directories on first write.
- Fail-open: write failures are logged but never block the inbound pipeline or trigger AI fallback.
