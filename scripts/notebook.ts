#!/usr/bin/env bun
import { readFileSync, writeFileSync, renameSync } from "node:fs";
const P = new URL("../config/notebook.json", import.meta.url).pathname;
function load(): any { try { return JSON.parse(readFileSync(P, "utf8")); } catch { return {}; } }
function save(o: any) { const t = P + ".tmp"; writeFileSync(t, JSON.stringify(o, null, 2)); renameSync(t, P); }
function getPath(o: any, p: string) { return p.split(".").reduce((a: any, k) => (a == null ? a : a[k]), o); }
function setPath(o: any, p: string, v: any) {
  const ks = p.split("."); let cur = o;
  for (let i = 0; i < ks.length - 1; i++) { cur[ks[i]] ??= {}; cur = cur[ks[i]]; }
  cur[ks.at(-1)!] = v;
}
const [cmd, path, raw] = process.argv.slice(2);
const nb = load();
if (cmd === "get") { console.log(JSON.stringify(getPath(nb, path ?? ""), null, 2)); }
else if (cmd === "set") { let v: any = raw; try { v = JSON.parse(raw!); } catch {} setPath(nb, path!, v); save(nb); }
else if (cmd === "push") { const arr = getPath(nb, path!) ?? []; let v: any = raw; try { v = JSON.parse(raw!); } catch {} arr.push(v); setPath(nb, path!, arr); save(nb); }
else if (cmd === "merge") { Object.assign(nb, JSON.parse(raw!)); save(nb); }
else { console.error("usage: notebook.ts get|set|push|merge ..."); process.exit(1); }
