# flutter-ci-image

A self-owned Flutter CI Docker image — built from scratch on plain
`ubuntu:24.04`, no third-party Android/Flutter base image. Installs the
Android SDK command-line tools, Chromium, and the Linux desktop toolchain
directly from their official sources, then Flutter itself. Every version
this image ever ships is resolved **dynamically from
[github.com/flutter/flutter](https://github.com/flutter/flutter)
directly** — nothing here is a hand-picked or hardcoded Flutter version;
see [How versions are resolved](#how-versions-are-resolved) below.

Builds **Android, Web, and Linux desktop**. Does **not** and cannot build
iOS, macOS, or Windows — those need the real OS + toolchain (Xcode on
macOS, MSVC on Windows). That's an Apple/Microsoft platform requirement,
not something this image chooses to omit, and no Docker/Linux container
anywhere can do it.

## Tags

Published to `ghcr.io/dhc-tech/flutter-ci`:

| Tag | What it is | Rebuilds |
|---|---|---|
| `<version>` (e.g. `3.47.2`) / `pinned` | Exact Flutter release, immutable | Automatically, the moment flutter/flutter's `stable` branch is tagged with a new version — see below |
| `stable` / `latest` | Flutter's `stable` channel, tip-of-branch | Within ~15 min of a new commit landing on that branch |
| `beta` | Flutter's `beta` channel, tip-of-branch | Within ~15 min of a new commit landing on that branch |
| `main` | Flutter's `main` channel (contributor/bleeding-edge — this channel used to be called `master`) | Within ~15 min of a new commit landing on that branch |

`dev` is intentionally not built — Flutter deprecated it, it is not one of
the 3 real channels (stable/beta/main) — see
[docs.flutter.dev/release/upgrade](https://docs.flutter.dev/release/upgrade).

## How versions are resolved

Nothing in this repo hardcodes "the current Flutter version" as a
judgment call — every tag traces back to flutter/flutter's own repository
state, checked automatically and often:

- **`stable`/`beta`/`main` tags** — `build-and-push.yml` runs every 15
  minutes. Each run asks the GitHub API for the current HEAD commit SHA of
  that channel's branch in `flutter/flutter`, compares it against the SHA
  this image last actually built (recorded in `channel-shas/<channel>.sha`
  in this repo), and only rebuilds — and only updates that recorded SHA —
  if the branch has genuinely moved. An unchanged channel is a fast no-op,
  not a wasted rebuild.
- **`<version>`/`pinned` tag** — `check-flutter-version.yml` also runs
  every 15 minutes. It asks the GitHub API which commit `flutter/flutter`'s
  `stable` branch currently points at, then which tag (if any) points at
  that exact same commit — that tag name *is* the real, official version
  number Flutter itself assigned to that release, straight from
  `github.com/flutter/flutter`, not a third-party manifest or a guess. If
  that differs from the version recorded in `FLUTTER_VERSION`, it opens a
  PR bumping the file.

## Fully automated release flow

1. `check-flutter-version.yml` detects flutter/flutter tagged a new stable
   release and opens a PR (labeled `automated-flutter-bump`) bumping
   `FLUTTER_VERSION`.
2. `pr-check.yml` builds the Dockerfile against the new version (no push)
   to confirm it actually builds before anything merges.
3. `auto-merge.yml` — restricted to PRs carrying that exact label, i.e.
   only ones the bot itself opened, never a human PR — enables GitHub's
   native auto-merge, which completes the merge the moment `pr-check.yml`
   passes. No manual click required end to end.
4. Merging to `main` triggers `build-and-push.yml`'s `build-pinned` job,
   which builds and publishes the new `<version>`/`pinned` tags.

## Usage

```yaml
image: ghcr.io/dhc-tech/flutter-ci:3.47.2
```

or track a channel (rebuilds within ~15 min of upstream moving, see above):

```yaml
image: ghcr.io/dhc-tech/flutter-ci:stable
```

## Repo layout

- `Dockerfile` — the image itself. `FLUTTER_REF` build arg selects the
  git ref (a version tag or a channel branch name) to install.
- `FLUTTER_VERSION` — single source of truth for the `pinned` tag's
  version; only ever changed by `check-flutter-version.yml`'s bot PRs.
- `channel-shas/*.sha` — last-built commit SHA per channel, used to skip
  no-op rebuilds; only ever changed by `build-and-push.yml` itself.
- `.github/workflows/` — the four workflows described above.
