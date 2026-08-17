#!/usr/bin/env node
// notify-attention.mjs — W6 dry-run TWIN of notify-attention.sh (2026-08-17).
// NOT registered in settings.json: the shell hook stays authoritative until
// the Node port earns cutover (per-hook, tests + dual-run equivalence first).
// Why a port at all: cross-platform without BSD/GNU userland drift — Node's
// os/path/fs behave identically on macOS, Linux/WSL, and native Windows.
// Behavior mirrors the shell hook 1:1 including the CLAUDE_NOTIFY_LOG test
// seam ("title\tsubtitle\tmessage" appended instead of delivering).
import { readFileSync, existsSync, appendFileSync, readdirSync, statSync } from "node:fs";
import { execFile } from "node:child_process";
import { join, basename } from "node:path";
import os from "node:os";

function readStdin() {
  try { return readFileSync(0, "utf8"); } catch { return ""; }
}
function jqr(obj, key) {
  const v = obj?.[key];
  return typeof v === "string" && v.length ? v : "";
}

const raw = readStdin();
if (!raw.trim()) process.exit(0);
let input = {};
try { input = JSON.parse(raw); } catch { input = {}; }

const ntype = jqr(input, "notification_type");
let msg = jqr(input, "message");
const cwd = jqr(input, "cwd");
const sid = jqr(input, "session_id");
let transcript = jqr(input, "transcript_path");

let emoji, sound;
switch (ntype) {
  case "idle_prompt":
    emoji = "✋"; sound = "Glass"; if (!msg) msg = "Waiting for your input"; break;
  case "permission_prompt":
    emoji = "🔐"; sound = "Ping"; if (!msg) msg = "Needs your approval"; break;
  case "auth_success":
  case "elicitation_dialog":
  case "elicitation_complete":
  case "elicitation_response":
    process.exit(0);
  default:
    emoji = "🔔"; sound = "Glass"; if (!msg) msg = "Claude needs your attention";
}
msg = `${emoji} ${msg}`;

// Resolve transcript by session id when not provided.
if ((!transcript || !existsSync(transcript)) && sid) {
  const root = join(os.homedir(), ".claude", "projects");
  try {
    outer: for (const d of readdirSync(root)) {
      const p = join(root, d, `${sid}.jsonl`);
      if (existsSync(p)) { transcript = p; break outer; }
    }
  } catch { /* ignore */ }
}

// Session name: last custom-title, else last ai-title.
let name = "";
if (transcript && existsSync(transcript)) {
  try {
    const lines = readFileSync(transcript, "utf8").split("\n");
    for (const l of lines) {
      if (l.includes('"type":"custom-title"')) {
        try { name = JSON.parse(l).customTitle || name; } catch {}
      }
    }
    if (!name) for (const l of lines) {
      if (l.includes('"type":"ai-title"')) {
        try { name = JSON.parse(l).aiTitle || name; } catch {}
      }
    }
  } catch { /* ignore */ }
}

const project = cwd ? basename(cwd) : "Claude Code";
let br = "";
if (cwd) {
  try {
    const { execFileSync } = await import("node:child_process");
    br = execFileSync("git", ["-C", cwd, "branch", "--show-current"], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
  } catch { /* not a repo */ }
}
const short = sid ? sid.slice(0, 8) : "";

let title, sub;
if (name) { title = name; sub = project; } else { title = project; sub = ""; }
if (br) sub = sub ? `${sub} · ${br}` : br;
if (short) sub = sub ? `${sub} · #${short}` : `#${short}`;

if (process.env.CLAUDE_NOTIFY_LOG) {
  try { appendFileSync(process.env.CLAUDE_NOTIFY_LOG, `${title}\t${sub}\t${msg}\n`); } catch {}
  process.exit(0);
}

const iconDir = process.env.CLAUDE_NOTIFY_ICON_DIR || join(os.homedir(), ".claude", "assets");
const iconName = ntype === "idle_prompt" ? "notify-waiting" : ntype === "permission_prompt" ? "notify-approval" : "notify-attention";
const icon = join(iconDir, `${iconName}.png`);
const iconArgs = existsSync(icon) ? ["-contentImage", icon] : [];

function fireAndForget(cmd, args) {
  try { execFile(cmd, args, () => {}).unref(); } catch { /* absent notifier */ }
}
// Delivery mirrors the shell fallback chain; silent no-op elsewhere.
fireAndForget("terminal-notifier", ["-title", title, "-subtitle", sub, "-message", msg, "-sound", sound, ...iconArgs]);
process.exit(0);
