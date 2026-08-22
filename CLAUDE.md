# omarchy-capacities — working notes

An Omarchy shell plugin: capture to today's Capacities daily note, search the
space, and a bar panel showing today / open tasks / recently created.

**This directory is the development home. It is not the installed plugin.**

## Two checkouts, on purpose

| Path | What it is |
| --- | --- |
| `~/src/omarchy-capacities` | this repo — where you edit, commit, push |
| `~/.config/omarchy/plugins/riclib.capacities` | the installed copy, cloned by `omarchy plugin add` |

They are separate clones of `github.com/riclib/omarchy-capacities`. Do not
symlink one to the other: `omarchy plugin validate` rejects symlinks inside a
plugin folder outright, and the plan is for the installed copy to come from the
marketplace like anyone else's.

The loop is therefore: edit here → commit → push → update the installed copy:

```bash
omarchy plugin update riclib.capacities --yes   # pulls origin into the installed clone
omarchy restart shell                           # see the gotcha about caching below
```

Without `--yes` it prints the incoming diff and waits for a keypress, which
hangs an agent.

For a fast inner loop while iterating on QML, edit the installed copy directly
(it hot-reloads), then port the change back here and delete it there before
`plugin update`. Never let the two diverge silently — check both with
`git -C <path> log --oneline -1`.

## Trying it

```bash
./bin/omarchy-capacities status          # token, space, queue depth
./bin/omarchy-capacities capture "text"  # writes to the real daily note
./bin/omarchy-capacities sync            # refresh what the panel reads
node --test tests/model.test.js          # 12 tests, no network
tests/cli.test.sh                        # 16 tests, no network, no token
```

Both suites run without a token or a network. `tests/cli.test.sh` uses a
throwaway `XDG_STATE_HOME`, a fake `HOME` for the uninstaller, and a local
server that floods the connection — nothing in them touches the real space.

The shell's own diagnostics:

```bash
journalctl --user --since "2 minutes ago" | grep -i riclib
qs -p /usr/share/omarchy/shell/shell.qml ipc show | grep riclib   # 3 targets
omarchy-shell riclib.capacities.bar toggle                        # the panel
omarchy-shell shell toggle riclib.capacities '{}'                 # the overlay
```

## Layout

```
manifest.json     id, kinds (overlay + bar-widget), the bar widget's settings schema
Capture.qml       the overlay: capture and search modes, key handling, results
BarSlot.qml       the bar lamp: outbox badge, hosts the panel, IPC routing
Panel.qml         today / open tasks / recent, and the actions
PanelRow.qml      one clickable line
Model.js          parsing and index arithmetic — plain JS, tested with node
bin/omarchy-capacities  the API client: token, outbox, caches, sync
bin/capacities-setup    first-load setup: config, menu rows, PATH
bin/capacities-bind-key the three shortcuts, when asked for
bin/capacities-uninstall takes back exactly what setup added
```

The QML never talks to the API. The token belongs in a 0600 file rather than in
the shell's process state, a failed capture belongs in a queue on disk, and the
structure list wants a cache. All three are ordinary in Python and miserable in
QML.

## Gotchas, each of which cost an afternoon

**A bar widget component is cached by URL.** Editing `BarSlot.qml` or
`Panel.qml` in place does nothing — not even `omarchy-shell shell
rescanPlugins` reloads it, because the shell skips reloading when the component
URL is unchanged. `omarchy restart shell` is the only thing that picks it up.
The overlay (`Capture.qml`) *does* hot-reload, which makes this easy to
misdiagnose.

**`data` is `Item`'s default property.** Declaring `property var data` silently
shadows the child-object list, so every read returns children and every field is
`undefined`. `Panel.qml` calls it `cache` for this reason. Same trap waits for
anything else QML already defines.

**Naming a QML file after the type it extends breaks it.** `BarWidget.qml`
whose root is `BarWidget` (from `qs.Ui`) fails to load with "File name case
mismatch" — the local directory is an implicit import, so the type resolves to
itself. Hence `BarSlot.qml`.

**Every `Text` must set `textFormat: Text.PlainText`.** Qt defaults to
`AutoText`, which guesses rich text, and rich text loads resources. The
marketplace security review flagged exactly this. Anything holding an API
string — a title, an error, a structure name — decides what the shared shell
process fetches otherwise. There is a re-audit one-liner in "Before a release".

**IPC routes to one handler, but bar widgets are live once per monitor.** A
keybinding that opens the panel will open it on whichever screen registered
first unless it resolves the focused instance via `bar.findPanelWidget`. See
`focusedInstance()` in `BarSlot.qml`. Refreshes broadcast instead, because a
refresh is not a place.

**`omarchy plugin remove` + `add` drops the widget from the bar.** The layout
in `~/.config/omarchy/shell.json` loses the entry and `omarchy bar put` does not
reliably put it back; edit `bar.layout.right` in that file directly — it
hot-reloads.

## The API, and what it cannot do

Base `https://api.capacities.io`, spec at `https://developers.capacities.io/openapi.json`
(v1.0.0 — note `api.capacities.io/openapi.json` serves an older beta surface).
Token from the app: Settings → Capacities API. One token, one space.

- **Quotas are per-endpoint and small**: 10/60s for space reads, 30/60s for
  objects, search and appends. Nothing here polls. Opening the panel syncs, and
  only if the cache is over two minutes old.
- **`POST /blocks/daily-note/append` is not used.** It answers `200` with an
  empty body and delivers minutes later, which an outbox cannot work with — a
  queue can only hold what did not arrive if arrival is knowable. Captures
  resolve the day's note by title and use `POST /blocks/append`, which is
  immediate and verifiable. If that endpoint ever gets a delivery guarantee,
  the resolve step is what to delete.
- **List responses carry no timestamps, no ordering and no task state** — only
  id, structureId and title, and `sort` parameters are ignored. So "recent" and
  a task's open/done state are one object read each, cached on disk and capped
  per sync. `omarchy-capacities warm --minutes 10` paces a full warm-up against
  the quota.
- **A creation time only exists on types that carry the *Created at* property**,
  which is off by default. Custom types can be given it in the type's settings;
  basic ones (Task, Daily Note, Tag, Query, AI Chat) cannot — *"properties of
  basic object types cannot be edited"*. The sync skips types that lack it
  rather than spending reads that can never produce anything, and says which.
- **Deep links**: `capacities://<spaceId>/<objectId>`, with `?bid=<blockId>` for
  a single block. There are also x-callback URLs
  (`capacities://x-callback-url/appendToDailyNote?content=…`) which write
  through the running app with no rate limit — attractive, but fire-and-forget,
  so there is no success signal and no honest outbox. Unused for that reason;
  worth revisiting as an opt-in `captureVia: "app"`.

## Before a release

```bash
node --test tests/model.test.js && tests/cli.test.sh
omarchy plugin validate .
# no Text may be left on AutoText — the security review checks this
for f in *.qml; do awk '/^\s*Text \{/{s=NR;b="";d=1;next} s&&d>0{b=b"\n"$0; if(/\{/)d++; if(/\}/)d--; if(d==0){if(b !~ /textFormat/) print FILENAME": Text at "s" has no textFormat"; s=0}}' "$f"; done
# nothing private, in the tree or the history
grep -rniE 'cap-api-[a-zA-Z0-9]{6}' --exclude-dir=.git --exclude=CLAUDE.md .
git log -p --all | grep -iE 'cap-api-[a-zA-Z0-9]{6}' | sort -u
#   the only expected hit is the fixture "cap-api-stored" in tests/cli.test.sh
```

Then bump `version` in `manifest.json`, commit, tag `vX.Y.Z`, push both.

Screenshots: `preview.png` is the panel, blurred by hand over the space name and
client-identifying rows; `capture.png` is the overlay. **Never publish an
unblurred panel or search screenshot** — both render real object titles.

## Marketplace

Listed via the plugin marketplace; the listing tracks this repo, so the README
and images can change after approval.

- Submission: https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/1166
- Category **Productivity**, tags **Quickshell / Bar / Launcher** (three is the
  maximum; more are rejected).
- State at last check: `validated`, with `needs-fixes` and
  `security-review-required` still applied. Both review findings — unbounded
  response buffering and `AutoText` sinks — were fixed in v0.3.1 (`6dfccf3`) and
  answered in a comment. Those labels are maintainer-applied and do not clear
  automatically; a human has to re-review.
- The automated baseline will always flag the `installer` capability, because
  `capacities-setup` and `capacities-uninstall` write to the user's menu and
  bindings. That is informational — the README's *What it writes, and taking it
  back* table is the answer to it.

If more findings arrive: fix, add a test that would have caught it, bump the
patch version, tag, push, then reply on the issue with the commit sha and what
changed. Posting there is outward-facing and public under Ricardo's account —
draft it and ask before posting.

## House rules

- The QML never talks to the API. Anything needing a credential, a queue or a
  cache goes in `bin/omarchy-capacities`.
- Nothing polls. A user action is what refreshes.
- Never take a keybinding without being asked; never rewrite a user's file
  wholesale. Everything written outside the plugin sits in a marked block or is
  a symlink setup made, which is what makes `capacities-uninstall` exact.
- A capture must never be lost. Anything that might not have arrived goes to
  the outbox.
