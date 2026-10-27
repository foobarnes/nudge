# Phase 0 — De-risk spike findings

Date: 2026-10-27 · Branch: `spike/phase0` · Spec: [`docs/specs/2026-10-27_nudge-v0.md`](../specs/2026-10-27_nudge-v0.md)

Environment: macOS 27.0, Xcode 26.6 (macOS 26.5 SDK), Swift 6.3 (`-swift-version 6`, strict concurrency complete), XcodeGen, Ghostty 1.3.1.

Spike code lives in `spikes/<name>/` and is throwaway. Each folder has a `run.sh`.

| # | Spike | Result |
| --- | --- | --- |
| 1 | GraphQL query, team query, cost | **PASS** |
| 2 | Agent-app notifications + actions | **NEEDS MANUAL CHECK** (prompt + grant PASS; action click pending) |
| 3 | Terminal launch + injection safety | **PASS** (one hardening change; Nudge's own Automation prompt is checked manually in spike 2) |
| 4 | Non-activating `NSPanel` pill | **NEEDS MANUAL CHECK** (build, render, no focus steal, hover, and menu PASS; Esc, snap, Spaces/full screen pending) |

Privacy: no output below contains real org names, repo names, titles, logins, or PR numbers. Scripts print shapes and numbers only. Screenshots stayed outside the repo.

---

## 1. GraphQL — PASS

**Commands** (`spikes/graphql/run.sh`): the spec's `Waiting` query copied verbatim (`waiting.graphql`), the team-membership query (`teams.graphql`), and a by-node reviewer refetch (`refetch.graphql`).

```text
$ gh api graphql -F query=@waiting.graphql | jq '{errors, cost, nodes, rrPageInfo, eventsWithId, eventsWithActor}'
{ "errors": null, "cost": 1, "nodes": 3,
  "rrPageInfo": [["hasNextPage"], ["hasNextPage"], ["hasNextPage"]],
  "eventsWithId":    [true, true, true, true, true, true],
  "eventsWithActor": [true, true, true, true, true, true] }

# per-node shape (values stripped)
keys: author,headRefName,id,isDraft,number,repository,reviewRequests,timelineItems,title,url
PR id prefix: "PR_" · ReviewRequestedEvent id prefix: "RRE_" · ReadyForReviewEvent: no id (not requested)
ReviewRequestedEvent.requestedReviewer keys: "__typename,login" (User) / "__typename,organization,slug" (Team)
node 1: viewer is NOT among User reviewers; matched via a Team request   ← review-requested:@me includes team requests

$ gh api graphql -F query=@teams.graphql -f login=<viewer> | jq '{errors, cost, orgs}'
{ "errors": null, "cost": 1, "orgs": 3 }

$ gh api graphql -F query=@refetch.graphql -f id=<PR node id>     # node(id:){...reviewRequests(first:100, after:$cursor)}
{ "errors": null, "cost": 1, "pageInfoKeys": ["endCursor", "hasNextPage"], "n": 2 }

$ # rateLimit(dryRun: true) on the full Waiting query shape (first: 50, reviewRequests 100, timeline 50)
{ "dryRunCost": 1 }

$ gh api graphql -i -F query=@waiting.graphql | grep -i '^x-ratelimit'
X-Ratelimit-Limit: 5000
X-Ratelimit-Remaining: 4759
X-Ratelimit-Reset: 1793130392
X-Ratelimit-Resource: graphql
X-Ratelimit-Used: 241
```

**Findings**

- Every field name in the spec query exists. No errors and no scope problems with the default `gh` token.
- `actor { login }` and the event `id` come back on every `ReviewRequestedEvent`.
- `reviewRequests(first: 100) { pageInfo }` works. The refetch by node ID with `after:` works too.
- **Cost: 1 point per search page.** The dry run on the full `first: 50` shape also costs 1, so a sync costs ≤ 4 points (4-page cap). The team query costs 1 per hour. At a 60 s interval that is ≤ 240 points/h, under 5% of 5,000.
- Search results include drafts. The spec expects this, and the resolver filters them.

**Spec changes**

1. The spec query can't paginate reviewers. Under Examples:
   > `reviewRequests(first: 100) { pageInfo { hasNextPage } nodes { requestedReviewer {`

   Replace with:
   > `reviewRequests(first: 100) { pageInfo { hasNextPage endCursor } nodes { requestedReviewer {`

   Add the refetch query next to it:
   ```graphql
   query Reviewers($id: ID!, $cursor: String) {
     node(id: $id) { ... on PullRequest {
       reviewRequests(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor }
         nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug organization { login } } } } } } }
   }
   ```
2. The adaptive interval is dead code at the measured cost. Under Architecture → Rate limits:
   > Actual cost is read from `rateLimit { cost }` and logged; if it exceeds 5 points per sync, the interval widens so usage stays under 10% of the hourly budget.

   Replace with:
   > Actual cost is read from `rateLimit { cost }` and logged. Measured: 1 point per search page (≤ 4 per sync, ≤ 240/h at 60 s), so v0 has no adaptive interval. Rate-limit responses still use the backoff above.

---

## 2. Notifications from an ad-hoc-signed agent app — NEEDS MANUAL CHECK

`spikes/notify/` is an `LSUIElement` app (`io.github.foobarnes.nudge.spike-notify`) with ad-hoc signing and no hardened runtime, installed at `/Applications/NudgeSpikeNotify.app`. At launch it registers category `REVIEW_REQUEST` with `OPEN` (`.foreground`) and `SNOOZE_1H`. It requests authorization from `applicationDidFinishLaunching` without activating the app, then posts one synthetic notification (id `RRE_example`). It writes a log to `~/Library/Logs/NudgeSpike/notify.log`. When "Open" is clicked, it also runs a Terminal.app `do script` through `NSAppleScript`, which tests Nudge's own Automation prompt (spike 3). Its status item `N0` has "Post notification" and "Quit".

```text
$ spikes/notify/run.sh install
Identifier=io.github.foobarnes.nudge.spike-notify
Signature=adhoc
19:34:39Z launched bundle=/Applications/NudgeSpikeNotify.app
19:34:39Z before-request authorizationStatus=0 alertStyle=1     # notDetermined → system prompt shown
19:36:22Z requestAuthorization granted=true                     # user clicked Allow
19:36:22Z after-request authorizationStatus=2 alertStyle=1      # authorized, banner style
19:36:22Z posted err=nil
```

**Verified:** an ad-hoc-signed `.accessory` app in `/Applications` gets the system permission prompt and is authorized. The request was made at launch without activating the app. Swift 6 strict concurrency needs the delegate to be `@MainActor` with `nonisolated` async `UNUserNotificationCenterDelegate` methods.

**Pending (human):** that the "Open" and "Snooze 1h" buttons deliver `didReceive action=OPEN|SNOOZE_1H`, that a repeat post with the same identifier replaces the banner instead of stacking, and that the Terminal Automation prompt appears for this bundle.

**Spec changes**

1. Under Tricky / Non-Obvious Parts → Agent-app quirks:
   > A `UNUserNotificationCenter` authorization request must happen after launch, while the app can be activated.

   Replace with:
   > Request `UNUserNotificationCenter` authorization from `applicationDidFinishLaunching`. No activation is needed; the prompt appears for an `.accessory` app (verified on macOS 27, ad-hoc signed, in `/Applications`). The delegate is `@MainActor`, with `nonisolated` async delegate methods under Swift 6.

---

## 3. Terminal launch and injection safety — PASS

`spikes/terminal/render.swift` implements the spec's shell rendering. It turns each token into `${NUDGE_PR_*}` and writes single-quote-escaped `export` lines plus `trap 'rm -f "$0"' EXIT` into a `0700` directory. `run.sh [inject|ghostty|terminal]` drives it.

**Injection (hostile title):**

```text
title:    Fix "auth" $(touch $out/pwned1) `touch $out/pwned2` '; touch $out/pwned3; ' ${(e)$(touch $out/pwned4)} * ; touch $out/pwned5
template: printf "%s\n" "{title}"; echo {title}; x=$(echo {title}); print -r -- "sub:$x"
dir/file: drwx------ …/nudge-spike-…/  ·  -rwx------ action.zsh
stdout:   the title, verbatim, three times (bare, quoted, inside $(…))
markers:  ls $out/pwned*  →  no matches found          ← PASS
script deleted after run: yes
```

**Hardening gap found:** the safety argument depends on zsh *default* options. A login shell sources `~/.zprofile`/`~/.zlogin`. If the user sets `sh_word_split` or `glob_subst` there, a bare token gets split and globbed. It still can't run commands, but arguments change:

```text
$ title='two words *.txt'  template='print -l -- {title}'   (cwd has a.txt b.txt)
default options:                 two words *.txt
-o shwordsplit -o globsubst:     two / words / a.txt / b.txt        ← args changed
same + `emulate -R zsh` in script: two words *.txt                  ← fixed
```

**Ghostty** (`Ghostty 1.3.1`, stable channel):

```text
$ open -na Ghostty.app --args -e /bin/zsh -l "$script"     # script writes a marker
open-exit=0 · marker after 2s: "ok 4211 <epoch> <PATH with /opt/homebrew/bin …>"   ← PASS, login PATH applied
new Ghostty instance after script exits: none (window closes immediately)
$ open -na Ghostty.app --args --wait-after-command=true -e /bin/zsh -l "$script"
new Ghostty instance after script exits: still running (window stays open)
```

**Terminal.app:**

```text
$ osascript -e 'on run argv' -e 'tell application "Terminal" to do script "/bin/zsh -l " & quoted form of (item 1 of argv)' -e 'end run' "$script"
tab 1 of window id … · osa-exit=0 · marker after 5s: "ok 4211"        ← PASS
```

The host process already had Automation permission for Terminal, so no prompt appeared. The prompt for Nudge's own bundle ID is covered by the spike 2 manual step ("Open" runs `do script`). Terminal.app keeps the window open after the script exits (`[Process completed]`), so Ghostty and Terminal behave differently by default.

**Spec changes**

1. Under Action Templates → Passing values:
   > The script holds `export NUDGE_PR_…='<value>'` lines, each value single-quote escaped (an assignment context, so this is safe), followed by the user's rendered template.

   Replace with:
   > The script starts with `emulate -R zsh` (which resets options a user's `.zprofile` may have changed, such as `sh_word_split` and `glob_subst`), then holds `export NUDGE_PR_…='<value>'` lines, each value single-quote escaped (an assignment context, so this is safe), followed by the user's rendered template.
2. Under Execution contract → Kinds → `terminal`:
   > `terminal`: Ghostty → `open -na Ghostty.app --args -e /bin/zsh -l <script>`;

   Replace with:
   > `terminal`: Ghostty → `open -na Ghostty.app --args --wait-after-command=true -e /bin/zsh -l <script>` (without the flag the window closes the moment the command exits, so output from e.g. `gh pr checkout` is lost; verified on Ghostty 1.3.1);
3. Open Questions: remove "Does `open -na Ghostty.app --args -e …` run the command reliably on current Ghostty for macOS?…". It is answered: yes, on Ghostty 1.3.1.

---

## 4. Non-activating `NSPanel` pill — NEEDS MANUAL CHECK

`spikes/panel/` (`io.github.foobarnes.nudge.spike-panel`, runs from `build/`, no install) has:

- A status item (`clock.badge` + count).
- An `NSPanel` with `[.nonactivatingPanel, .borderless]`, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`, and a clear background.
- An `NSHostingView` with a SwiftUI `GlassEffectContainer` + `.glassEffect(.regular, in: .rect(cornerRadius:))` capsule, and two `Menu`s (Start, Snooze).
- Hover through an `NSTrackingArea` (`.mouseEnteredAndExited, .activeAlways, .inVisibleRect`).
- Esc through `cancelOperation` (only when key).
- Edge snap on drag end, from a local `leftMouseUp` monitor plus a 0.35 s animation.
- Grow-before-expand / shrink-after-collapse resizing.
- `--demo` expands at +2 s and collapses at +6 s with no input.

Events go to `~/Library/Logs/NudgeSpike/panel.log` with the frontmost app on every line.

```text
$ spikes/panel/run.sh demo
frontmost before: <browser>
frontmost after launch: <browser>
frontmost while expanded: <browser>                                     ← no focus steal
panel shown frame=(1566,1032,150,40) isKey=false active=false
expanded=true frame=(1376,902,340,170) isKey=false

# real user interaction captured in the log while the app ran (another app frontmost throughout):
mouseEntered [frontmost=<browser>] → expanded=true isKey=false      ← .activeAlways hover works while inactive
menu begin isKey=false [frontmost=<browser>]                        ← SwiftUI Menu opens without key status
menu end … → mouseExited → expanded=false
```

Screenshots (`screencapture -x -R …`, kept outside the repo because the background shows personal data) confirm that the collapsed capsule and the expanded glass card render with Liquid Glass, the tier-colored dots, monospaced timers, and the Start ⌄ / Snooze ⌄ menus.

**Findings**

- Builds clean under Swift 6 strict concurrency, but `NotificationCenter`/`NSEvent` monitor closures need `MainActor.assumeIsolated` and explicit `self.`.
- The panel never became key and never activated the app on launch, hover, or menu open.
- A SwiftUI `Menu` inside the panel opens and tracks with `isKey=false`. "The pill can become key only while a menu is open" isn't needed.
- **Spurious hover exits.** Resizing the panel rebuilds the tracking area, and the log shows `mouseEntered`/`mouseExited` pairs within the same second right after a resize. The spike now debounces exit by 150 ms and confirms it against `NSEvent.mouseLocation` before collapsing. The manual check should confirm there's no flicker.
- `NSScreen.main` is the screen with the *key window*, which may be a different display than the menu bar. After the user switched apps, a relaunch placed the pill on another display. Default placement should use the status item's screen.

**Pending (human):** Esc collapses after a click into the pill, drag snaps to the nearest edge, the pill shows on every Space and over a full-screen app, and focus returns to the previous app after a menu or Esc.

**Spec changes**

1. Under UI/UX → Keyboard & VoiceOver:
   > The pill can become key only while one of its menus (Start ⌄, Snooze ⌄) is open, and focus returns to the previous app afterwards. The pill stays expanded while a child menu is open.

   Replace with (pending the Esc check):
   > The pill never becomes key on hover or when a menu opens; SwiftUI `Menu` tracks without key status (verified). It becomes key only after a click inside it, so Esc (`cancelOperation`) can collapse it, and it resigns key on collapse. The pill stays expanded while a child menu is open (`NSMenu.didBegin/EndTrackingNotification`).
2. Under Tricky / Non-Obvious Parts → Pill behavior, add:
   > Resizing the panel rebuilds the tracking area and can emit spurious enter/exit pairs. Debounce exit (~150 ms) and confirm with `NSEvent.mouseLocation` before collapsing.
3. Under UI/UX → Drag + snap:
   > On display change or unplug, restore that display's anchor or default to top-right.

   Replace with:
   > On display change or unplug, restore that display's anchor or default to top-right of the status item's screen (`statusItem.button?.window?.screen`), not `NSScreen.main`, which follows the key window.

---

## Manual checks (≈ 4 min)

1. **Notification actions (~1 min).** Click the `N0` menu bar item → "Post notification". On the banner, open the actions menu and click **Snooze 1h**. Post again and click **Open**. Allow the Terminal Automation prompt if it appears. Then run `spikes/notify/run.sh log` and expect `didReceive action=SNOOZE_1H`, `didReceive action=OPEN`, and `terminal do script error=nil`.
2. **Pill hover + menu (~1 min).** Run `spikes/panel/run.sh interactive`. Hover the pill in the top-right: it should expand without flicker. Open Start ⌄, pick an item, and confirm it stays expanded while the menu is open. Move away and it should collapse. Keep typing in another app throughout to confirm focus is never stolen.
3. **Esc + snap (~1 min).** Click the pill, press Esc (it should collapse), then type in your previous app and confirm keystrokes land there. Drag the pill to mid-screen and release; it should spring to the nearest edge with a 12 pt inset.
4. **Spaces + full screen (~1 min).** Switch Spaces (Ctrl-→) and full-screen any app (Ctrl-⌘-F). The pill should stay visible on both.
5. **Cleanup.** Run `spikes/notify/run.sh clean && spikes/panel/run.sh clean`. This removes `/Applications/NudgeSpikeNotify.app`, the build output, the logs, and the TCC entries.
