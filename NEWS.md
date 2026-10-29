# What changed in MEGA

One entry per version, newest first. A version is MAJOR.MINOR.PATCH: MINOR
goes up with a round of work that adds or changes what MEGA does, PATCH with
one that only mends, and MAJOR stays 2 until MEGA is made over again. Each
version is tagged in git as `vX.Y.Z`.

## 2.3.0 — 2026-10-28

- `C-a` goes to the first character of the line that is not a space or a
  tab; pressed again, to the start of the line, and so back and forth.
  Where a wrapped line continues, the start of the screen line comes first.
  At a prompt it stops at what was typed, not in the prompt.
- A mode that has its own `C-a`, as Org, mail and a terminal do, keeps it.

## 2.2.0 — 2026-10-21

- Every file shows its line numbers and the ruler, whatever kind of file it
  is; before, line numbers were for code, and the ruler for code,
  configuration and prose.
- The ruler stands at 80 columns, or where a project's `.editorconfig` puts
  it.
- Long lines are not wrapped: a line too long for its window runs off the
  right edge, marked with a `$`, and the window scrolls sideways to follow
  the cursor, as does a sideways tilt of the wheel.
- `mega-line-numbers`, `mega-ruler` and `mega-wrap-lines` in `local.el`
  change each of these; `local.el.example` has them.

## 2.1.0 — 2026-10-21

The first rounds of use.

**Search**
- Each hit shows what matched, marked.
- `M-g a` starts from the word or number under the cursor, selected:
  typing replaces it.
- `C-j` shows a hit where you searched from and keeps the prompt open;
  `C-v` and `M-v` page through the list.
- The prompt says how the search is set, and says the new setting at once
  when a `C-o` key changes it; `C-o ?` lists the keys.
- `C-o d` searches another directory, in the project or out of it;
  `C-u M-g a` asks for it first.
- Files git does not track are left out unless asked for.

**Editing**
- The line the cursor rests on says who changed it last, and when.
- Once the line that opens a block is out of sight, it is shown above the
  text.
- A file indented with tabs is indented with tabs.
- What an undo took away is named, and what it put back is marked.

**Looks**
- Three themes: Ayu Dark, which MEGA starts with, green on black, and Nord.
- A terminal of 8 or 16 colours gets one look in its own eight colours.
- Emoji and other joined characters no longer throw a terminal's lines out
  of place.

**Projects**
- Trust, and running in the dev container, are asked about once, when you
  open a project yourself, with a typed yes.
- A dev container starts without a window, unless it fails.
- `fd` lists a project's files where it is installed; the home page's
  choices are picked with `C-n` and `C-p`.
- A yes to a parser builds it, and the question does not come back.

**MEGA itself**
- `local.el.example` holds every setting, with what it does and its value.
- MEGA runs on an Emacs without native compilation, as bytecode.
- Making the compiled copy again keeps the native code of what did not
  change; the doctor says which functions are never native, and why.
- `Q` leaves the undo tree too.

## 2.0.0 — 2026-10-10

The first whole MEGA: everything in DESIGN.md's milestones M0 to M6, the
compiled copy, and a repository of its own (commit 084b491).
