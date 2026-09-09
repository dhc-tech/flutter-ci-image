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

Published to `ghcr.io/dhc-tech/flutter-ci` (public — pull it with no
registry credentials):

| Tag | What it is | Pick this if you want... | Rebuilds |
|---|---|---|---|
| `stable` / `latest` | Flutter's official **stable** channel — the tip of flutter/flutter's `stable` branch. Recommended by Flutter itself for new users and production releases; updated from `beta` roughly every 3 months, with occasional hot fixes for high-severity issues | The version most people should build against day to day | Within ~5 min of a new commit landing on that branch (GitHub Actions' own minimum schedule granularity) |
| `beta` | Flutter's **beta** channel — the tip of flutter/flutter's `beta` branch. Per Flutter's own docs, "essentially the same as the stable channel but updated monthly instead of quarterly" — when `stable` updates, it updates *to* the latest `beta`, so this is genuinely a preview of what `stable` becomes next, not a separate experimental line | Slightly newer fixes/features than `stable`, heavily tested but not yet promoted | Once daily |
| `main` | Flutter's **main** channel (used to be called `master`) — the tip of flutter/flutter's `main` branch, where Flutter's own contributors work. Flutter's own docs explicitly recommend against using it: "not as thoroughly tested... more likely to contain serious regressions" | Testing against the absolute latest, unreleased Flutter source | Once daily |
| `<version>` (e.g. `3.47.2`) / `pinned` | The exact version number of the current stable release, immutable — never silently changes under you | Reproducible builds: the same tag always means the same Flutter build, unlike `stable` which moves forward over time | Automatically, the moment flutter/flutter's `stable` branch is tagged with a new version — see below |

In short: `stable` tracks whatever Flutter currently calls its stable
release (moves over time, ~quarterly); `<version>`/`pinned` freezes that
same release at one exact number (never moves); `beta` is what `stable`
will become next (~monthly); `main` is Flutter's own bleeding-edge
contributor branch, explicitly not recommended by Flutter for general use.
See [docs.flutter.dev/release/upgrade](https://docs.flutter.dev/release/upgrade)
for Flutter's own explanation of these channels.

`dev` is intentionally not built — Flutter deprecated it, it is not one of
the 3 real channels (stable/beta/main) — see
[docs.flutter.dev/release/upgrade](https://docs.flutter.dev/release/upgrade).

## How versions are resolved

Nothing in this repo hardcodes "the current Flutter version" as a
judgment call — every tag traces back to flutter/flutter's own repository
state, checked automatically and often:

- **`stable` tag** — `build-and-push.yml`'s `build-stable` job runs every
  5 minutes (GitHub Actions' own minimum schedule granularity). Each run
  asks the GitHub API for the current HEAD commit SHA of `flutter/
  flutter`'s `stable` branch, compares it against the SHA this image last
  actually built (a `LAST_BUILT_SHA_STABLE` GitHub Actions repository
  variable — not a committed file, since branch protection blocks a
  plain `git push` to `main` even from the workflow's own token;
  variables need no push), and only rebuilds — and only updates that
  recorded SHA — if the branch has genuinely moved. An unchanged branch
  is a fast no-op, not a wasted rebuild.
- **`beta`/`main` tags** — `build-daily-channels` job, same
  changed-SHA check, but on a once-daily cron instead of every 5 minutes.
- **`<version>`/`pinned` tag** — `check-flutter-version.yml` runs every
  5 minutes. It asks the GitHub API which commit `flutter/flutter`'s
  `stable` branch currently points at, then which tag (if any) points at
  that exact same commit — that tag name *is* the real, official version
  number Flutter itself assigned to that release, straight from
  `github.com/flutter/flutter`, not a third-party manifest or a guess. If
  that differs from the version recorded in `FLUTTER_VERSION`, it opens a
  PR bumping the file.

## Fully automated release flow

Two trusted bots can open a PR here — neither a human PR is ever
auto-merged, even if it happens to touch the same files:

- **`check-flutter-version.yml`** — detects flutter/flutter tagged a new
  stable release and opens a PR (labeled `automated-flutter-bump`)
  bumping `FLUTTER_VERSION`.
- **Dependabot** (`.github/dependabot.yml`) — opens its own PRs bumping
  GitHub Actions versions used in the workflows, and the `ubuntu:24.04`
  base image in the Dockerfile.

For either:

1. `pr-check.yml` builds the Dockerfile against the change (no push) to
   confirm it actually builds before anything merges — for a
   workflow-only Dependabot PR that can't affect the image, it skips the
   actual build and passes immediately instead.
2. `auto-merge.yml` — checks the PR's live author/label (not the
   `opened` event's payload, which isn't reliably populated with a label
   set at PR-creation time) — enables GitHub's native auto-merge, which
   completes the merge the moment `pr-check.yml` passes. Runs on
   `pull_request_target` specifically because Dependabot PRs always get a
   hard-restricted, read-only token on plain `pull_request` regardless of
   repository settings. No manual click required end to end.
3. Merging a `FLUTTER_VERSION` bump to `main` triggers
   `build-and-push.yml`'s `build-pinned` job, publishing the new
   `<version>`/`pinned` tags.

This entire chain was verified with a real test run, not just designed on
paper: a manually-lowered `FLUTTER_VERSION` was detected, a real PR was
opened, built, and auto-merged with zero manual steps once the one-time
repo settings below were in place.

### One-time repo setup this flow depends on

Already configured on this repo — noted here in case it's ever recreated:

- **Settings → Actions → General → Workflow permissions**: "Read and
  write permissions" + "Allow GitHub Actions to create and approve pull
  requests" — without this, `gh pr create` fails with *"GitHub Actions is
  not permitted to create or approve pull requests."*
- **Settings → General → Pull Requests → "Allow auto-merge"** — without
  this, `gh pr merge --auto` has nothing to enable.
- **Branch protection on `main`**: required status check `build-check`
  (from `pr-check.yml`), strict (branch must be up to date) — this is
  also what makes `git push origin main` fail for anything but a proper
  PR merge, which is why build state is tracked via repository variables
  instead of a committed file (see above).
- A label named `automated-flutter-bump` must exist on the repo (`gh
  label create`) before `check-flutter-version.yml` can apply it.

## Usage

```yaml
image: ghcr.io/dhc-tech/flutter-ci:3.47.2
```

or track a channel (rebuilds within ~5 min of `stable`/`beta` moving,
~daily for `main` — see above):

```yaml
image: ghcr.io/dhc-tech/flutter-ci:stable
```

### Checking exactly what Flutter version a tag contains

Every image — including the mutable `stable`/`beta`/`main` tags, which
don't carry a version in their own name — carries an
`org.opencontainers.image.version` label recording the exact commit it
was built from, so you never have to guess:

```bash
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' ghcr.io/dhc-tech/flutter-ci:stable
```

or without pulling the image, via the GHCR API:

```bash
docker manifest inspect ghcr.io/dhc-tech/flutter-ci:stable
```

## Repo layout

- `Dockerfile` — the image itself. `FLUTTER_REF` build arg selects the
  git ref (a version tag or a channel branch name) to install.
- `FLUTTER_VERSION` — single source of truth for the `pinned` tag's
  version; only ever changed by `check-flutter-version.yml`'s bot PRs.
- `LAST_BUILT_SHA_<CHANNEL>` repository variables (Settings → Secrets and
  variables → Actions → Variables) — last-built commit SHA per channel,
  used to skip no-op rebuilds; only ever changed by `build-and-push.yml`
  itself.
- `.github/dependabot.yml` — keeps Actions versions and the base image
  current.
- `.github/workflows/` — the four workflows described above.
