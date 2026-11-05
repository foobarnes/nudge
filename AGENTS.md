# AGENTS.md

Nudge is a macOS menu bar app (AppKit shell, SwiftUI views) for pull requests waiting on your review. The Xcode
project is generated from `project.yml` by XcodeGen; logic lives in the `Packages/NudgeKit` Swift package.

## Commands

```sh
make bootstrap   # once: Brewfile tools + generate Nudge.xcodeproj
make build       # build the dev app (Debug)
make run         # build and run the dev app in the foreground; Ctrl-C quits. Pass flags with ARGS="..."
make stop        # quit every running dev build, from any worktree; never touches the installed release
make test        # package tests (swift test in Packages/NudgeKit)
make dmg         # Release build packaged into an unsigned build/Nudge.dmg; installs nothing
make clean       # make stop, then remove DerivedData, the generated project, and .build
```

`make run` blocks until the app quits. From an agent, run it in the background and finish with `make stop`.

## Dev build vs. installed release

These are two separate apps. Keep them apart:

| | Dev (Debug) | Release |
| --- | --- | --- |
| Bundle | `Nudge Dev.app` | `Nudge.app` |
| Process (executable) | `Nudge PRs Dev` | `Nudge PRs` |
| Bundle ID | `io.github.foobarnes.nudge.dev` | `io.github.foobarnes.nudge` |
| Shown as | "Nudge Dev", **DEV** in the menu bar | "Nudge" |
| Comes from | `make run` / `make build` | GitHub Releases only (auto-updates through Sparkle) |

- Never copy a local build into `/Applications`. Local builds are ad-hoc signed and have no Sparkle key, so one
  would replace the user's release and turn off its updates.
- Never quit apps by the bare name `Nudge` (`killall Nudge`, `pkill -x Nudge`). macadmins Nudge, an MDM OS-update
  tool, runs as `Nudge`, which is why this app's executable (`EXECUTABLE_NAME`) is `Nudge PRs`. Use `make stop`
  for dev builds.

## Shipping

- PR titles must be Conventional Commits (`feat:`, `fix:`, `chore:`, …), checked by `pr-title.yml`.
- Every merge to `main` releases: the version comes from those titles, and the build is signed, notarized, and
  published with a Sparkle appcast. See [docs/releasing.md](docs/releasing.md).
- The design spec lives in [docs/specs/](docs/specs/).
