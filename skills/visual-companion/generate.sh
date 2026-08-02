#!/usr/bin/env bash
# visual-companion: generate an interactive HTML companion from a markdown doc.
# Each "### Your notes (X)" or "### Notes section" subsection becomes an editable
# textarea persisted in localStorage. Top toolbar copies all notes to clipboard,
# downloads a merged .md, prints, or clears.
#
# Usage: generate.sh <input.md> [<output.html>]

set -euo pipefail

MD="${1:?usage: generate.sh <markdown-file> [<output-html>]}"
[ -f "$MD" ] || { echo "not a file: $MD" >&2; exit 1; }

DIR="$(cd "$(dirname "$MD")" && pwd)"
BASE="$(basename "$MD" .md)"
HTML="${2:-$DIR/$BASE.html}"

TITLE="$(grep -m1 '^# ' "$MD" | sed 's/^# //' || echo "$BASE")"

{
cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
HTML_HEAD
printf '<title>%s — visual companion</title>\n' "$(printf '%s' "$TITLE" | sed 's/[<>&"]//g')"
cat <<'HTML_HEAD2'
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown-light.min.css">
<style>
  :root { color-scheme: light; }
  body { box-sizing: border-box; min-width: 280px; max-width: 1100px; margin: 0 auto; padding: 20px 28px 60px;
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f6f8fa; }
  .markdown-body { padding: 28px 40px; background: #fff; border: 1px solid #d0d7de; border-radius: 8px;
                   box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
  .markdown-body table { display: table; width: 100%; border-collapse: collapse; }
  .markdown-body table th, .markdown-body table td { border: 1px solid #d0d7de; padding: 6px 13px; }
  .markdown-body table tr:nth-child(2n) { background: #f6f8fa; }

  .toolbar { position: sticky; top: 0; background: #fff; padding: 10px 16px; margin: -28px -40px 24px;
             border-bottom: 1px solid #d0d7de; display: flex; gap: 10px; align-items: center;
             z-index: 10; border-radius: 8px 8px 0 0; flex-wrap: wrap; }
  .toolbar button, .toolbar a { font-size: 13px; padding: 5px 12px; border: 1px solid #d0d7de; border-radius: 6px;
                                 background: #f6f8fa; color: #24292f; text-decoration: none; cursor: pointer;
                                 font-family: inherit; }
  .toolbar button:hover, .toolbar a:hover { background: #eaeef2; }
  .toolbar .primary { background: #1f883d; color: #fff; border-color: #1a7f37; }
  .toolbar .primary:hover { background: #1a7f37; }
  .toolbar .danger { background: #fff; color: #cf222e; border-color: #d0d7de; }
  .toolbar .meta { margin-left: auto; color: #57606a; font-size: 12px; }

  .notes-section { background: #fffbea; border-left: 4px solid #f5c542; padding: 10px 16px 12px;
                   margin: 14px 0 24px; border-radius: 0 6px 6px 0; }
  .notes-section .notes-hint { margin: 0 0 8px; color: #57606a; font-size: 13px; }
  .notes-section .notes-hint em { color: #57606a; }
  .notes-textarea { width: 100%; min-height: 100px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
                    font-size: 13px; line-height: 1.5; padding: 10px; border: 1px solid #d0d7de; border-radius: 6px;
                    resize: vertical; box-sizing: border-box; background: #fff; }
  .notes-textarea:focus { outline: none; border-color: #0969da; box-shadow: 0 0 0 3px rgba(9,105,218,.15); }
  .notes-actions { margin-top: 8px; display: flex; gap: 8px; align-items: center; font-size: 12px; color: #57606a; }
  .notes-actions button { font-size: 12px; padding: 3px 10px; border: 1px solid #d0d7de; border-radius: 6px;
                          background: #f6f8fa; cursor: pointer; color: #24292f; font-family: inherit; }
  .notes-actions button:hover { background: #eaeef2; }
  .notes-saved { color: #1a7f37; opacity: 0; transition: opacity .2s; }
  .notes-saved.show { opacity: 1; }
  .notes-section.has-content { border-left-color: #1a7f37; background: #f0fff4; }

  .vc-banner { background: #ddf4ff; border: 1px solid #54aeff66; padding: 8px 14px; border-radius: 6px;
               margin: 0 0 16px; font-size: 13px; color: #0969da; }
  .vc-banner code { background: #fff; padding: 1px 5px; border-radius: 3px; font-size: 12px; }
</style>
</head>
<body>
<div class="markdown-body">
  <div class="toolbar">
    <button class="primary" id="vc-copy-all">Copy all notes</button>
    <button id="vc-download">Download merged .md</button>
    <button id="vc-print">Print / PDF</button>
    <button class="danger" id="vc-clear">Clear all notes</button>
    <span class="meta">Notes persist in browser localStorage</span>
  </div>
  <div class="vc-banner">
    <strong>Visual companion.</strong> Each <em>Your notes</em> section below is an editable textarea. Type — your input auto-saves locally. When ready, click <strong>Copy all notes</strong> to paste them back to chat.
  </div>
  <div id="vc-content">Rendering…</div>
</div>

<textarea id="vc-source" style="display:none">
HTML_HEAD2
cat "$MD"
cat <<'HTML_TAIL'
</textarea>

<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js"></script>
<script>
(() => {
  const src = document.getElementById('vc-source').value;
  marked.setOptions({ gfm: true, breaks: false });
  const rawHTML = marked.parse(src);
  const safeHTML = DOMPurify.sanitize(rawHTML);
  const content = document.getElementById('vc-content');
  // Replace via a template element so we never set innerHTML on a live element with unsanitized strings
  const tpl = document.createElement('template');
  tpl.innerHTML = safeHTML;
  content.replaceChildren(...tpl.content.childNodes);

  // Storage key namespace per-file
  const docKey = location.pathname.split('/').pop() || 'doc';
  const lsPrefix = 'vc-notes:' + docKey + ':';

  // Find each "Your notes" / "Notes section" h3 and replace following siblings with a textarea
  const sectionMap = new Map();
  const headings = document.querySelectorAll('#vc-content h3');
  headings.forEach((h3, idx) => {
    const text = (h3.textContent || '').trim();
    if (!/^Your notes\b/i.test(text) && !/^Notes section\b/i.test(text)) return;

    const id = 'vc' + idx + '-' + text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

    // Collect siblings until next h1/h2/h3 or <hr>
    const toRemove = [];
    let hintNode = null;
    let sib = h3.nextElementSibling;
    while (sib && !/^H[123]$/.test(sib.tagName) && sib.tagName !== 'HR') {
      if (!hintNode && sib.tagName === 'P') hintNode = sib.cloneNode(true);
      toRemove.push(sib);
      sib = sib.nextElementSibling;
    }

    // Build the notes UI with DOM APIs (no innerHTML on dynamic content)
    const wrapper = document.createElement('div');
    wrapper.className = 'notes-section';
    wrapper.dataset.section = id;

    if (hintNode) {
      const hintP = document.createElement('p');
      hintP.className = 'notes-hint';
      // hintNode came from marked-then-sanitized HTML; clone its children
      while (hintNode.firstChild) hintP.appendChild(hintNode.firstChild);
      wrapper.appendChild(hintP);
    }

    const textarea = document.createElement('textarea');
    textarea.className = 'notes-textarea';
    textarea.dataset.section = id;
    textarea.placeholder = 'Type your notes here…';
    wrapper.appendChild(textarea);

    const actions = document.createElement('div');
    actions.className = 'notes-actions';
    const copyBtn = document.createElement('button');
    copyBtn.type = 'button';
    copyBtn.textContent = 'Copy this section';
    copyBtn.addEventListener('click', () => copySection(id));
    actions.appendChild(copyBtn);
    const savedSpan = document.createElement('span');
    savedSpan.className = 'notes-saved';
    savedSpan.id = 'saved-' + id;
    savedSpan.textContent = 'Saved ✓';
    actions.appendChild(savedSpan);
    wrapper.appendChild(actions);

    toRemove.forEach(el => el.remove());
    h3.parentNode.insertBefore(wrapper, h3.nextSibling);

    const key = lsPrefix + id;
    textarea.value = localStorage.getItem(key) || '';
    if (textarea.value.trim()) wrapper.classList.add('has-content');

    let timer;
    textarea.addEventListener('input', () => {
      localStorage.setItem(key, textarea.value);
      wrapper.classList.toggle('has-content', !!textarea.value.trim());
      savedSpan.classList.add('show');
      clearTimeout(timer);
      timer = setTimeout(() => savedSpan.classList.remove('show'), 1500);
    });

    sectionMap.set(id, { heading: text, textarea });
  });

  function copySection(id) {
    const sec = sectionMap.get(id);
    if (!sec) return;
    navigator.clipboard.writeText(sec.textarea.value).then(() => {
      const saved = document.getElementById('saved-' + id);
      const prev = saved.textContent;
      saved.textContent = 'Copied ✓';
      saved.classList.add('show');
      setTimeout(() => { saved.classList.remove('show'); saved.textContent = prev; }, 1500);
    });
  }

  function copyAll() {
    const parts = [];
    sectionMap.forEach((sec) => {
      const v = sec.textarea.value.trim();
      if (v) parts.push('## ' + sec.heading + '\n\n' + v);
    });
    const out = parts.length ? parts.join('\n\n---\n\n') : '(no notes yet)';
    navigator.clipboard.writeText(out).then(() => {
      alert('Copied ' + parts.length + ' note section' + (parts.length === 1 ? '' : 's') + ' to clipboard.');
    });
  }

  function downloadMerged() {
    let merged = src;
    const sectionRegex = /(^### (?:Your notes|Notes section)[^\n]*\n)([\s\S]*?)(?=\n---\n|\n## |\n### |$)/gm;
    const ids = Array.from(sectionMap.keys());
    let i = 0;
    merged = merged.replace(sectionRegex, (match, heading) => {
      const id = ids[i++];
      const sec = id ? sectionMap.get(id) : null;
      const v = sec ? sec.textarea.value.trim() : '';
      const body = v ? '\n' + v + '\n' : '\n*(no notes)*\n';
      return heading + body;
    });
    const blob = new Blob([merged], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = docKey.replace(/\.html$/, '') + '.with-notes.md';
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function clearAll() {
    const count = Array.from(sectionMap.values()).filter(s => s.textarea.value.trim()).length;
    if (count === 0) { alert('No notes to clear.'); return; }
    if (!confirm('Clear ' + count + ' note section' + (count === 1 ? '' : 's') + ' for this document? (cannot undo)')) return;
    sectionMap.forEach((sec, id) => {
      localStorage.removeItem(lsPrefix + id);
      sec.textarea.value = '';
      sec.textarea.closest('.notes-section').classList.remove('has-content');
    });
  }

  document.getElementById('vc-copy-all').addEventListener('click', copyAll);
  document.getElementById('vc-download').addEventListener('click', downloadMerged);
  document.getElementById('vc-print').addEventListener('click', () => window.print());
  document.getElementById('vc-clear').addEventListener('click', clearAll);
})();
</script>
</body>
</html>
HTML_TAIL
} > "$HTML"

if command -v open >/dev/null 2>&1; then
  open "$HTML"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$HTML"
fi

echo "wrote: $HTML"
