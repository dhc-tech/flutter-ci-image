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

# Matches this project's compileSdk 37 (android/app/build.gradle.kts).
# Build-tools patch version follows Android's own X.0.0-per-platform
# convention; if a given release doesn't exist under this exact version,
# pr-check.yml's real build catches it — never silently falls back.
ENV ANDROID_PLATFORM_VERSION=37
ENV ANDROID_BUILD_TOOLS_VERSION=37.0.0

RUN yes | sdkmanager --licenses \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM_VERSION}" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}"

ARG FLUTTER_REF=stable
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN git clone --depth 1 --branch "${FLUTTER_REF}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && yes | flutter doctor --android-licenses \
    && flutter doctor \
    && flutter precache --android

# Bake in the exact ref this image was built for, so a build using it can
# assert against it the same way bitbucket-pipelines.yml's own version
# check does — a stale/wrong image is a build-time failure, not a silent
# wrong-SDK build.
RUN echo "${FLUTTER_REF}" > /opt/flutter-ref.txt
