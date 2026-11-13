# What changed in MEGA

One entry per version, newest first. A version is MAJOR.MINOR.PATCH: MINOR
goes up when it adds or changes what MEGA does, PATCH when it only mends,
and MAJOR stays 2 until MEGA is made over again. What is done meanwhile is
under "Not yet released" until there is enough of it for a version, which
is then tagged in git as `vX.Y.Z`.

## 2.5.0 — 2026-11-13

- In a file that git keeps, the lines changed since the last commit are
  marked in the margin, beside the line numbers: added, changed, and where
  lines were taken out, as you type. `C-x v ]` and `C-x v [` go from one
  change to the next, `C-x v *` shows one, `C-x v n` puts it back. The
  cheat sheet lists Emacs's own git keys with them, and the README how a
  merge conflict is resolved.
- `M-g I` goes to a definition anywhere in the project: type part of its
  name, and the language server lists the functions, types and constants
  it finds, with what each is and where, as you type. `M-,` comes back,
  as `M-g i` is the same in the buffer. A request that a key interrupts
  is asked again, rather than taken for an answer of nothing.
- Replacing in the whole project works, and the README says how: `M-g a`,
  `C-o e`, then `e` and `M-%`; the buffer of hits says it too. Before,
  `M-%` from the top changed the line that names the search and stopped
  there, and a hit Emacs had not drawn yet took no change. A hit is now
  editable only if it is its line in the file as it is: one in a file
  that changed since the search, or one whose line was cut short or held
  escape codes, would have been written over the line in the file.
- The search can leave files out: after ` -- `, `!vendor` leaves out
  every directory or file called `vendor`, and `!/vendor` only the one
  right in the directory searched. Names to search follow the same rules,
  as in a `.gitignore`, and mean the same to git grep, ripgrep and grep.
  Before, `-- src` found nothing with ripgrep, `-- *.rs` nothing with grep,
  and `src/*.rs` went into `src/gen` with git grep only; it no longer
  does, `src/**/*.rs` does. What grep cannot do, such as leaving out a
  path, the prompt says, and lists nothing.
- The search prompt (`M-g a`) has a history: `Up` brings back the query
  searched for before, `Down` the next one, and after the newest what you
  were typing. `C-n` and `C-p` go through the hits, as before. It keeps
  the queries you typed. Before, it kept the hit you took, which is a
  line of one of your files, and that was saved to disk with the other
  prompt histories. Such lines are dropped from it when you next search.
- In the undo tree (`C-x u`) the state that is in the file is marked `s`.
  On it, it stays an `s`, highlighted as `@` is. Moving about the tree no
  longer loses which state that is: once it was lost, getting back to the
  saved text, by the tree or by `C-/`, left the buffer marked as changed.
- `M-g a` starts from the word the cursor is right behind as well, as it
  is once you have typed the word; before, only from the one it was on.
- The word `M-g a` starts from is no longer selected: what you type is
  added to it, without moving the cursor first. `C-a C-k` clears it.
- In a prompt for a file, Backspace deletes one character, as anywhere
  else; after a `/` it deleted the whole directory name before it, and on
  `~/` it spelled out your home directory and deleted its last part.
  `M-Backspace` deletes a word, as before.
- In the search prompt, what you type or delete is on the screen at once,
  while the search is still at work. In a tree as large as Linux a search
  takes seconds, and `M-Backspace` left the word in sight until it was done.
- The mouse wheel scrolls the text, three lines a notch, in an Emacs built
  without X (`emacs-nox`). Before, a notch said "<wheel-up> is undefined"
  until something such as a language server had loaded the wheel's keys.
- "Who changed this line" no longer asks git again and again about a file
  it cannot blame where your language is not English: git's answer was
  looked for in English, and it says it in yours.
- The tests no longer reach your desktop: a test that killed text in a
  terminal Emacs gave it to your clipboard, in place of what you had copied.

## 2.4.0 — 2026-10-28

- In the search prompt (`M-g a`) a space can be typed: it is part of the
  pattern, as is `\ `. Before, the key tried to complete a word and failed
  with an error. `?` is typed too, instead of listing completions.
- Links that programs print (OSC 8: `ls --hyperlink`, delta, gcc,
  ripgrep) are buttons in `M-x shell`, Eshell and the buffer of a task or
  of `M-x compile`, as they were in `M-x term`. A click opens one, or
  `C-c RET`. Escape codes are no longer left in the text.
- The output of `M-x compile` is in colour before the first task too.

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
