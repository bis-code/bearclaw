#!/usr/bin/env python3
"""PreToolUse guard: blocks broad destructive shell commands even under
--dangerously-skip-permissions (PreToolUse hooks run regardless of permission mode).
Root cause it addresses: 2026-06-08 bypassPermissions bg agent wiping a whole projects tree.

Parser-based: the command is split into segments on UNQUOTED separators, and a
segment is only inspected when its real command word is destructive
(rm / git clean / find / chmod / chown). So `echo "rm -rf ~/foo"`, comments, and
docs are NOT flagged — only an actual `rm` invocation is. Fails OPEN on its own
errors (never blocks legit work due to a bug). Allows narrow project-local deletes."""
import sys, json, re, os, shlex

def _norm(p):
    """Normalize a path to forward slashes so depth math survives Windows
    backslash paths (C:\\Users\\x) and os.path.normpath's platform separator —
    without this, home_depth() returned None on native Windows and the
    shallow-home-delete guard silently failed OPEN (found 2026-08-16)."""
    return os.path.normpath(p).replace("\\", "/")

HOME = _norm(os.path.expanduser("~"))

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "[guard-destructive] " + reason}}))
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if data.get("tool_name") != "Bash":
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command", "")
if not cmd:
    sys.exit(0)

SYS = ("/etc", "/var", "/usr", "/bin", "/sbin", "/System", "/Library", "/opt", "/private")
SKIP_PREFIX = {"sudo", "command", "time", "nice", "nohup", "env", "exec",
               "builtin", "then", "do", "else", "elif", "\\", "xargs"}

def home_depth(t):
    rt = t.replace("${HOME}", HOME).replace("$HOME", HOME)
    rt = rt.replace("%USERPROFILE%", HOME)
    if rt.startswith("~"):
        rt = HOME + rt[1:]
    rt = _norm(rt)
    if rt == HOME:
        return 0
    if rt.startswith(HOME + "/"):
        return rt[len(HOME) + 1:].count("/") + 1
    return None

def segments(s):
    """Split into command segments on UNQUOTED ; \\n | & separators (&&/|| collapse)."""
    segs, cur, i, n, q = [], [], 0, len(s), None
    while i < n:
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(s[i + 1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c in "'\"":
            q = c; cur.append(c); i += 1; continue
        if c in ";\n|&":
            segs.append("".join(cur)); cur = []
            i += 2 if (c in "|&" and i + 1 < n and s[i + 1] == c) else 1
            continue
        cur.append(c); i += 1
    if cur:
        segs.append("".join(cur))
    return segs

def cmd_and_args(seg):
    try:
        toks = shlex.split(seg)
    except Exception:
        toks = seg.split()
    extra = []
    if "\\" in seg:
        # POSIX shlex EATS backslashes (C:\Users\x tokenizes to C:Usersx),
        # which hid Windows-style paths from every path check — fail-open on
        # exactly the machine class added 2026-08-16. Re-tokenize non-POSIX
        # and inspect those tokens too (analysis-only, strictly stricter).
        try:
            extra = shlex.split(seg, posix=False)
        except Exception:
            extra = seg.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", t) or t in SKIP_PREFIX:
            i += 1; continue
        args = toks[i + 1:] + [x for x in extra if x not in toks]
        return os.path.basename(t), args
    return None, []

def short_flags(args):
    return "".join(a[1:] for a in args if a.startswith("-") and not a.startswith("--"))

# fork bomb (distinctive enough to match the raw command)
if re.search(r":\(\)\s*\{\s*:\s*\|\s*:?\s*&\s*\}\s*;\s*:", cmd):
    deny("fork bomb pattern")

for seg in segments(cmd):
    base, args = cmd_and_args(seg)
    if not base:
        continue

    if base == "rm":
        flags = short_flags(args)
        recursive = "r" in flags or "R" in flags or "--recursive" in args
        force = "f" in flags or "--force" in args
        if not (recursive and force):
            continue
        for t in args:
            if t.startswith("-") or not t:
                continue
            if t in ("/", "/*", "~", "~/", "$HOME", "${HOME}", "..", "../*", "*", "./*"):
                deny(f"recursive force-delete of catastrophic target '{t}'")
            if re.fullmatch(r"\$\{?\w+\}?/?\*?", t):
                deny(f"rm -rf of a bare variable '{t}' (empty-expansion could hit $HOME or /)")
            if any(t == s or t.startswith(s + "/") for s in SYS):
                deny(f"recursive force-delete of system path '{t}'")
            d = home_depth(t)
            if d is not None and d <= 2:
                deny(f"recursive force-delete of shallow home path '{t}' (≤2 levels under ~, e.g. ~/foo or ~/foo/bar). "
                     f"Run it from inside the project with a relative path, or name a deeper subdir.")
            if re.match(r"^/[^/]*\*", t):
                deny(f"recursive force-delete with a top-level glob '{t}'")

    elif base == "git":
        flags = short_flags(args)
        if "clean" in args and "f" in flags and "d" in flags and "x" in flags:
            deny("git clean -fdx removes ALL untracked + ignored files. Verify the repo root, or use 'git stash -u'.")

    elif base == "find":
        if ("-delete" in args) or ("-exec" in args and "rm" in args):
            root = args[0] if (args and not args[0].startswith("-")) else ""
            if root == "/" or root.startswith(("/Users/", "~", "$HOME")):
                deny("find -delete / -exec rm over an absolute or home root. Scope it to the project.")

    elif base in ("chmod", "chown"):
        flags = short_flags(args)
        if "R" in flags or "--recursive" in args:
            # Check every non-flag token, not just the first: chmod's mode
            # ("777") or chown's owner spec ("user:group") precedes the
            # path, so stopping after the first candidate would inspect the
            # mode/owner and never reach the actual target.
            for t in args:
                if t.startswith("-"):
                    continue
                d = home_depth(t)
                if t in ("/", "~", "$HOME", "${HOME}") or (d is not None and d <= 1):
                    deny(f"recursive {base} over home/root ('{t}').")

# redirect-truncation over a home dotfile (ignore matches inside quotes; skip >> and N>)
masked = re.sub(r"'[^']*'|\"[^\"]*\"", " ", cmd)
if re.search(r"(?<![0-9>&])>(?!>)\s*(~|\$HOME|\$\{HOME\}|/Users/[^/]+)/\.\w", masked):
    deny("redirect-truncation over a home dotfile; edit the file instead of '>'.")

sys.exit(0)
