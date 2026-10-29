# MEGA 2.0 — Make Emacs Great Again

> **☠️☠️☠️ DANGER ZONE! VIBE-CODED 💀💀💀**
>
> This was written by an AI model at its user's direction. It is tested, and
> nobody has read every line of it: use it knowing that.

A terminal-first Emacs configuration that needs nothing but Emacs 31.1: no
packages, no downloads. This page is the whole user guide. How and why it is
built is in [DESIGN.md](DESIGN.md).

## Why

MEGA began as a complaint. The big Emacs frameworks, proved buggy and sluggish
in daily use. They were unstable, now and then took Emacs down with a segfault,
and, worst of all, a bug of theirs could change the text in a buffer. An editor
can be forgiven a great deal, but not that.

So MEGA is built to keep your text as you typed it and to stay up, before
anything else. And it is whole from the first start: good enough as it
comes, with no package to download. It would go on working after a nuclear
war, with nowhere left to download from. Until then you can still add
things; the parsers for syntax highlighting, for one, are fetched when you
say yes.

## Install, update, remove

MEGA is this repository, cloned to where Emacs is told to look:

```sh
git clone https://github.com/0xD503/mega2.git ~/.mega2.d
emacs --init-directory ~/.mega2.d
```

With [chemacs2](https://github.com/plexus/chemacs2), name `~/.mega2.d` as
the default profile and plain `emacs` starts it.

**Anywhere else, and without git.** MEGA is three things: `early-init.el`,
`init.el` and the directory `lisp`. Put them in any directory and point
Emacs at it, or put them in `~/.emacs.d` and start plain `emacs`; no
installer and no profile switcher is needed, and they can be copied over
from another machine. MEGA finds its files from where they lie and writes
nothing there, `~/.emacs.d` included. What it remembers and builds goes
under `~/.local/state/mega2`, `~/.cache/mega2` and `~/.local/share/mega2`,
or where `XDG_STATE_HOME`, `XDG_CACHE_HOME` and `XDG_DATA_HOME` say. It
needs Emacs 31.1; an older one says so and stays a plain Emacs.

To update, `git -C ~/.mega2.d pull --ff-only`, and restart Emacs: a running
one goes on with the version it loaded. Updating is safe to do at any time.
Git leaves the directory holding exactly the new version's files, and your
`local.el` is not git's to touch. What MEGA remembers (history, undo,
trusted projects, workspaces) lives elsewhere and is read with care: a file
a newer MEGA cannot make sense of is ignored, never guessed at, so the worst
an update can do is make MEGA ask or forget something once. Its compiled
copy is rebuilt by itself.
What each version brought is in [NEWS.md](NEWS.md); `M-x mega-doctor` names
the one running.

To remove it, delete `~/.mega2.d`. What MEGA remembers is in
`~/.local/state/mega2`, and what it built, with its backups of your files,
in `~/.cache/mega2`: yours to keep or delete.

## Start

```sh
emacs                                  # if MEGA 2.0 is your default chemacs2 profile
emacs --init-directory ~/.mega2.d      # anywhere else
```

Without a file, Emacs opens on a home page: `r` continues where you left off,
`1`–`9` open a recent project, and the first line says how long starting
took, up to the moment the page was drawn. `C-n` and `C-p` go from one
choice to the next, and `RET` takes the one that is marked.

Then, once:

```
M-x mega-doctor      what works on this machine, and what is missing
C-c ?                every MEGA key, and the keys of each place that has its own
```

**MEGA compiles itself.** There is nothing to do. The first start after an
update runs MEGA's Lisp as source; the first time Emacs then has three
seconds with nothing to do, it compiles a copy in the background. Every
start after that loads the copy, and Emacs turns what it loads into native
code by itself, also in the background. The copy lives in `~/.cache/mega2`;
nothing compiled is ever written to `~/.mega2.d`, which is to say into this
repository. After an update only the files that changed go through this
again. `M-x mega-doctor` says which form is running, under "MEGA's own
Lisp": how many functions are native, compiled or source, and whether Emacs
is still making native code, in which case the count is on its way up.
`M-x mega-compile-now` makes the copy at once, for the next start. A few
functions are never native and are not meant to be, and the doctor says
which. An Emacs built without native compilation runs the compiled copy as
bytecode instead: everything works, a little slower.

## Keys

`C-` is Ctrl, `M-` is Alt. `C-c ?` always shows the complete, current list;
these are the ones to know. Pause after a prefix such as `C-c c` and Emacs
lists what can follow.

| Key | Does |
| --- | --- |
| `C-c ?` | The cheat sheet |
| `C-c h` | The home page |
| `C-c y` | Trust this project: let its tools run (see Trust below) |
| `C-c p f` | Open a file of the project: type any part of its name |
| `M-g a` | Search the project as you type (`M-g s`: the symbol at point; `C-u` first: a directory you choose) |
| `C-c t` | Show or hide the file tree |
| `M-.` | Go to the definition (`M-,` goes back, `M-?` lists the uses) |
| `C-c d` | Documentation for the thing at point |
| `C-c c r` | Rename everywhere (`C-c c a`: fixes, `C-c c f`: format) |
| `C-c c n` | Next problem (`C-c c e`: list them) |
| `C-c x b` | Build (`C-c x r` run, `C-c x t` test, `C-c x x` choose a task) |
| `C-c g g` | Start the debugger (`C-c g b` breakpoint, `r` run, `n` step, `c` continue) |
| `C-c k u` | Start or join the project's dev container (`C-c k d` leaves it) |
| `C-c l c` | Claude session for the project (`C-c l a` ask, `r` rewrite, `e` explain) |
| `C-x u` | The undo history as a tree |
| `C-c w s` | Save the open files and the window layout (`C-c w r` brings them back) |
| `C-c s` | Insert a snippet |
| `C-/` | Undo (`C-M-_` redoes) |
| `C-g` | Cancel whatever is happening |
| `C-h k` | What does this key do? |

In code, `C-c C-c` comments or uncomments, `C-c f` folds the block the cursor
is in (`C-c F`: all of them), and `M-n` / `M-p` jump between the uses of the
symbol at point. Anywhere, `C-a` goes to the first character of the line that
is not blank, and pressed again to the start of the line; a mode that has a
`C-a` of its own, as Org and a terminal do, keeps it.

**Which block you are in.** When the line that opens the function, class or
block around the cursor has scrolled off the top, a line above the text
shows it, outermost first: `impl Parser › fn statement › match self.peek()`.
It is worked out from indentation, so it needs no parser and works in any
language whose code is indented; when everything is on screen the line goes
away. `M-x mega-context-mode` switches it off in a buffer, `(setq
mega-context nil)` in `local.el` everywhere.

**Who changed this line.** In a file that git keeps, the line the cursor
rests on says at its end who changed it last, how long ago and in which
change; a line you have changed since says `not committed yet`. `M-x
mega-blame-mode` switches that off in a buffer, `(setq mega-blame nil)` in
`local.el` everywhere.

The mouse works in the terminal: click, scroll, hover for a hint. Selecting
text with the terminal itself then needs Shift held down; `(setq mega-mouse
nil)` in `local.el` gives the mouse back to the terminal.

**The completion menu** appears as you type. `TAB` takes a candidate, `C-n` /
`C-p` choose, `C-g` closes it; nothing is ever inserted unasked.

**The debugger** follows the program through your files. Where both are
installed, lldb is used before gdb (`mega-debug-prefer` in `local.el` turns
that round). On this machine it is Emacs's own interface to the debugger. In
a dev container MEGA shows the stack and the variables itself, in a window
below, and `C-c g b` sets breakpoints before you start; that needs lldb's
adapter (`lldb-dap`) or gdb 14 or newer in the container.

**Every prompt** lists its choices and narrows the list as you type. `C-n`
and `C-p` move in it, `C-v` and `M-v` by a page, `M-<` and `M->` to its first
and last entry; `RET` takes the highlighted one, `M-j` exactly what you typed.

**Searching** (`M-g a`) is done by `git grep`, as a Perl regular expression,
and the prompt says so. It starts with the word or the number the cursor is
on, or right behind, and its hits are there at once. What you type is added
to that word; `C-a C-k` clears it. Outside a checkout `git grep` cannot search, and the
next of git grep, ripgrep and grep that is installed does. Each hit shows
what matched in its line, marked, as the program that searched reports it.

`RET` goes to the highlighted hit. `C-j` only shows it: in the window you
searched from, its line in the middle and marked, with the prompt still open,
so you can go down the list and look at the next. `C-g` then leaves
everything as it was, and closes a file that was opened only to be shown.

The prompt says how it searches: `[git  case:smart]` is git grep, case
ignored unless you type a capital, and anything else that is on is named
after it. That is changed in the prompt, while it is open and you are typing
what to look for: `C-o` and then a letter, and the prompt says the new
setting at once. (Anywhere else `C-o` is Emacs's own key and opens a line.)
`C-o ?` lists the keys; `C-o c` changes case, `w` whole words, `l` literal
text, `e` exports the hits to an editable buffer. `C-o b` switches to ripgrep, then plain grep, then back,
and the session stays with what you chose; `(setq mega-search-backend 'rg)`
in `local.el` makes ripgrep the one to start with. `needle -- src/*.rs`
searches part of the project. A space in the pattern is a space, as `\ ` is
too; `\ --\ ` looks for ` -- ` itself.

A search starts at the root of the project, every time. `C-o d` moves it to
another directory while the prompt is open, in the project or out of it,
and keeps what you typed and how the search is set; `C-u M-g a` asks for the
directory before the prompt opens. In that question RET goes into a
directory, and RET on `./` at the top, or `M-j`, searches the one you are
in. The prompt says where it searches: `proj` for the root, `proj/src/net`
inside it, `~/notes` outside it. The program follows the directory, since
git grep can only search a checkout. What you open from there is not asked
about, as nothing a search opens is.

Which files are searched is where the three programs differ, since only git
knows what a checkout tracks. These too are keys of the search prompt; in
brackets, how each starts out:

| | git grep | ripgrep | grep |
| --- | --- | --- | --- |
| untracked files | `C-o u` (off) | always | always |
| ignored files | `C-o i` (off) | `C-o i` (off) | always |
| hidden files | always | `C-o h` (on) | `C-o h` (on) |
| submodules | `C-o s` (off) | always | always |

With git grep, ignored files count as untracked, so `C-o i` brings both, and
`C-o s` leaves both out. A key the current program cannot act on says so.

**Links that programs print** (`ls --hyperlink`, delta, gcc, ripgrep) are
buttons in `M-x term`, `M-x shell`, Eshell and the buffer of a task or of
`M-x compile`: a click opens one, or `C-c RET` (`RET` in a task's buffer).
A `zed://` link goes to Zed, a `file://` one opens in Emacs. Most programs
write links only to a terminal, which Eshell is not, so there they are rare.

**A dev container** starts in the background: Emacs stays yours while it
does, and the modeline says `[box: starting]` until it says `[box:NAME]`.
Each step is written to the buffer `*mega-container*`, which is put in
front of you only if a step fails. Before anything from
`devcontainer.json` runs you are shown what will: every command, in order,
and what is mounted from this machine. A file that asks for something MEGA
cannot do, or does not know, is refused by name and not half-followed.

## What needs what

Everything outside Emacs is optional: without it the feature stays quiet and
`M-x mega-doctor` says what is missing.

| For | Install |
| --- | --- |
| Search | `git` in a checkout; `rg` or `grep` anywhere else |
| Finding files | `git` in a checkout; `fd` (also under the name `fdfind`), `rg` or `find` anywhere else |
| Go to definition, rename, problems as you type | the language's server, e.g. `rust-analyzer`, `clangd` |
| Format on save | the language's formatter, e.g. `rustfmt`, `clang-format`, `ruff` |
| Debugging | `lldb` or `gdb`; Python brings `pdb` |
| Dev containers | `podman` or `docker`; the `devcontainer` CLI if you have it |
| Claude | the `claude` program, signed in |

Syntax highlighting for some languages wants a parser; Emacs offers to build
it the first time you open such a file. Say yes and it is there from then on;
say no and the question does not come back (`M-x mega-lang-ask-again` undoes
that). `M-x mega-lang-install-parsers` builds all the missing ones in one go.

## Trust

A language server, a syntax checker, a formatter, a task, a debugger and a
container all run code that comes with the project. Until you say so, none
of them does: a project you have not trusted is only edited, and the
modeline says `untrusted`.

The first time you open a file of a project yourself, with `C-x C-f`, the
project's file prompt or the home page, MEGA asks whether to trust the
project. A no is remembered and the question does not come back; `C-c y`
trusts the project of the file you are in whenever you like, and what was
held back starts in its open files. `M-x mega-distrust-project` takes that
back. Leaving the question with `C-g` decides nothing.

A trusted project that has a `devcontainer.json` is asked about next:
whether to run its tools in its container. A no there lasts until Emacs is
restarted, and `C-c k u` starts the container at any time.

MEGA does not ask about a file that Emacs opens along the way: a jump to a
definition, a hit of a search, the line a debugger stops at. Besides the
first opening it asks only when you press a key that cannot work without
the answer, such as build or debug, and says what the answer allows. A file
outside any project is trusted with the other files of its directory and
nothing below it, and is not asked about when opened. `(setq
mega-trust-ask-on-open nil)` in `local.el` leaves it all to `C-c y`.

These questions take the word `yes`, typed out: one key is pressed too
easily to let a project run its code. So do the others whose yes weighs as
much: removing a container, sending text from a private file to Claude,
downloading parsers, and deleting what MEGA has stored.

## Where a setting goes

| Want to… | Edit |
| --- | --- |
| Change something on this machine only | `local.el` |
| Change the theme | `(setq mega-theme 'mega-hacker)` or `'mega-nord` in `local.el`; `M-x mega-theme` for this session only |
| Add, move or remove a key | `mega-keys-add` / `mega-keys-remove`, in `local.el`; the cheat sheet follows |
| Change a global default | `lisp/mega-core.el` |
| Add a language: modes, server, formatter, indentation | one row of `mega-languages` in `lisp/mega-lang.el` |
| Add a kind of project: its tasks, its formatter | one row of `mega-project-kinds` in `lisp/mega-project.el` |
| Add a snippet | `mega-snippets` in `lisp/mega-snippet.el` |
| Remove a feature | delete its line in `init.el`; its keys go with it |

`local.el` is yours: git ignores it, so an update never touches it. Start
it with `cp local.el.example local.el`: that file holds every setting MEGA
has, by subject, each with what it does and the value it has, all commented
out, and at the end recipes for Emacs's own defaults, keys of your own and
the like. To change a setting, uncomment its lines (select them, `C-c C-c`)
and change the value. A test holds the template to MEGA, so it is never out
of date.

Every file shows its line numbers and the ruler, whatever kind of file it
is; the ruler stands at 80 columns, or where a project's `.editorconfig`
puts it. A line too long for its window is not wrapped: it runs off the
right edge, marked with a `$`, and the window scrolls sideways to follow the
cursor. `mega-line-numbers`, `mega-ruler` and `mega-wrap-lines` in
`local.el` change that; `M-x visual-line-mode` wraps one buffer at the ends
of words.

There are three themes. `mega-ayu`, the one MEGA starts with, is Ayu Dark,
as Zed has it: blue-black, keywords orange, functions yellow.
`mega-hacker` is green on black, after the old screens: a background that is
all but black, text in the green of phosphor, and what stands out from it
bright. `mega-nord` is the Nord palette, soft and blue-grey. They need a terminal of
256 colours or more. On one of 8 or 16, whichever is chosen, MEGA uses the
eight colours every terminal has, by name, so that the terminal draws them
in its own shades: white on black, keywords cyan, functions yellow, strings
green, comments and what is selected blue.

A theme is a palette of seventeen colours in `lisp/NAME-theme.el`, each
named for what it is used for; which face gets which of them is written
once, in `lisp/mega-themes.el`, so a colour is changed in one place and a
theme of your own is one short file and its name in `mega-themes`. A project's
`.editorconfig` sets its
indentation and line endings, moves the ruler (`max_line_length`), and says
whether spaces at the ends of lines are removed. Where it says nothing about
indentation, MEGA indents with spaces, except in a file whose lines begin
with tabs: there a new line begins with a tab like its neighbours. A module that others are
built on (`mega-exec`, `mega-trust`, `mega-project`, `mega-lang`) stays
loaded for as long as anything that needs it is on the list.

## What MEGA does without asking, and what it never does

- **Keeps your work.** Backups and auto-saves are on, stored away from your
  projects. Deleting a file moves it to the trash. Undo history survives
  closing the file and restarting Emacs.
- **Keeps your data on the machine.** MEGA opens no network connection and
  has no telemetry. What you copy is never written to disk. Files such as
  `.env`, keys, anything under `~/.ssh` and anything in a temporary directory
  leave no trace: not in recent files, cursor places, prompt history, saved
  workspaces or stored undo history. `mega-private-file-regexps` in
  `local.el` adds your own.
- **Sends text to Claude only when you press a Claude key**, and only the
  text you selected. With nothing selected, explain and rewrite offer the
  function the cursor is in, say how many lines that is, and wait for a yes.
  A private file needs a typed "yes" first.
- **Does not trust a repository.** Opening a file cannot run code: unsafe
  file-local variables and `eval:` lines are ignored, nothing checks or
  builds it, and see Trust above.

Everything MEGA remembers lives in `~/.local/state/mega2` and
`~/.cache/mega2`, readable only by you. Deleting the cache loses nothing you
cannot rebuild offline. `~/.mega2.d` itself is never written to.

## When something breaks

A module that fails to load is skipped and reported; the rest keeps working.
`M-x mega-doctor` lists what failed, how long each module took, which
programs it found, and whether the promises above are really in force.

`M-x mega-keys-mode` turns every MEGA key off, leaving stock Emacs. On an
Emacs older than 31.1 MEGA configures nothing and says so.

Text that is gone a moment after you typed it has most likely been undone:
`C-/` takes back one step, and to Emacs a step can end in the middle of a
word, so what is left does not look like an undo. MEGA therefore shows what
an undo did. The echo area names what it took away, `Undo: removed "mn =
true"`, and text that it puts back is marked where it stands, until the next
key or for two seconds; the same when you step through `C-x u`. Nothing is
lost by an undo: press any other key and then `C-/` again, or look in
`C-x u`, where every state the text was in is kept. `(setq mega-undo-show
nil)` in `local.el` leaves Emacs's bare `Undo`.

In a terminal, an emoji that is made of several characters is drawn
plainly: a skull without its colour, a family as three faces side by side, a
thumb without its skin tone. That is on purpose. Emacs and a terminal each
keep count of the cells a line takes, such sequences are where they disagree,
and a line they disagree on is drawn over its neighbours: text looks cut
off, moved or gone while the buffer holds every character of it. So MEGA
does not send a terminal what makes it join characters. Should a screen
ever look wrong all the same, nothing is lost: what the buffer holds is what
`C-x u`, the undo tree, shows and what a save writes. `C-l` draws the screen
again; a character newer than your terminal knows keeps its line wrong
until it is scrolled away.

`MEGA_SOURCE=1 emacs` runs MEGA from source this once, whatever compiled
copy there is. `M-x mega-compile-forget` deletes the copy; `(setq
mega-compile nil)` in `local.el` stops MEGA from making one.

## Tests and timings

```sh
tests/run.sh                 # everything, in a sandbox
tests/run.sh bench           # only the timings
MEGA_TEST_ONLY=mega-undo tests/run.sh unit    # only the tests so named
MEGA_REAL_IMAGE=my/image tests/run.sh container   # a real container: see below
EMACS=/path/to/emacs tests/run.sh                 # another Emacs, e.g. one without native compilation
```

The tests run on both forms of MEGA's Lisp, source and compiled, and a real
terminal session is taken through all of it: source, compiled, native. With
tmux installed, a tmux of the tests' own is also asked what its grid holds
after Emacs has drawn some seventy awkward lines: emoji, accents, scripts
that join. Yours is not touched.

The `bench` stage times what you wait for (a keystroke, the modeline, the
completion menu, listing and finding a file, a search, a save, the undo tree,
a language server's first start) and prints each time beside what it is
expected to take. A line marked `SLOW` is over one and a half times that and
worth a look; over three times, the run fails. Before a change that might
cost time, keep a run with `MEGA_BENCH_SAVE=before.eld`; afterwards
`MEGA_BENCH_COMPARE=before.eld` also fails on anything that became twice as
slow as it was.

What each benchmark is expected to take is on record in
`tests/mega-bench-history.eld`, with the commit that made it so and the
reason; there is no number anywhere else to change. When one is exceeded,
whoever sees it finds the cause first (the stage prints the `git bisect`
command) and fixes it. Only if the slowdown is the reasonable, direct and
minimised price of a change that is wanted does the time go up, and then
with a new record: the time, the commit that introduced it, and why.

The `container` stage runs only when named. It starts one container with
podman from an image you already have, with no network, runs, builds and
debugs in it, and removes it; nothing is downloaded.

## Licence

Copyright 2026 0xD503. MEGA 2.0 is under the
[Apache License, Version 2.0](LICENSE): use it, change it and pass it on,
keeping the licence and the [NOTICE](NOTICE) with it and saying what you
changed.
