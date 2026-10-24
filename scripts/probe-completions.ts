#!/usr/bin/env bun
import { readFileSync, writeFileSync, renameSync } from "node:fs";

const BASE = process.env.FI_BASE ?? "https://freeinference.org/v1";
const KEY  = process.env.FREEINFERENCE_API_KEY ?? "";
const SID  = process.env.FI_SESSION_ID ?? `probe-${Date.now()}`;
const MODEL = process.env.FI_MODEL ?? "minimax-m3";
const NB = new URL("../config/notebook.json", import.meta.url).pathname;
const CFG = JSON.parse(readFileSync(new URL("../config/gate.json", import.meta.url), "utf8"));
const NARR = new RegExp(CFG.narration.actionPromises, "i");

const H = { Authorization: `Bearer ${KEY}`, "X-Session-ID": SID, "Content-Type": "application/json" };

async function call(extra: Record<string, string> = {}, body: any = {}) {
  const r = await fetch(BASE + "/chat/completions", {
    method: "POST", headers: { ...H, ...extra },
    body: JSON.stringify({ model: MODEL, temperature: 0, max_tokens: 256, ...body }),
    signal: AbortSignal.timeout(45000),
  });
  const text = await r.text();
  let j: any = null; try { j = JSON.parse(text); } catch {}
  return { status: r.status, text, j };
}

function content(j: any) { try { return j.choices[0].message.content ?? ""; } catch { return ""; } }
function hasReasoning(j: any) { return /"reasoning_content"\s*:/.test(JSON.stringify(j ?? {})); }
function ngrams(s: string, n = 3) { const w = (s.toLowerCase().match(/[a-z0-9]+/g) ?? []); const out = new Set<string>(); for (let i = 0; i + n <= w.length; i++) out.add(w.slice(i, i+n).join(" ")); return out; }
function jac(a: Set<string>, b: Set<string>) { if (!a.size || !b.size) return 0; let i = 0; for (const x of a) if (b.has(x)) i++; return i / (a.size + b.size - i); }

const offR = await call({ "X-Reasoning-Passthrough": "false" }, { messages: [{ role: "user", content: "Reply with exactly: PONG" }] });
const onR  = await call({ "X-Reasoning-Passthrough": "true"  }, { messages: [{ role: "user", content: "Reply with exactly: PONG" }] });
const honored = hasReasoning(onR.j) && !hasReasoning(offR.j);

const PROMPT = "List three ways to verify a port is listening, then stop. Do not explain.";
const texts: string[] = []; let narration = 0; let promises = 0;
for (let i = 0; i < 5; i++) {
  const r = await call({ "X-Reasoning-Passthrough": honored ? "true" : "false" },
                       { messages: [{ role: "user", content: PROMPT }], tools: [] });
  const t = content(r.j); texts.push(t);
  if (NARR.test(t)) promises++;
  const tc = (r.j?.choices?.[0]?.message?.tool_calls ?? []).length;
  if (NARR.test(t) && tc === 0) narration++;
}
const pairs: number[] = [];
for (let i = 0; i < texts.length; i++) for (let j = i+1; j < texts.length; j++) pairs.push(jac(ngrams(texts[i]), ngrams(texts[j])));
const selfNgram = pairs.length ? pairs.reduce((a,b)=>a+b,0)/pairs.length : 0;

const nb = JSON.parse(readFileSync(NB, "utf8"));
nb.session = SID;
nb.base = BASE;
nb.reasoningPassthrough = { honored, field: honored ? "reasoning_content" : null, model: MODEL };
nb.loopTendency = { selfNgram: +selfNgram.toFixed(3), semantic: null, runs: texts.length };
nb.narrationTendency = { runs: texts.length, violations: narration, actionPromises: promises };
nb.probes.push({ kind: "completions", model: MODEL, honored, selfNgram: +selfNgram.toFixed(3), narration, promises });
const tmp = NB + ".tmp"; writeFileSync(tmp, JSON.stringify(nb, null, 2)); renameSync(tmp, NB);

console.log(JSON.stringify({ honored, selfNgram: +selfNgram.toFixed(3), narration, promises }, null, 2));

const gate = JSON.parse(readFileSync(new URL("../config/gate.json", import.meta.url), "utf8"));
if (selfNgram > 0.5) { gate.proseTokenBudget = 600; gate.pivotBudget = 1; }
if (narration > 0)    { gate.narration.escalateAfter = 1; gate.narration.criticalAfter = 2; }
writeFileSync(new URL("../config/gate.json", import.meta.url), JSON.stringify(gate, null, 2));
process.exit(0);
