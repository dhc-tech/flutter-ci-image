# flutter-android-ci-image

A self-owned Flutter + Android SDK CI Docker image — built from scratch on
plain `ubuntu:24.04`, no third-party Android/Flutter base image. Installs
the Android command-line tools directly from Google's official
distribution, then Flutter at an exact version or channel — no runtime
`git clone`/version-pin workaround needed in your own CI pipeline.

Android only — Docker containers can't build iOS (needs real macOS + Xcode).

## Tags

Published to `ghcr.io/dhc-tech/flutter-android-ci`:

| Tag | What it is | Rebuilt |
|---|---|---|
| `<version>` (e.g. `3.47.2`) / `pinned` | Exact Flutter release, immutable | Only when `FLUTTER_VERSION` changes |
| `stable` / `latest` | Flutter's `stable` channel | Weekly (Mondays) |
| `beta` | Flutter's `beta` channel | Weekly |
| `main` | Flutter's `main` channel (contributor/bleeding-edge — was `master`) | Weekly |

`dev` is intentionally not built — Flutter deprecated it, it's not one of
the 3 real channels (stable/beta/main) — see
[docs.flutter.dev/release/upgrade](https://docs.flutter.dev/release/upgrade).

## Automated version bumps

`check-flutter-version.yml` runs daily, checks Flutter's official stable
release manifest, and opens a PR bumping `FLUTTER_VERSION` if a new stable
release exists. `pr-check.yml` validates the PR's Dockerfile actually
builds with the new version; `auto-merge.yml` auto-merges once that check
passes — but **only** for PRs labeled `automated-flutter-bump` (i.e. only
ones the bot itself opened, never a human PR).

## Usage

```yaml
image: ghcr.io/dhc-tech/flutter-android-ci:3.47.2
```

or track a channel:

```yaml
image: ghcr.io/dhc-tech/flutter-android-ci:stable
```
