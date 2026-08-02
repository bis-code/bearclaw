---
name: visual-companion
description: Use when the user wants to view a markdown document as an interactive "visual companion" — a browser-rendered HTML with editable note sections that persist in localStorage and can be copied/exported back to chat. Triggers include "visual companion", "open as html with notes", "interactive review doc", or when the user has a markdown doc with `### Your notes` / `### Notes section` subsections waiting for input.
---

# Visual Companion

## Overview

Generates an interactive HTML viewer from a markdown document. Designed for review / discussion / planning docs where the user wants to add notes section-by-section without editing the source `.md`.

Each `### Your notes (...)` or `### Notes section` heading becomes an editable `<textarea>` in the rendered HTML. Notes persist in `localStorage` (per-document, per-section). Top toolbar exposes:

- **Copy all notes** — concatenates all section notes (with their headings) and copies to clipboard for paste-back to chat
- **Download merged .md** — produces a `.md` blob with the user's notes baked into the source structure
- **Clear all notes** — wipes localStorage for the document (with confirm)

## When to use

- User explicitly asks for "visual companion", "interactive HTML", "open as html with notes"
- A markdown doc the assistant produced contains `### Your notes (...)` or `### Notes section` subsections waiting for the user
- The user wants to review in browser + add notes + export the notes back to chat without manually editing the `.md`

## When NOT to use

- The doc has no notes-sections — pandoc / a plain renderer is enough; `visual-companion`'s value is the interactivity.
- The doc contains secrets / credentials — they'd land in `localStorage` where they're harder to clean up than from a file.
- The user is on a non-macOS box without `open` — adapt the open command (`xdg-open` on Linux, `start` on Windows) or skip the auto-open.

## Workflow

1. Identify the source markdown path. Usually the most recent `.md` the assistant created that contains `### Your notes` subsections.
2. Run the generator:
   ```bash
   bash ~/.claude/skills/visual-companion/generate.sh /absolute/path/to/document.md
   ```
3. The generator writes a sibling `.html` next to the source `.md` and opens it in the default browser.
4. Tell the user:
   - Notes persist in browser `localStorage` (per-document path + section id).
   - **Copy all notes** button assembles everything for paste-back to chat.
   - **Download merged .md** produces a self-contained file they can hand back.
   - Re-running the generator after editing the source `.md` refreshes the HTML; persisted notes survive because they're keyed by section heading, not by markdown position.

## Behavioral notes

- The `.md` is the source of truth. The `.html` is a derived view. Don't auto-write notes back into the `.md` — flow them OUT via clipboard / download instead.
- `localStorage` scope is the file's path-as-URL. Moving the `.html` to a different directory loses notes.
- If a notes-section heading is renamed in the `.md`, that section's saved notes become orphaned (still in localStorage under the old id, no longer reachable via the UI). Tell the user before renaming.

## Anti-patterns

- Don't generate a visual companion for arbitrary `.md` files just because the user mentioned "open this". Confirm notes-sections exist; if not, use a plain renderer or ask whether they want notes-sections added first.
- Don't bake the markdown content inline as a JS string — that requires escaping. Use a hidden `<textarea>` element (textareas don't interpret HTML in their value).
- Don't ship local credentials / tokens into the HTML. The HTML is self-contained and easy to send to others; secrets in localStorage stay on disk.
