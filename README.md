<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.png">
    <img alt="nudge — the reviews waiting on you, and for how long" src=".github/assets/banner-light.png" width="100%">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/foobarnes/nudge/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/foobarnes/nudge?style=flat-square&color=7457FF&label=release"></a>
  <a href="https://github.com/foobarnes/nudge/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/foobarnes/nudge/total?style=flat-square&color=2A1A8A"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="https://github.com/foobarnes/nudge/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/foobarnes/nudge/ci.yml?branch=main&style=flat-square&label=CI"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/github/license/foobarnes/nudge?style=flat-square&color=8E8E93"></a>
</p>

<p align="center">
  <b>A tiny macOS menu bar app that tells you when someone requests your review on a GitHub pull request,<br>and shows how long it has been waiting on you.</b>
</p>

<p align="center">
  <a href="https://github.com/foobarnes/nudge/releases/latest"><img alt="Download for macOS" src="https://img.shields.io/badge/Download_for_macOS-7457FF?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">
  <img alt="The Nudge pill, expanded, listing four pull requests waiting on review with live timers" src=".github/assets/hero.png" width="100%">
</p>

## Features

| | |
| --- | --- |
| ⏱️ **Live timers** | Every PR waiting on you counts up from the moment your review was requested, in real time and in working hours. |
| 🟣 **A glass pill that stays out of the way** | It floats above your work, shows a count and the oldest wait, and expands on hover. Drag it anywhere, or keep Nudge in the menu bar only. |
| 🟠 **Tiers, not noise** | Grey when fresh, amber after 4 working hours, red after 8. One wiggle and one reminder, then it stays quiet. |
| 🔔 **Notifications you control** | Per-org and per-repo rules, snooze, and "hide until re-requested". |
| ▶️ **Start-review actions** | One click runs your own commands in Ghostty, cmux, iTerm2, Warp, WezTerm, kitty, Alacritty or Terminal, opens URLs, or runs scripts in the background. PR text is passed as data, never as code. |
| 🔄 **Updates itself** | Signed, notarized and kept current with Sparkle. |

<p align="center">
  <img alt="Settings, Actions tab: custom start-review commands with placeholders and a live preview" src=".github/assets/settings-actions.png" width="80%">
</p>

## Install

1. Download **[the latest DMG](https://github.com/foobarnes/nudge/releases/latest)**.
2. Drag **nudge** to Applications.
3. Sign in to the [GitHub CLI](https://cli.github.com) once with `gh auth login`. Nudge reads review requests through `gh` and never stores a token of its own.

<p align="center">
  <img alt="The Nudge install window: drag nudge to Applications" src=".github/assets/install.png" width="66%">
</p>

Requires **macOS 26 or later**. Nudge updates itself after that.

## Develop

```sh
make bootstrap   # once: tools + Xcode project
make run-debug   # build Debug and launch it
make test        # package tests
```

The design spec lives in [`docs/specs/`](docs/specs/). Every merge to `main` ships a signed, notarized release with generated notes, and PR titles must be [Conventional Commits](https://www.conventionalcommits.org). See [docs/releasing.md](docs/releasing.md).

README images are rendered by [`.github/assets/render.swift`](.github/assets/render.swift).

## License

[MIT](LICENSE)
