#!/usr/bin/env bun
/**
 * narration-guard.ts — run-scoped narration + semantic brake + cold-tool re-rank.
 * stdin:  one JSON turn
 * stdout: { action: "accept" | "continue", reason, inject? }
 */
import { readFileSync } from "node:fs";

const CFG = JSON.parse(
  readFileSync(new URL("../config/gate.json", import.meta.url), "utf8"),
);
const NARR = new RegExp(CFG.narration.actionPromises, "i");
const PIVOT =
  /\b(oh wait|wait|actually|hold on|let me reconsider|hmm|no no|i mean|scratch that|let me think|recalibrat)\b/gi;

type Turn = {
  turn: number;
  runId: string;
  reasoning?: string;
  text?: string;
  toolCalls?: { name: string; ok?: boolean }[];
  receipts?: string[];
  priorReasoning?: string[];
  toolHistory?: string[];
};

function words(s = "") {
  return new Set(
    (s.toLowerCase().match(/[a-z0-9_./:-]+/g) ?? []).filter(
      (w) => w.length > 2,
    ),
  );
}
function jac(a: Set<string>, b: Set<string>) {
  if (!a.size || !b.size) return 0;
  let i = 0;
  for (const x of a) if (b.has(x)) i++;
  return i / (a.size + b.size - i);
}
function tokens(s = "") {
  return Math.ceil(s.length / 4);
}
function pivots(s = "") {
  return (s.match(PIVOT) ?? []).length;
}

const raw = await Bun.stdin.text();
const t = JSON.parse(raw) as Turn;
const prose = `${t.reasoning ?? ""}\n${t.text ?? ""}`;
const calls = t.toolCalls ?? [];
const receipts = t.receipts ?? [];

if (NARR.test(prose) && calls.length === 0 && receipts.length === 0) {
  console.log(
    JSON.stringify({
      action: "continue",
      reason: "narration",
      inject:
        "NARRATION_GUARD: action promise with zero tool calls in this runId. End this turn with a ToolCall or a RaceTuple. Prose is not a constructor.",
    }),
  );
  process.exit(0);
}

if (pivots(prose) >= CFG.pivotBudget) {
  console.log(
    JSON.stringify({
      action: "continue",
      reason: "pivot",
      inject:
        "RACE_TUPLE required. Stop prose. Exactly 3 orthogonal candidates, each with a command, a falsifier, and a cost bound. Run via scripts/race-run.sh. Winner = fastest rc=0 with a receipt.",
    }),
  );
  process.exit(0);
}

const prior = t.priorReasoning ?? [];
const cur = words(prose);
if (prior.some((p) => jac(words(p), cur) >= CFG.repetitionJaccard)) {
  const cold = (t.toolHistory ?? []).slice(-CFG.coldTool.lookbackTurns);
  console.log(
    JSON.stringify({
      action: "continue",
      reason: "repetition",
      inject: `ORTHOGONAL_FORK + COLD_TOOL_RERANK required. Repetition detected. Fork 3 disjoint scopes (A read-only evidence, B /tmp repro, C counterexample). Additionally re-rank cold tools not used in the last ${CFG.coldTool.lookbackTurns} turns: ${JSON.stringify(cold)}. Models over-select recent tools (EMNLP 2026); surface the cold candidate explicitly.`,
    }),
  );
  process.exit(0);
}

if (tokens(prose) > CFG.proseTokenBudget) {
  console.log(
    JSON.stringify({
      action: "continue",
      reason: "budget",
      inject:
        "RACE_TUPLE required. Prose budget exceeded. 3 orthogonal candidates, each with a falsifier.",
    }),
  );
  process.exit(0);
}

console.log(
  JSON.stringify({
    action: "accept",
    reason: calls.length || receipts.length ? "receipt" : "under-budget",
  }),
);
