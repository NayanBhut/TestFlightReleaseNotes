# Orca Computer Use — agent how-to

Drive local desktop apps from an agent via accessibility trees, screenshots,
and safe UI actions. Source of truth:
https://www.onorca.dev/docs/cli/computer-use
Installed skill name: `computer-use`
(`npx skills add https://github.com/stablyai/orca --skill computer-use`)

## 0. Resolve the CLI (do this once, reuse it)

Resolution order:

- `$ORCA_CLI_COMMAND` if set (Orca-managed WSL sessions).
- `orca-dev` in a dev checkout exposing `ORCA_DEV_REPO_ROOT`.
- `orca-ide` on Linux outside an Orca-managed terminal (never bare `orca`
  there — it resolves to the GNOME screen reader).
- Otherwise `orca`.

**Known gotcha (seen on this Mac, Oct 2026):** `/usr/local/bin/orca` can be a
root-owned symlink with owner-only perms (`lrwx------ root wheel`) — every
invocation fails with:

```
Unable to determine Orca.app path from symlink: /usr/local/bin/orca
```

It is the same CLI, just unreachable through the shim. Workaround — invoke the
in-app binary directly (same version, same surface):

```sh
/Applications/Orca.app/Contents/Resources/bin/orca --version
```

Verify with `status` before doing anything else.

## 1. First-time setup (every session)

```sh
ORCA=/Applications/Orca.app/Contents/Resources/bin/orca   # or resolved name
$ORCA status --json
$ORCA computer permissions --json
$ORCA computer capabilities --json
```

`permissions` must show `accessibility: granted` and `screenshots: granted`
(macOS needs Screen Recording too, granted to **Orca Computer Use** in System
Settings). If anything is missing, grant it and re-run `permissions --json`.
`capabilities --json` tells you which actions/windows/surfaces this build
supports — read it, don't assume (e.g. this build: no annotated screenshots,
no OCR, no dock/menubar/dialog surfaces, no window focus/move).

## 2. The loop: snapshot → act → snapshot

```sh
$ORCA computer list-apps --json
$ORCA computer get-app-state --app <bundle-id> --json
$ORCA computer click --app <bundle-id> --element-index 42 --json
# …re-read state, verify, repeat
```

- Element indexes are scoped to the **latest** `get-app-state` result and may
  be **sparse**. Read the tree from `result.snapshot.treeText`; never invent
  indexes from `elementCount`.
- Refresh state after navigation, focus changes, scrolling, or any re-render
  before reusing an index.
- `get-app-state` returns a screenshot by default; with `--json` the bytes go
  to disk and `screenshot.path` is returned. Pass `--no-screenshot` when
  pixels aren't needed (faster). Pass `--restore-window` to unhide/minimize.

## 3. Targeting apps and windows

```sh
$ORCA computer get-app-state --app com.microsoft.edgemac --json
$ORCA computer list-windows --app com.microsoft.edgemac --json
$ORCA computer get-app-state --app com.microsoft.edgemac --window-id <id> --json
$ORCA computer click --app com.microsoft.edgemac --window-id <id> --element-index 12 --json
```

Prefer bundle IDs from `list-apps`; names work when unambiguous
(`--app Spotify`); `--app pid:<n>` only when both collide. Prefer stable
`--window-id` when it isn't `none`, else `--window-index`.

## 4. Actions

```sh
$ORCA computer click --app <app> --element-index <i> --json
$ORCA computer set-value --app <app> --element-index <i> --value "text" --json
$ORCA computer type-text --app <app> --text "text" --json
$ORCA computer press-key --app <app> --key Return --json
$ORCA computer hotkey --app <app> --key CmdOrCtrl+A --json
$ORCA computer paste-text --app <app> --text "text" --json
$ORCA computer scroll --app <app> --element-index <i> --direction down --json
$ORCA computer drag --app <app> --from-x 100 --from-y 100 --to-x 300 --to-y 300 --json
$ORCA computer drag --app <app> --from-element-index 3 --to-element-index 9 --json
$ORCA computer perform-secondary-action --app <app> --element-index <i> --action <name> --json
```

Prefer semantic actions (`click`, `set-value`, `perform-secondary-action`) over
`type-text`/`press-key` — they target accessibility elements directly and
survive focus changes. Coordinates (`--x/--y`) are a last resort when
accessibility targeting fails.

Secrets via stdin (never shell history):

```sh
printf '%s' "$TEXT" | $ORCA computer set-value --app <app> --element-index 7 --value-stdin --json
```

(`--text-stdin` likewise for `type-text` / `paste-text`.)

## 5. If the helper won't connect

- `runtime_access_denied` → sandbox blocked the connection: re-run with
  escalated permissions; do **not** run `ORCA open` or restart Orca.
- "Orca is not running" → start it with `ORCA open --json`, then retry.
- CLI itself can't run (symlink error above) → report the exact error, use the
  in-app path from §0 (same binary, not a different executable).

## 7. Lessons from live-driving this repo

- **Same bundle id twice = target by pid.** A released copy in
  `/Applications` and the Debug build share `com.demos.App-Store`; bundle-id
  targeting then fails with `no accessibility window`. Use
  `--app pid:<number>` (doc-allowed for collisions) and quit the copy you
  don't need.
- **AX stall needs a human.** If even Finder reads fail with `no
  accessibility window` while permissions show granted, only toggling Orca
  Computer Use off/on in System Settings recovers — an agent cannot do this.
  Relaunching the target app does not help.
- **Rows that are `Button`s appear as `button` elements** — read the whole
  tree before concluding rows are unreachable (the app row was element 29).
- Destructive controls (remove-team, Cancel submission, Expire Build) are
  reachable by index too — map the tree carefully and never click near them
  on a real account.

## 6. Notes for this repo (App Store Connect client)

- Build: `xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx
  -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build -skipMacroValidation`
- Product: `~/Library/Developer/Xcode/DerivedData/App_Store-*/Build/Products/Debug/App Store.app`
- Unsigned build + sandboxed app (`ENABLE_APP_SANDBOX=YES`) → fresh Keychain
  identity per build: expect Keychain prompts every launch; saved teams look
  "lost" between rebuilds. For a stable live pass, set `ENABLE_APP_SANDBOX=NO`
  (Debug) or remove `keychain-access-groups` locally — re-enable before
  distribution.
- Without a real App Store Connect API key the app sits on "No Teams Yet":
  reachable-without-key surface is first-launch, Add-Team validation,
  `.p8`/garbage-input handling, and empty-state navigation. Deep flows need a
  real key (have the user add a team first, or paste Issuer/Key ID via stdin).
- Static bug list to verify against live: `BUG_SWEEP.md`.
