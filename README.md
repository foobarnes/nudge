# Nudge

A tiny macOS menu bar app that tells you when someone requests your review on a GitHub
pull request, and shows how long it has been waiting on you.

- Lives in the menu bar, or as a small always-on-top glass pill you can drag anywhere.
- Live count-up timer per PR, running only while a review request to you is active.
- Native notifications, per-org/repo notification rules, and custom "start review" actions.

**Status:** pre-v0. The design spec lives in `docs/specs/`.

Requires macOS 26+ and the [GitHub CLI](https://cli.github.com) (`gh auth login`).

## License

MIT
