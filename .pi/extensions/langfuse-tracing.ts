/**
 * Langfuse Tracing Extension for pi
 *
 * Captures every agent turn — LLM requests/responses and tool calls — and
 * sends them to your self-hosted Langfuse instance as traces, generations,
 * and spans.
 *
 * Event flow per turn:
 *   turn_start -> before_provider_request -> after_provider_response
 *     -> message_end (assistant, may contain tool_calls)
 *     -> tool_execution_start -> tool_execution_end (for each tool)
 *     -> turn_end
 *
 * Requirements (in order of precedence):
 *   1. Environment variables: LANGFUSE_SECRET_KEY, LANGFUSE_PUBLIC_KEY, LANGFUSE_BASE_URL
 *   2. Config file: ~/.pi/agent/langfuse-config.json
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Config ────────────────────────────────────────────────────────────────────

function loadConfig() {
  const envSecret = process.env.LANGFUSE_SECRET_KEY;
  const envPublic = process.env.LANGFUSE_PUBLIC_KEY;
  if (envSecret && envPublic) {
    return {
      secretKey: envSecret,
      publicKey: envPublic,
      baseUrl: process.env.LANGFUSE_BASE_URL ?? "http://localhost:3000",
    };
  }

  const configPath = join(homedir(), ".pi", "agent", "langfuse-config.json");
  if (existsSync(configPath)) {
    try {
      const raw = readFileSync(configPath, "utf-8");
      const cfg = JSON.parse(raw);
      if (cfg.secretKey && cfg.publicKey) {
        return {
          secretKey: cfg.secretKey,
          publicKey: cfg.publicKey,
          baseUrl: cfg.baseUrl ?? "http://localhost:3000",
        };
      }
    } catch (e) {
      console.error("[langfuse] failed to read config file:", String(e));
    }
  }

  return null;
}

const config = loadConfig();
const LF_SECRET = config?.secretKey ?? "";
const LF_PUBLIC = config?.publicKey ?? "";
const LF_BASE = config?.baseUrl ?? "http://localhost:3000";
const DISABLED = !LF_SECRET || !LF_PUBLIC;

// ── State ─────────────────────────────────────────────────────────────────────

let traceId: string | null = null;
let traceStartTime: string | null = null;
let turnCount = 0;
let currentGenId: string | null = null;
let reachable = true;
let unreachableWarned = false;

interface PendingGen {
  id: string;
  model: string;
  modelParameters: Record<string, unknown>;
  startTime: string;
  updated: boolean;
}

const pendingGen = new Map<number, PendingGen>();

const activeSpans = new Map<
  string,
  { id: string; name: string; args: unknown; startTime: string }
>();

const batch: Array<Record<string, unknown>> = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

// ── Helpers ───────────────────────────────────────────────────────────────────

const FETCH_TIMEOUT_MS = 2000;
let firstFailureLogged = false;

function uid(): string {
  return (
    "pi-" +
    Date.now().toString(36) +
    "-" +
    Math.random().toString(36).slice(2, 10) +
    "-" +
    Math.random().toString(36).slice(2, 6)
  );
}

function nowISO(): string {
  return new Date().toISOString();
}

function authHeader(): string {
  return `Basic ${Buffer.from(`${LF_PUBLIC}:${LF_SECRET}`, "utf-8").toString("base64")}`;
}

// ── Event Batching ────────────────────────────────────────────────────────────

let flushInFlight = false;

async function flush() {
  if (!reachable) return;
  if (batch.length === 0) return;
  if (flushInFlight) return;

  const events = batch.splice(0);
  flushInFlight = true;

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    try {
      const res = await fetch(`${LF_BASE}/api/public/ingestion`, {
        method: "POST",
        headers: {
          Authorization: authHeader(),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ batch: events }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text();
        if (!firstFailureLogged) {
          console.warn(`[langfuse] flush error ${res.status}: ${text.slice(0, 200)}`);
          firstFailureLogged = true;
        }
        if (res.status >= 500) {
          events[0] = { ...events[0], _retry: (events[0]._retry as number ?? 0) + 1 } as Record<string, unknown>;
          if ((events[0]._retry as number) <= 1) {
            batch.unshift(...events);
          }
        }
      }
    } finally {
      clearTimeout(timeout);
    }
  } catch {
    if (!firstFailureLogged) {
      console.warn("[langfuse] cannot reach server at", LF_BASE, "- tracing disabled for this session");
      firstFailureLogged = true;
    }
    reachable = false;
  } finally {
    flushInFlight = false;
    if (batch.length > 0 && reachable) {
      if (flushTimer) clearTimeout(flushTimer);
      flushTimer = setTimeout(flush, 2000);
    }
  }
}

function enqueue(event: Record<string, unknown>) {
  if (!reachable) return;
  batch.push(event);
  if (batch.length >= 15) {
    if (flushTimer) {
      clearTimeout(flushTimer);
      flushTimer = null;
    }
    flush().catch(() => {});
  } else {
    if (flushTimer) clearTimeout(flushTimer);
    flushTimer = setTimeout(() => flush().catch(() => {}), 2000);
  }
}

function flushBackground() {
  if (flushTimer) {
    clearTimeout(flushTimer);
    flushTimer = null;
  }
  flush().catch(() => {});
}

// ── Extension ─────────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  if (DISABLED) {
    if (!unreachableWarned) {
      console.warn("[langfuse] LANGFUSE_SECRET_KEY and/or LANGFUSE_PUBLIC_KEY not set - tracing disabled");
      unreachableWarned = true;
    }
    return;
  }

  pi.on("before_agent_start", async (_event) => {
    const tid = uid();
    traceId = tid;
    traceStartTime = nowISO();
    turnCount = 0;
    currentGenId = null;
    reachable = true;
    pendingGen.clear();
    activeSpans.clear();

    enqueue({
      id: uid(),
      timestamp: traceStartTime,
      type: "trace-create",
      body: {
        id: tid,
        name: (_event.prompt ?? "pi session").slice(0, 1000),
        input: _event.prompt ?? "",
        tags: ["pi-agent"],
        environment: "default",
        release: "pi-agent-v1",
      },
    });
  });

  pi.on("turn_start", async () => {
    turnCount++;
    currentGenId = null;
  });

  pi.on("before_provider_request", (event) => {
    if (!traceId) return;
    const idx = turnCount;
    const payload = event.payload as Record<string, unknown> | undefined;
    const model = typeof payload?.model === "string" ? payload.model : "unknown-model";

    const modelParams: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(payload ?? {})) {
      if (["messages", "stream", "stream_options"].includes(k)) continue;
      if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") {
        modelParams[k] = v;
      }
    }

    const genId = uid();
    currentGenId = genId;

    pendingGen.set(idx, {
      id: genId,
      model,
      modelParameters: modelParams,
      startTime: nowISO(),
      updated: false,
    });

    const messages = payload?.messages ?? [];
    const systemMsg = payload?.system ?? undefined;
    const input = systemMsg ? { system: systemMsg, messages } : messages;

    enqueue({
      id: uid(),
      timestamp: nowISO(),
      type: "generation-create",
      body: { id: genId, traceId, name: model, model, modelParameters: modelParams, input, startTime: nowISO() },
    });
  });

  pi.on("message_end", async (event) => {
    if (!traceId) return;
    if (event.message.role !== "assistant") return;

    const gen = pendingGen.get(turnCount);
    if (!gen || gen.updated) return;
    gen.updated = true;

    const msg = event.message as Record<string, unknown>;
    const output = msg.content ?? "";
    const usageRaw = msg.usage as
      | { input?: number; output?: number; total?: number; cost?: { total?: number } }
      | undefined;

    let usage: { input?: number; output?: number; total?: number; unit?: string } | undefined;
    const usageDetails: Record<string, number> = {};
    const costDetails: Record<string, number> = {};

    if (usageRaw) {
      usage = { input: usageRaw.input ?? 0, output: usageRaw.output ?? 0, total: usageRaw.total ?? 0, unit: "TOKENS" };
      usageDetails.input = usageRaw.input ?? 0;
      usageDetails.output = usageRaw.output ?? 0;
      usageDetails.total = usageRaw.total ?? 0;
      if (usageRaw.cost?.total != null) costDetails.totalCost = usageRaw.cost.total;
    }

    enqueue({
      id: uid(),
      timestamp: nowISO(),
      type: "generation-update",
      body: { id: gen.id, traceId, output, usage, usageDetails: Object.keys(usageDetails).length > 0 ? usageDetails : undefined, costDetails: Object.keys(costDetails).length > 0 ? costDetails : undefined, endTime: nowISO() },
    });
  });

  pi.on("tool_execution_start", async (event) => {
    if (!traceId) return;
    const parentId = currentGenId ?? traceId;
    const sid = uid();
    activeSpans.set(event.toolCallId, { id: sid, name: event.toolName, args: event.args, startTime: nowISO() });

    enqueue({
      id: uid(),
      timestamp: nowISO(),
      type: "span-create",
      body: { id: sid, traceId, parentObservationId: parentId, name: event.toolName, input: event.args, startTime: nowISO() },
    });
  });

  pi.on("tool_execution_end", async (event) => {
    const span = activeSpans.get(event.toolCallId);
    if (!span) return;

    enqueue({
      id: uid(),
      timestamp: nowISO(),
      type: "span-update",
      body: { id: span.id, traceId, output: event.result, level: event.isError ? "ERROR" : "DEFAULT", statusMessage: event.isError ? String(event.result) : undefined, endTime: nowISO() },
    });

    activeSpans.delete(event.toolCallId);
  });

  pi.on("turn_end", async () => {
    currentGenId = null;
    const gen = pendingGen.get(turnCount);
    if (gen && !gen.updated) {
      enqueue({
        id: uid(),
        timestamp: nowISO(),
        type: "generation-update",
        body: { id: gen.id, traceId, level: "ERROR", statusMessage: "Generation did not complete successfully", endTime: nowISO() },
      });
    }
    pendingGen.delete(turnCount);
  });

  pi.on("agent_settled", async () => {
    if (traceId) {
      enqueue({
        id: uid(),
        timestamp: nowISO(),
        type: "trace-create",
        body: { id: traceId, output: "Agent run completed" },
      });
    }
    flushBackground();

    traceId = null;
    traceStartTime = null;
    turnCount = 0;
    currentGenId = null;
    pendingGen.clear();
    activeSpans.clear();
  });

  pi.on("session_shutdown", async () => {
    flushBackground();
  });
}