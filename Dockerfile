# Self-owned Flutter + Android SDK CI image — built from scratch on plain
# Ubuntu, no third-party Android/Flutter base image. Installs the Android
# command-line tools directly from Google's official distribution, then
# Flutter at the exact ref this image is built for (a version tag like
# "3.47.2", or one of Flutter's 3 real channels: stable/beta/main —
# https://docs.flutter.dev/release/upgrade. "dev" is not a real Flutter
# channel — deprecated, don't build it).
#
# FLUTTER_REF: a git tag (e.g. 3.47.2) or branch name (stable/beta/main).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-21-jdk-headless \
        curl ca-certificates unzip xz-utils git \
        locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# https://developer.android.com/studio#command-line-tools-only — pinned to
# an exact build (15859902) rather than a "latest" URL, so this image is
# reproducible and doesn't silently pick up a new cmdline-tools release.
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV ANDROID_CMDLINE_TOOLS_VERSION=15859902
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -sSLo /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

# No hardcoded platforms;android-<N> or build-tools;<N> here on purpose —
# guessing a specific version number is exactly what broke earlier (37
# doesn't exist as a real published platform). Instead: accept every SDK
# license up front, and let the Android Gradle Plugin's own official
# auto-download mechanism install whatever exact compileSdk/build-tools
# version a given consuming project's build.gradle.kts actually asks for,
# the first time it's built — https://developer.android.com/studio/intro/update#download-with-gradle.
# This image works unmodified for any project's SDK level, current or
# future, without ever needing a version bump here.
RUN yes | sdkmanager --licenses \
    && sdkmanager "platform-tools"

ARG FLUTTER_REF=stable
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN git clone --depth 1 --branch "${FLUTTER_REF}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && yes | flutter doctor --android-licenses \
    && flutter doctor \
    && flutter precache --android

# Extension point for web builds (not installed yet — Android-only image
# for now, per current scope): `flutter precache --web` needs no extra apt
# packages, but `flutter test --platform chrome` would need a `chromium`
# apt package installed above alongside the other apt-get install line.
# Add both here together when web support is actually needed, rather than
# growing this file piecemeal.

# Bake in the exact ref this image was built for, so a build using it can
# assert against it the same way bitbucket-pipelines.yml's own version
# check does — a stale/wrong image is a build-time failure, not a silent
# wrong-SDK build.
RUN echo "${FLUTTER_REF}" > /opt/flutter-ref.txt
