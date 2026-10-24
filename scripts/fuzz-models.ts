#!/usr/bin/env bun
import { readFileSync, writeFileSync, renameSync } from "node:fs";

const BASE = process.env.FI_BASE ?? "https://freeinference.org/v1";
const KEY  = process.env.FREEINFERENCE_API_KEY ?? "";
const SID  = process.env.FI_SESSION_ID ?? `fuzz-${Date.now()}`;
const NB   = new URL("../config/notebook.json", import.meta.url).pathname;
const HDRS = { Authorization: `Bearer ${KEY}`, "X-Session-ID": SID, Accept: "*/*" };

const MATRIX = [
  "/models",
  "/models?alt=sse",
  "/models?stream=true",
  "/models?stream=1",
  "/models/stream",
  "/models/events",
  "/models:stream",
  "/models?watch=true",
  "/models/changes",
  "/model",
  "/models?category=llm",
];

type Verdict = "Buffered" | "Sse" | "SseCorrupted" | "Absent" | "Error";
type Probe = { path: string; status: number; ctype: string; bytes: number; verdict: Verdict; note: string };

function classify(status: number, ctype: string, body: string): Verdict {
  if (status === 404) return "Absent";
  if (status === 0 || status >= 500) return "Error";
  const isSse = /text\/event-stream/i.test(ctype) || /^(data|event):/m.test(body.slice(0, 512));
  if (!isSse) {
    try { const j = JSON.parse(body); return (j && (j.data || j.object)) ? "Buffered" : "Error"; }
    catch { return "Error"; }
  }
  const hasErrorFrame = /event:\s*error|\bproxy_stream_error\b|"error"\s*:/.test(body);
  const hasPartialJson = /^\s*\{/.test(body) && !/\}\s*$/.test(body.trim());
  return (hasErrorFrame || hasPartialJson) ? "SseCorrupted" : "Sse";
}

const probes: Probe[] = [];
for (const p of MATRIX) {
  let status = 0, ctype = "", body = "";
  try {
    const r = await fetch(BASE + p, { headers: HDRS, signal: AbortSignal.timeout(5000) });
    status = r.status; ctype = r.headers.get("content-type") ?? "";
    body = await r.text();
  } catch (e: any) {
    body = String(e?.message ?? e);
  }
  const verdict = classify(status, ctype, body);
  probes.push({ path: p, status, ctype, bytes: body.length, verdict, note: body.slice(0, 120).replace(/\s+/g, " ") });
  if (verdict === "Buffered") break;
}

const winner = probes.find(p => p.verdict === "Buffered")
            ?? probes.find(p => p.verdict === "SseCorrupted")
            ?? probes.find(p => p.verdict === "Sse")
            ?? probes.find(p => p.verdict === "Absent");

const nb = JSON.parse(readFileSync(NB, "utf8"));
nb.session = SID;
nb.base = BASE;
nb.framing.models = {
  verdict: winner?.verdict ?? "Absent",
  path: winner?.path ?? null,
  evidence: winner ? { status: winner.status, ctype: winner.ctype, bytes: winner.bytes } : null,
};
nb.probes = [...(nb.probes ?? []), ...probes];
const t = NB + ".tmp"; writeFileSync(t, JSON.stringify(nb, null, 2)); renameSync(t, NB);
console.log(JSON.stringify({ verdict: nb.framing.models, probes }, null, 2));
process.exit(nb.framing.models.verdict === "Buffered" ? 0 : 2);
