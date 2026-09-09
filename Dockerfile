# Self-owned Flutter CI image — Android + Web + Linux desktop.
#
# Built from scratch on plain Ubuntu, no third-party Android/Flutter base
# image. Installs the Android command-line tools directly from Google's
# official distribution, Chromium for web, the Linux desktop toolchain,
# then Flutter itself at the exact ref this image is built for (a version
# tag like "3.47.2", or one of Flutter's 3 real channels: stable/beta/main
# — https://docs.flutter.dev/release/upgrade. "dev" is not a real Flutter
# channel — deprecated, don't build it).
#
# iOS, macOS, and Windows builds are NOT possible from this image, or any
# Docker/Linux container — they require the real OS + toolchain (Xcode on
# macOS, MSVC on Windows). That's an Apple/Microsoft platform requirement,
# not something this image chooses to omit.
#
# FLUTTER_REF: a git tag (e.g. 3.47.2) or branch name (stable/beta/main).
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-21-jdk-headless \
        curl ca-certificates unzip xz-utils git \
        locales \
        # Web: headless Chromium for `flutter test --platform chrome` /
        # `flutter drive -d web-server` — https://docs.flutter.dev/testing/integration-tests.
        chromium \
        # Linux desktop: https://docs.flutter.dev/platform-integration/linux/building
        clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# https://docs.flutter.dev/testing/integration-tests — Flutter looks for
# this exact env var to drive headless Chrome; the apt package installs
# the binary as `chromium`, not `google-chrome`.
ENV CHROME_EXECUTABLE=/usr/bin/chromium

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
    && flutter config --enable-linux-desktop \
    && flutter doctor -v \
    && flutter precache --android --linux --web

# Bake in the exact ref this image was built for, so a build using it can
# assert against it the same way a consuming pipeline's own version check
# does — a stale/wrong image is a build-time failure, not a silent
# wrong-SDK build.
RUN echo "${FLUTTER_REF}" > /opt/flutter-ref.txt
