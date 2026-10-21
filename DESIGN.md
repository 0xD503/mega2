# MEGA 2.0 — design

The agreed requirements, feature list and architecture. The user guide is
[README.md](README.md); this file is for whoever changes MEGA.

## The one rule

MEGA 2.0 is **self-sufficient**: it uses what Emacs ships and code written for
MEGA, and depends on no downloadable Elisp. MEGA 1, which it replaces,
pulled about 40
packages and 15 tree-sitter parsers; 2.0 pulls none.

| Decision | |
| --- | --- |
| Emacs | 31.1 or newer |
| Code allowed | Emacs built-ins + code written for MEGA. No packages, no vendored third-party files |
| Tree-sitter parsers | Emacs 31's own prompt offers to build one, and `mega-lang-install-parsers` has Emacs build all the missing ones after one question; MEGA has no installer of its own |
| Completion popup | None is built in, so MEGA writes one on 31.1's terminal child frames |
| Project search | Live, as you type |
| Kept from MEGA 1 | Workspaces, Claude CLI, undo tree + persistent undo, indent guides |
| Added | Tasks, debugger, format on save, snippets, Dev Containers, vertical ruler |
| Not wanted | Git workflow beyond stock `vc`, with one addition asked for after the first use: who changed the current line. Spell and grammar checking |
| Dev Containers | MEGA-native subset; official `devcontainer` CLI when it is installed |
| Location | A repository of its own, cloned to `~/.mega2.d`; the default chemacs2 profile |
| Licence | Apache-2.0. `NOTICE` names the copyright holder; the code is MEGA's own, so there is nobody else's licence to honour |
| Own language modes | Markdown, Zig, justfile; a Rust fallback for when its parser is not built |

## Priorities

In descending order. When two conflict, the higher one wins.

**safety → privacy → security → stability → extensibility → maintainability → performance**

Examples of that ordering already decided:

- Backups and auto-saves cover private files too (safety over privacy), in a
  directory only the owner can read.
- Emacs asks before killing a running process on exit (safety over
  convenience); MEGA 1 did not.
- Startup tricks that risk misreading a file named on the command line are
  not used (stability over performance).

## Hard constraints

- **Emacs ≥ 31.1.** An older Emacs is left plain and told why; it is never
  half-configured.
- **No Elisp downloads.** `package.el` is not initialised and has no archives.
- **External programs are optional, never prerequisites.** Each is detected,
  and its feature is inert with a clear message when it is missing.
- **Terminal-first.** Fully functional under `emacs -nw` and tmux. Popups use
  TTY child frames with an echo-area or side-window fallback. What is on the
  screen is what the buffer holds: Emacs is kept from sending a terminal
  anything the two would count the cells of differently.
- **Launcher-neutral.** Works as a chemacs2 profile and with
  `--init-directory`; no file of MEGA mentions its launcher.

## Requirements, by priority

1. **Safety — never lose or damage your work.**
   - Backups and auto-save stay on, outside project trees, under hashed names
     so a deep path cannot make one uncreatable.
   - Deleting a file moves it to the trash.
   - Format on save is all-or-nothing and never blocks or aborts the save.
   - Persistent undo is restored only when the file content matches.
   - Nothing destructive without confirmation; nothing a repository defines
     runs automatically.
2. **Privacy — nothing leaves the machine unless you ask.**
   - MEGA opens no network connection and has no telemetry. The only
     sanctioned download is Emacs's parser prompt, after you answer yes.
   - Code goes to Claude only on an explicit command, and only the text you
     selected; with nothing selected, the function at point, in code only,
     after its size was shown and agreed to. On standard input, never on a
     command line; a private file needs a typed "yes".
   - A debugger's debuginfod lookups, which name what you debug to a
     server, are off: every debugger is started with `DEBUGINFOD_URLS`
     empty, lldb and those in a container included.
   - Language servers get telemetry switched off where they offer a switch,
     and a project's own server settings are merged under that, not over it.
   - State directories are 0700. The kill ring is never saved.
   - **One rule for what leaves no trace.** `mega-forgettable-file-p` is
     asked by everything that writes something about a file to disk: recent
     files, cursor places, the history of file prompts, recent projects,
     workspaces (down to the buffer names in a saved window layout) and
     persistent undo. It covers private files, by name or by where a link
     leads; temporary directories, `$TMPDIR` included; and files that exist
     for one command, such as a commit message.
3. **Security — a cloned repository cannot run code by being opened.**
   - `enable-local-variables :safe`, no local `eval`, no remote dir-locals.
   - `compilation-read-command` stays on: it is the only reason Emacs accepts
     a project's `compile-command`.
   - **Project trust.** Language servers, syntax checkers, formatters,
     tasks, debuggers and containers run code that belongs to the project
     (build scripts, macros, plugins, a Makefile). None of them starts in a
     project you have not trusted, and that includes what Emacs would start
     by itself: its on-the-fly checker runs `make` for C and `perl -c` for
     Perl. The modeline shows `untrusted` where tools are held back, and
     `C-c y` trusts a project at any time.
   - **When trust is asked for.** Once, when you open a file of a project
     yourself that nothing was ever said about; and from a command that
     cannot go on without the answer. Never about a file Emacs opens along
     the way, a jump to a definition or a line the debugger stops at, and
     never from a process filter or a timer of its own: a question met in
     passing is one you learn to answer yes to. "Yourself" is a list of
     commands whose purpose is opening a file (`mega-trust-opening-commands`),
     and the question comes after the command, not from inside it. The
     review had taken the question at opening away altogether, for that
     reason; its user asked for it back after the first day, with the word
     yes in place of a key, which answers the reason. A trusted project
     with a `devcontainer.json` is then offered its container, once a
     session.
   - **Two kinds of question.** One key answers what can be taken back.
     The word yes, typed out, answers what lets code run, lets text leave
     the machine, or cannot be undone: trust, starting or removing a
     container, text from a private file for Claude, downloading parsers,
     deleting stored undo history or a workspace. They are asked with
     `mega-confirm`, which Emacs's `use-short-answers` does not shorten.
     MEGA sets that option for Emacs's own questions, and until it was
     reported from use it shortened MEGA's long ones as well.
   - **What a decision covers.** A project, by its root. A file outside any
     project: its directory and nothing below, and no longer once a project
     appears there. The home directory and `/` are never a root, whatever
     marks them. Decisions are data, written whole or not at all, and read
     again when the file changes, so two sessions agree.
   - **Emacs's own launch points.** A project's `compile-command` is taken
     only in a trusted project. Every git that Emacs or MEGA starts runs
     with `core.fsmonitor` off and bare repositories refused unless named,
     because both are ways for a directory to run a program
     (`mega-git-hardening`).
   - A further approval, tied to a hash of `devcontainer.json` and of the
     files it names, before anything from it runs. The screen shows what
     will run, in order; what is mounted from the host; `privileged`; and
     what is left to the official CLI, when that is what will act on it.
   - A one-shot Claude question never runs in the project: `claude --print`
     skips that program's own trust question, and a project can carry
     settings that run commands. It runs in an empty directory with tools,
     MCP servers and project settings off.
   - Stored undo history is data: read, checked record by record, never
     evaluated. Records that call functions are neither written nor accepted.
   - Processes get argument lists, never shell strings built from file names
     or search input.
4. **Stability.**
   - A module that fails to load is skipped and reported.
   - Built-ins only. The places that lean on something Emacs keeps for
     itself — eglot's snippet hook, `undo-equiv-table` — are isolated,
     tested, and reported by the doctor if they change.
   - The configuration directory is read-only at runtime.
5. **Extensibility.** Keys, languages, kinds of project, snippets, picker
   sources and doctor sections are data tables or lists; machine overrides go
   in `local.el`, keys included (`mega-keys-add`).
6. **Maintainability.**
   - One module, one concern; explicit module list in `init.el`; no DSL;
     byte-compiles with zero warnings.
   - Every feature ships with unit tests; a feature without them is not done.
   - The user guide stays one short page.
7. **Performance.** Startup ≤ 100 ms in a terminal, counting what is put
   off until Emacs has started; heavy modules load on first use; typing is
   never blocked, and neither is a save: every formatter, the language
   server included, gets `mega-format-timeout` seconds and no more. These
   are goals and yield to everything above.

## Features

### Configured from built-ins

LSP through eglot (completion, diagnostics, hover, navigation, rename, code
actions, hierarchies, semantic highlighting); tree-sitter modes through
Emacs's own prompt; a vertical minibuffer with `flex` matching; line numbers
and the ruler in every file, and long lines left unwrapped;
a file tree (speedbar in a side window); imenu; diagnostics list; folding;
which-key; editorconfig; tabs; history, recent files and places; TRAMP;
project shell; editable grep results; GUD debuggers (gdb, lldb, pdb).

### Written for MEGA

| Feature | What it does |
| --- | --- |
| Popup | Child-frame popup primitive |
| Completion menu | Appears as you type; fed by the language server, snippets and the buffer |
| Live picker | Minibuffer picker with async sources, in-place toggles, export |
| Project search | `C-j` shows the highlighted hit without leaving the prompt, and leaving it otherwise than by a choice puts the windows back and closes what was opened to be shown. It starts from the word or number under the cursor. What matched is marked in each hit: the program is asked to colour it, with settings of MEGA's own so that yours do not matter, and the colour is read as the mark. `git grep -PnI` by default, `rg --hidden` or `grep` one key away (`C-o b`, which lasts for the session); toggles for case, untracked, ignored, submodules, hidden, literal/word, file glob. It searches the root of the project unless `C-o d` moves it, while the prompt is open, to another directory in the project or out of it, or `C-u` asks first; that is not remembered, and the settings stay as they are. The prompt says how the search is set, for as long as it is open, and says the new setting as a key changes it; a note beside it (why a key could not act, which keys there are) stays until the next key, not for two seconds |
| Project files | Emacs's own `C-c p f`, matching fuzzily. In a checkout the list is version control's; in a project without one MEGA lists it (`fd`, which is `fdfind` on some systems, else `rg --files`, else `find`) and leaves out what a build made. Not cached |
| Tasks | Build / run / test per project, with jump to error |
| Format on save | editorconfig, then the language server or the language's own tool (rustfmt on the buffer; `cargo fmt` project-wide) |
| Snippets | LSP-syntax tab stops; user snippets per mode |
| Dev Containers | See below |
| Claude | Project session in a tmux pane or a terminal buffer; one-shot ask, explain and rewrite-with-diff through `claude --print` |
| Themes | Three, each a palette of seventeen colours named for what they are used for: Ayu Dark as Zed has it, which MEGA starts with, green on black, and Nord. On a terminal of 8 or 16 colours each falls back to one and the same look in the terminal's eight colours by name; below 8 nothing is applied. Which face gets which part is written once for all of them, and tests hold every colour on the screen to a palette and every colour of text to a measured contrast with what it is written on. `mega-theme` in `local.el` chooses; `M-x mega-theme` switches for a session |
| Undo | Tree drawn from Emacs's own undo list; history persisted per file. What an undo did is shown, by the key or by a step in the tree: the echo area names what it took away, and what it put back is marked where it stands until the next key or for two seconds. It looks on while Emacs undoes and changes neither text nor history |
| Debugging | Picks the debugger and the program for the project; one set of keys for gdb, lldb and pdb. On the host through GUD, in a container through a debug adapter |
| Debug adapter client | Own client for the Debug Adapter Protocol: breakpoints that outlive sessions, stack, variables, output |
| Workspaces | The open files and the window layout, saved under a name and resumed |
| Small helpers | Indent guides, TODO highlight, symbol jump, trim changed lines, clipboard bridge |
| Which block you are in | A line above the text names the lines that open the blocks around the cursor, once they are out of sight, and goes away when they are not. From indentation alone: the nearest line above that is indented less, and so on outward. Comments, the inside of strings, and in C the preprocessor and labels are passed over; a line that only closes a list of arguments gives way to the line that began it |
| Who changed this line | At the end of the line the cursor rests on: who, how long ago, in which change. git is asked about that one line when Emacs is idle, in the background, about the text on screen whether saved or not, and with `--no-textconv`, without which it runs a converter the repository can name |
| Modes | Markdown, Zig, justfile, Rust fallback |

### Not in 2.0

Spell and grammar checking; Git UI or margin marks; icons; kitty keyboard
protocol; multiple cursors; an API-key LLM client; Dev Container Features and
compose without the official CLI; RON mode; anything GUI-specific.

## Architecture

```
early-init.el     version gate, where files go, startup cost
init.el           the module list
local.el.example  every setting, commented out with what it does and its
                  value, and recipes, to start a local.el from; git ignores
                  local.el itself
lisp/
  base      mega-lib  mega-core  mega-keys  mega-ui  mega-themes
            mega-hacker-theme  mega-nord-theme  mega-ayu-theme
            mega-session  mega-help  mega-doctor
  kit       mega-popup  mega-pick  mega-exec  mega-project  mega-trust
            mega-lang  mega-compile
  features  mega-complete  mega-workspace  mega-home  mega-search
            mega-edit  mega-indent-guides  mega-undo  mega-undo-tree
            mega-snippet  mega-format  mega-lsp  mega-task  mega-debug
            mega-dap  mega-container  mega-remote  mega-llm  mega-zone
  modes     mega-mode-markdown  mega-mode-zig  mega-mode-just  mega-mode-rust
tests/            the ERT suite, the probes, the stand-in programs, the
                  bench and its history; Emacs never loads any of it
tests/run.sh      runs them
```

The repository is the configuration directory: cloned to `~/.mega2.d`,
its top is what Emacs is pointed at.

- **Layers, dependencies pointing down only:** features → kit → base → Emacs.
  A module `require`s what it calls, so the layering is in the code and not
  only in this picture: taking a feature off the list in `init.el` removes
  it, and taking a kit module off changes nothing while a feature needs it.
- **Source here, a compiled copy in the cache.** MEGA's Lisp is deployed
  as source, and nothing compiled is ever stored with it: not in this
  directory, which is read-only, and not in the repository. A start that
  finds no compiled copy runs the source and, once idle, has another Emacs
  make one in the cache directory (`mega-compile`); later starts load it,
  and Emacs's own JIT takes each compiled file it loads on to native code.
  `early-init.el` decides which is loaded, before the first module, by a
  fingerprint of every source file: a copy made from any other source is
  not used, so compiled code can be absent but never stale. A copy is made
  whole or not at all. The Emacs that makes it gets state directories of
  its own to throw away and leaves without running exit hooks: compiling a
  module loads the modules it needs, and one that saved something on the
  way out would save it over yours. None does today; this is so that none
  can.
- **Loading.** `init.el` lists every module. A bare name loads at startup; a
  list such as `(mega-doctor :commands (mega-doctor))` loads on first use.
- **Read-only configuration.** `init.el` points `user-emacs-directory` at the
  state directory, which catches every Emacs feature that writes there
  without asking. It is done in `init.el`, not `early-init.el`, because
  chemacs2 finds `init.el` through that variable. MEGA finds its own files
  through `mega-dir`.
- **Keys are a table.** `mega-keys` builds the keymap and the cheat sheet, so
  they cannot disagree; `mega-keys-add` and `mega-keys-remove` change both
  at once, from `local.el`, and a key whose command does not exist is
  dropped at start-up. The keys of the places that have their own (the
  completion menu, the undo tree, the home page) are described in
  `mega-keys-elsewhere`, and a test holds that description to the keymaps,
  key by key, in both directions.
- **Logic separate from display.** Popup, picker, completion menu and undo
  tree keep a model apart from the code that draws it, so the model is
  unit-testable without a terminal.
- **Two tables say what MEGA knows about code.** `mega-languages`, by
  language: the modes, the server candidates, the formatters, the
  indentation variable of each mode, the kind of debugger. Nothing else
  knows which modes make up a language; snippets name a language, not its
  modes. `mega-project-kinds`, by the file that marks a kind of project:
  whether it marks a root, its tasks, the command that formats all of it.
  `Cargo.toml` is named there once. What a module keeps beside them is for
  what is in neither: a mode of no language, your own tasks for one project.
- **`mega-exec` is the key abstraction** (from M1). Every process MEGA starts
  goes through it, as an argument list. The caller says where: the project's
  tools (its container if it has one), where the files are (never a
  container: a search, a file listing), or this machine whatever the buffer
  visits (the clipboard, tmux, the container program itself). And how long
  it can wait: `mega-exec-run` waits, interruptibly and with a limit that
  covers sending the input; `mega-exec-start` calls back; `mega-exec-open`
  hands over output as it comes, for a conversation such as a debug
  adapter's. A project on another machine is not a context: its directory
  is a remote file name and Emacs starts the program there. The few
  programs that need a terminal of their own (GUD, the Claude session, a
  container shell) get their argument list from `mega-exec-command`. That
  is what makes containers a cross-cutting feature and not a rewrite of
  each module.
- **Dev Containers.** Parse `devcontainer.json` (own JSON-with-comments
  reader), show what it will do and wait for approval, then start: with
  `devcontainer up` if that CLI exists, else podman/docker directly. The
  start runs in the background, a step at a time, with a log; Emacs is
  never held. The log is a buffer and not a window: the modeline says
  that a container is starting, and the log is put in front of you only
  when a step has failed. (It used to open with the first step; with the
  container offered at every opening of its project, that was a window to
  close each time.) Every key of the file is in one of three lists: acted on
  (image, mounts, runArgs, capAdd, securityOpt, privileged, init, the
  environment, users, ports, the lifecycle commands), harmless to ignore,
  or impossible without the official CLI (build, features, compose).
  Without that CLI the last kind is refused by name, and so is a key in
  none of the lists: MEGA does not guess at a setting. With it, both are
  listed on the approval screen as the CLI's to act on. Files stay on the host and tools run in the container, with one
  path-mapping layer, applied per language server; container-only files
  open through TRAMP.
- **Undo has no data structure of its own.** The tree is read off
  `buffer-undo-list` and `undo-equiv-table` each time it is drawn, and a
  move is a replay of the records between two states, recorded like any
  other change. The only thing that could ever be wrong is the claim "the
  text is now in that older state", so it is made only when the replay ran
  exactly from one state to the other. Two consequences, both deliberate:
  Emacs's "undone all the way back" is not believed (it does not say back
  to where, and Emacs discards old history), so that state is drawn as a
  node of its own; and MEGA's own mark for the oldest state is dropped the
  moment the end of the list changes.
- **Two debugger interfaces, one set of keys.** On the host MEGA starts
  Emacs's own (GUD), which is mature and costs no code. In a container the
  full form of that needs a terminal of the host, so MEGA talks to the
  debugger as a debug adapter instead (`mega-dap`), over the same
  `podman exec` every other tool uses. `mega-debug-backend` overrides the
  rule; an adapter that is missing or too old falls back to GUD. The
  client is three layers — bytes, session, display — and wholly
  asynchronous: a key sends a request and returns.
- **The debugger is chosen before the interface.** `mega-debug-prefer`
  ranks the families, lldb before gdb by default, and outranks the choice
  of interface: lldb through its console is taken before gdb through an
  adapter. Both lists of candidates carry a `:family`, and
  `mega-debug-plan` is the one place the two are weighed.
- **The adapter client was written against recordings, not the
  specification.** Real conversations with gdb 16 and lldb-dap 19 were
  captured first, and the test stand-in plays either back with its habits
  intact, because they disagree on every point that matters: gdb says
  "initialized" at once and answers `launch` only after
  `configurationDone`, lldb the other way round; gdb's breakpoints start
  unverified and its frame ids go stale at every stop; lldb announces a
  step before answering it, ends the program's lines with CR LF, and
  crashes with a page of backtrace when told to disconnect. And they cut
  a frame's variables up differently: lldb gives one scope with arguments
  and locals in it, gdb gives the two apart and leaves out whichever would
  be empty; both say which is which, and neither marks the registers as
  costly to read.
- **Programs that take long** (`claude --print`) go through
  `mega-exec-start`, which returns at once and calls back; a mistake in the
  callback is reported, not raised, because it runs in the middle of
  whatever else is happening.

## Milestones

| | Delivers | Status |
| --- | --- | --- |
| M0 | Skeleton: init, base modules, theme, modeline, ruler, session, doctor, cheat sheet, tests, guide | done |
| M1 | Minibuffer, live prompt, `mega-exec`, file finder, live search, project keys, file tree | done |
| — | Home page and workspaces (requested after M0; workspaces moved up from M5) | done |
| M2 | Popup, completion menu, eglot, language table, parser prompt, the four modes | done |
| M3 | Project trust, format on save, snippets, tasks, indent guides, small edit helpers | done |
| M4 | Dev Containers: native subset, hand-over to the official CLI | done |
| M5 | GUD debugging, Claude, undo tree + persistence, remote, zone | done |
| M6 | Debug adapter client, used for debugging in a container | done |
| — | MEGA compiles itself: a compiled copy in the cache, made in the background, native through Emacs's JIT (requested after the review) | done |
| — | A repository of its own, out of the dotfiles it grew up in; its history came along | done |
| — | Architecture review, 37 findings: trust as an act and not a prompt, Emacs's own launch points gated, one process layer with three places, one rule for what leaves no trace, the two tables, tests over the wire, the bench rebuilt | done |
| — | First use, round one (reported by its user): a yes that really builds the parser; fd for listing files; choices on the home page; the word yes for what weighs; who changed a line; which block you are in; MEGA as a bare copy in `~/.emacs.d` | done |

Each milestone ends with its unit tests, doctor rows and guide entries.

## Versions

MAJOR.MINOR.PATCH, in `mega-version` (lisp/mega-lib.el), as the user set
it on 2026-10-21: MINOR goes up with a round of work that adds or changes
what MEGA does, PATCH with one that only mends, and MAJOR stays 2 until the
user decides MEGA is to be made over again. Each version has an entry in
NEWS.md, written for whoever uses MEGA, and a tag `vX.Y.Z`; a test holds
NEWS.md's newest entry to `mega-version`. 2.0.0 is commit 084b491, the
milestones done and the repository of its own; 2.1.0 the first rounds of
use.

## Testing

`tests/run.sh` runs five stages in a sandbox, without the network,
and a sixth when it is asked for by name:

| Stage | Checks |
| --- | --- |
| lint | Every file byte-compiles with warnings as errors |
| unit | The ERT suite, twice: on MEGA's Lisp as source and on its compiled copy, each against a session started from the real init files. A test that waits for something that never comes is stopped and Emacs says where it was waiting |
| boot | Startup, from source and from the compiled copy, fails no module, runs no program, opens no connection, and fits the time budget, what is put off until Emacs has started included |
| bench | What a person waits for, each against what it is expected to take: a keystroke, the modeline, the completion menu, listing and matching files, search, save, undo history and tree, debugger messages, first use of a module and of a language server |
| terminal | Real sessions in a pseudo-terminal: 24-bit, 256 and 8 colours, under a tmux terminal type, as a bare copy in `~/.emacs.d`, through chemacs2, and an old Emacs being refused. And four starts in a row on one cache, as after an update: the first makes the compiled copy, the second runs from it, the third waits while Emacs compiles that to native code, the fourth is native from its first moment. And, where tmux is installed, what the grid of a terminal holds, asked of a tmux started for it: after each line of `mega-screen-lines.txt` the cursor is on the character Emacs put it on, every character that was to be shown is on its line, and after a blame note has come and gone the screen holds the lines of the buffer |
| container | Only with `MEGA_REAL_IMAGE` set and named on the command line. A real container, started by podman from a `devcontainer.json` with no network and removed afterwards: programs run and a project built in it, and a program debugged with each debugger the image has, through the adapter client and through its console |

Afterwards the configuration directory must be byte-for-byte what it was.

The repository is the configuration directory, so a clone that is in use
has a `local.el` in it, and that is one machine's settings: the runner
leaves it out, by testing a copy of the configuration without it, and says
so. What is tested is MEGA.

The bench stage is how performance, last of the priorities, is still kept
honest. Each benchmark states what it took on the machine the figures were
set on, and the run prints every time beside that figure. Over one and a
half times it, a line is marked `SLOW` and the run passes; over three
times, it fails. Two fixed pieces of work, one of Lisp and one of starting
programs and using the disk, say how slow the machine is right now, and the
figures are stretched by that; they are taken at the start and at the end,
and again before any benchmark is called a failure, which is then run a
second time. Memory is collected as in a running session. A run can be
saved and compared with (`MEGA_BENCH_SAVE`, `MEGA_BENCH_COMPARE`).

The expected times are kept apart from the benchmarks, in
`tests/mega-bench-history.eld`: for each, every time it was ever held
to, with the date, the commit that changed what it takes, and the reason.
A benchmark has no number of its own, so a time cannot be raised without a
record, and the stage fails on a record that lacks its commit or its
reason, or names a commit the repository does not have. The rule is in
that file and is short: over its time, a benchmark is first explained (the
stage prints the `git bisect` command, starting from the commit of the
last record), then fixed; the time goes up only when the slowdown is the
reasonable, direct and minimised price of a change that is wanted, and
then whoever introduced it adds the record. The commit comes first and the
record after it, in a commit of its own. The
harness was itself tried both ways: a threefold slowdown put into a copy of
the code fails it, and a machine kept busy by twice as many spinning
processes as it has processors does not. A new feature with something a
person waits on gets a benchmark in `tests/mega-bench.el`.

The promises about security and privacy are tested by what happens, not by
what a variable holds: a file of every kind is opened in an untrusted
directory and the programs that start are counted; a secret is edited,
saved and closed, and the state directory is searched for its name; the
stand-in language server writes down what it was told, so "telemetry is
off" is read from the wire.

Things learned while building it, worth keeping in mind:

- Emacs renders no modeline and runs no `emacs-startup-hook` in batch mode.
  Anything that depends on either belongs in the terminal stage, and a probe
  must print an explicit verdict: a clean exit proves nothing.
- Emacs is idle only while it waits for a key with no time limit; not in a
  hook, not in `sit-for`. What MEGA postpones until after startup can
  therefore only be observed by a probe that itself runs from an idle
  timer, which is how the terminal probe runs.
- A batch Emacs is killed, silently, by writing to a program that has
  closed its input (the Emacs you edit in gets an error instead). Stand-in
  programs in the tests read their input; the real case is tried in the
  terminal stage.
- A variable that becomes buffer-local when set needs `setq-default`. A unit
  test scans MEGA's source for plain `setq` on such variables.
- Emacs makes no backups under the temporary directory, which is where the
  sandbox lives; tests that need one lift that rule explicitly.
- In batch mode an error in a process sentinel ends Emacs, and with it the
  whole test run, silently. Code that runs in a sentinel catches its errors.
- ERT runs tests with `debug-on-error` on, which lets errors through
  `with-demoted-errors`. A test of "this failure is only a message" has to
  switch it off.
- A synchronous request to a language server has no time limit in Emacs
  31: eglot passes "none" explicitly, so `jsonrpc-default-request-timeout`
  is never consulted. Anything MEGA asks a server from a hook is bounded
  from outside, with `with-timeout`. Found by a stand-in server that never
  answers; binding the variable had passed review and every other test.
- Emacs remembers whether a directory is in a checkout, and gives a caller
  that does not prompt an answer up to five minutes old. MEGA decides by the
  project's root what may run, so `mega-project-current` asks for the
  two-second answer a command gets.
- ripgrep reads a `.gitignore` only inside a repository unless told
  otherwise (`--no-require-git`), so in a project without version control
  nothing keeps it out of `target/` but MEGA.
- A shell's arithmetic prints a decimal comma in half the world's locales.
  The runner's does not (`LC_ALL=C`).
- Emacs's JIT compiles to native code what it loads *compiled*. Source
  that is loaded as source stays interpreted for good: with nothing to
  byte-compile MEGA's files, none of them was ever native, whatever the
  build of Emacs. And a compiled file is taken on to native code only if
  its source lies beside it, which is why the copy in the cache holds
  both.
- `secure-hash` and `md5` take a coding system into account, and on half
  a megabyte that costs seven milliseconds; `buffer-hash` takes the bytes
  as they are and costs half of one. The fingerprint is computed at every
  start.
- Compiling one module loads the modules it requires, in an Emacs that
  only came to compile. Were one of those a module that saves history when
  Emacs ends, it would save an empty one over yours. Tried without any
  protection, nothing was written: no module requires such a one today.
  The compiling Emacs is still given directories of its own and leaves
  without running exit hooks, so that this stays true whoever requires
  what later.
- A stand-in does what its author knew the real thing to do. The first
  run of the container stage found three faults that every test with a
  stand-in had passed: the commands of a `devcontainer.json` ran before the
  container's own `PATH` was read, so a `PATH` built on it found nothing;
  lldb's adapter starts no program where the kernel refuses to fix
  addresses, which is any container with its system-call filter on; and
  with gdb only a function's arguments were shown, because gdb lists
  arguments, locals and registers as three scopes, marks none as costly,
  and the recording the stand-in was written from came from a function
  without arguments. Each has a unit test now, and the stand-ins were
  corrected to what was recorded.
- A probe that plays the person must not say yes to everything: it will
  agree to something nobody meant. The container probe answers the
  questions it names, reports any other as a failure, and runs with a `git`
  that refuses to fetch.
- A variable of a library that is not loaded yet is not special. Bound
  with `let` in a file with lexical binding it switches nothing off, and
  the library then fails to load inside that `let`. Declare it first.
- A stand-in placed too high hides what lies under it. The parser offer was
  tested with the whole of Emacs's install function replaced, so nothing
  noticed that Emacs learns where a parser's source is only from the
  library its mode is defined in, and was being asked before that was
  loaded: every yes failed without a word and the question came back at
  each file. The test now starts a session per language, as the first file
  of a session would, and replaces only the step that runs git and the
  compiler; and it takes away every program first, in case the stand-in
  does not hold, which it did not at the first try.
- A window layout saved while a prompt is open has the prompt for its
  selected window. Put back after the prompt has closed, it leaves the
  cursor in a prompt that is not there, and Emacs waiting for keys nobody
  can give it. The layout that showing a hit puts back is taken before
  the prompt opens. The unit tests have no prompt and passed; the
  terminal stage, which has one, stopped answering.
- Emacs and a terminal each count the cells of a line, and nothing makes
  them agree. A skull with U+FE0F after it is one cell to Emacs and two to
  tmux; and whatever Emacs joins on a terminal it takes for one cell, a
  syllable of Hangul or an emoji with a mark included. Where they differ
  Emacs writes over text it meant to keep, on that line and the ones
  beside it, and the user sees typed text gone. The buffer was whole every
  time, and no unit test can see any of it: they have no screen. The
  terminal stage asks a real tmux what is under the cursor.
- A check passes on less as readily as on right. The first cure switched
  Emacs's joining of characters off; the cursor was where it should be on
  every line, and every accent, vowel sign and Thai tone mark had left the
  screen, because a terminal is sent those only joined to their letter.
  The stage now also asks that each character of a line is on it. What is
  joined is what takes one cell on both sides, and the rest goes out
  character by character.
- What a user saw is evidence; what did it is another question. "The
  blame note appeared and the text I had typed was gone" was first put
  down to the miscounted cells above, because that could be reproduced and
  looked the same. The stored undo history of the file said otherwise: the
  text had been removed by an undo, which Emacs records as one, with the
  state it led back to; a deletion by anything else carries no such mark.
  One step of undo had taken the second half of a word, the note came half
  a second later as it does after any key, and half a word does not look
  like an undo. The history that survives a restart is also the record of
  what happened to a text, and is where to look first.
- A default that suits most files is wrong in the others without a sign.
  MEGA indents with spaces; in a file indented with tabs that put spaces
  between tabs, and the two look alike on the screen. The same history
  shows it: four spaces deleted by hand and typed again. A file's own
  lines now decide where the project, the file and the mode say nothing.
- That a function is there does not say that it works. MEGA was to run
  on an Emacs without native compilation, and early-init.el asked
  `(fboundp 'startup-redirect-eln-cache)` before moving the native-code
  cache: the function is in every Emacs, and in one without native
  compilation it fails on a variable only native compilation defines.
  The error stopped early-init.el, and MEGA configured nothing at all.
  Every other place that touches native code had been read and found
  guarded; only an Emacs built without it showed this one. The whole
  suite has been run on such an Emacs since.
- An example in a comment is code that nothing runs. The template's first
  example, `(setq-default fill-column 100)`, had never worked: local.el
  loads before the modules, and mega-core sets the same default after it.
  The template is now every setting and a few recipes, and a test loads
  all of it uncommented in an Emacs of its own and checks what each recipe
  does, and that every setting is there with the value and the words it
  has in the code.
- Tests are worth only what they can fail on. Each milestone's safety,
  privacy and security checks were run against deliberately broken copies
  of the code (`MEGA_TEST_CONFIG` points the suite at a copy).

## Installing and updating

MEGA is installed by cloning this repository to the directory Emacs is
pointed at, and updated by pulling. Git then leaves the directory holding
exactly the new version's files, which is all an installer has to get
right; `local.el` is ignored by git and so is never in its way. MEGA began
as a directory of its author's dotfiles and was moved out with its
history: each commit from before the move ends in a `Dotfiles-commit:`
line naming the commit it was there, and in those commits the files are
where they were then, under `.mega2.d/` and `tests/mega2/`.

Neither git nor an installer is needed to run it. MEGA is three things,
`early-init.el`, `init.el` and `lisp/`, and it finds the others from where
`early-init.el` lies: so a copy of them works in any directory Emacs is
pointed at, and in `~/.emacs.d` with nothing to start it but Emacs. The
terminal stage runs it that way and checks that nothing was written into
`~/.emacs.d`, which is where Emacs writes by habit.

What makes an update safe on MEGA's side is that nothing it keeps is
trusted on the way back in: the trust store, workspaces, undo histories and
approvals are data, checked when read, and ignored when they do not check,
which costs a question asked again and never a file. The compiled copy is
used only for the source it was made from. And MEGA writes nothing into
its own directory, so git finds there what you changed and nothing that
running Emacs did.

## Open points

- **What compiling buys**, measured on the machine the bench figures were
  set on. Start-up: 50 ms as source, 36 ms from the compiled copy, 27 ms
  as native code. Compiled against source, the large factors are in the
  undo code (a megabyte of history brought back in 7 ms instead of 75, a
  move in a tree of 2000 changes in 1.5 ms instead of 12); a keystroke
  costs 0.020 ms instead of 0.027. The bench stage times the source, which
  is the slowest MEGA ever runs and the only form every machine has from
  the first start.
- **What it leaves behind.** About 1 MB for the compiled copy and 5 to 8 MB
  of native code, under `~/.cache/mega2`. Emacs keeps the native file of
  every version of a module it ever compiled; nothing prunes those.
  Deleting the cache directory is always safe.
- **Native compilation is Emacs's.** MEGA makes the compiled copy; the
  step from there to native code is Emacs's JIT, left as it comes, and it
  takes what a session loads: the modules loaded at start in the first
  session (about a quarter of a minute of background work), one that loads
  on first use in the session that first uses it. The boot test switches
  the JIT off to listen for MEGA alone. Emacs takes a native file only if
  it is no older than the compiled file it stands for, so a copy that is
  made again keeps the time of every compiled file that came out byte for
  byte the same: after an update only what changed is compiled to native
  code again, and `M-x mega-compile-now` on an unchanged source costs
  nothing. Before that, every remake sent all of it through the JIT again,
  and the doctor showed fewer native functions than the day before with
  nothing to say why; it now says when Emacs is still at it.
- **Parsers.** An Emacs built against tree-sitter 0.20 accepts ABI 13–14 only.
- **Cells.** MEGA keeps Emacs and a terminal agreed on the width of what a
  terminal joins. It cannot know what a terminal takes a single character
  for: one that is newer than the terminal's tables (an emoji of Unicode 16
  where the system knows 15) is two cells to Emacs and one to tmux, and
  its line is drawn wrong for as long as it is on the screen. The same holds for the marks of a
  few scripts added to Unicode lately. A mark after a character of two
  cells (kana written with a separate voicing mark, Hangul written as its
  parts) is drawn in a cell of its own: readable, exact, and not pretty.
- **Claude in the built-in terminal emulator** may render imperfectly. Inside
  tmux the session opens in a pane instead, which is the default there.
  Neither has been tried against the real program by the tests, which use a
  stand-in. The arguments of `mega-claude-print-arguments` are taken from
  the program's own help and their values pass its checks, but no question
  has been sent with them: that would have been a request nobody asked for.
- **Debugging in a container** is run for real by the container stage:
  lldb 19 and gdb 16.3, each through the adapter client and through its
  console (the fallback), with a breakpoint set from the buffer on the host
  and the line followed in the host's file. It needs nothing of the
  container: no added capability, no system-call filter switched off.
  Where the kernel will not fix a program's addresses MEGA finds that out
  first and tells lldb not to insist (`mega-dap--fixed-addresses-p`); the
  price there is that addresses differ from run to run.
- **Adapters.** lldb-dap and gdb are in `mega-dap-adapters`; both were run
  for real, lldb also on a Rust program (with the scripts Rust ships, a
  `String` shows as its text). debugpy would be one more row with a
  `:launch` function. Not done: conditional breakpoints, watch expressions,
  expanding a structure in the variables list, several threads shown at
  once, attaching to a running program, and giving the program arguments
  or input.
- **lldb through GUD in a container** works, but a command given in the
  first second is lost: Emacs's lldb interface sets lldb up by feeding it
  Python, and without a terminal lldb takes whatever arrives meanwhile as
  more Python. On the host lldb could not be tried at all: none is
  installed.
- **A project without version control** is recognised by a manifest at its
  root (`mega-project-markers`, by default the kinds marked `:root` in
  `mega-project-kinds`). The list is deliberately short; a Makefile is not
  on it, because one may sit in any directory. What a build put there is
  left out of its files and of a search by name
  (`mega-project-ignored-directories`), since no ignore file says so.
- **Trust is by path.** A decision is kept for the root's file name, not
  for the repository's identity: a different project unpacked at a path you
  once trusted is trusted. Storing an identity beside the path was
  considered in review and left out: there is none that a hostile checkout
  could not copy.
- **Undo tree extras** left out: a diff between two states, and marking the
  state that is saved on disk.
- **One ruler.** Emacs draws a single ruler; several at once would be new code.
- **Breakpoints with GUD** still need a running debugger: only the adapter
  path keeps them between sessions.
