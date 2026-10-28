# Nudge

A tiny macOS menu bar app that tells you when someone requests your review on a GitHub
pull request, and shows how long it has been waiting on you.

- Lives in the menu bar, or as a small always-on-top glass pill you can drag anywhere.
- Live count-up timer per PR, running only while a review request to you is active.
- Native notifications, per-org/repo notification rules, and custom "start review" actions.

Requires macOS 26+ and the [GitHub CLI](https://cli.github.com) (`gh auth login`).

## Install

Download the latest `Nudge-x.y.z.dmg` from [Releases](https://github.com/foobarnes/nudge/releases/latest) and drag
Nudge to Applications. It updates itself after that.

## Develop

`make bootstrap` once, then `make run` (or `make run-debug`). The design spec lives in `docs/specs/`.

Every merge to `main` ships a signed, notarized release with generated notes; PR titles must be Conventional Commits.
See [docs/releasing.md](docs/releasing.md).

## License

MIT
