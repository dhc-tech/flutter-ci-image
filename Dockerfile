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
        curl ca-certificates unzip xz-utils git gnupg \
        locales \
        # Linux desktop: https://docs.flutter.dev/platform-integration/linux/building
        clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Web: real Chrome for `flutter test --platform chrome` /
# `flutter drive -d web-server` — https://docs.flutter.dev/testing/integration-tests.
#
# Deliberately NOT `apt-get install chromium` — on Ubuntu 19.10+ (this
# image included) that package is a transitional wrapper that shells out
# to snap at runtime, and snap does not work inside a Docker container:
# the apt install itself succeeds (so this would silently pass a Docker
# build), but the resulting `chromium` binary fails the moment anything
# actually launches it. Installing Google's own .deb repo instead gives a
# real, self-contained binary — no snap involved. See e.g.
# https://www.stablebuild.com/blog/install-chromium-in-an-ubuntu-docker-container.
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/* \
    # Build-time smoke test — proves the binary genuinely runs (not just
    # that `apt install` exited 0), so a regression like the snap-wrapper
    # issue above fails the Docker build immediately instead of surfacing
    # only when a consuming project's own `flutter test --platform
    # chrome` run breaks.
    && google-chrome-stable --headless --disable-gpu --no-sandbox --version

# https://docs.flutter.dev/testing/integration-tests — Flutter looks for
# this exact env var to drive headless Chrome.
ENV CHROME_EXECUTABLE=/usr/bin/google-chrome-stable

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

# cmake for native/NDK builds — not covered by Gradle's own auto-download,
# and Flutter has no official pinned constant for it (unlike compileSdk/
# ndkVersion below), so this is a plain static version.
#
# compileSdk platforms and build-tools are intentionally NOT pinned here —
# build-tools has no Flutter-official version to track (AGP resolves it
# automatically from compileSdk, https://developer.android.com/studio/intro/update#download-with-gradle),
# and compileSdk itself is installed dynamically below, after Flutter is
# cloned, from flutter.compileSdkVersion — same reasoning as ndkVersion.
RUN yes | sdkmanager --licenses \
    && sdkmanager "cmake;3.22.1" \
    # sdkmanager leaves downloaded zips/temp files under the SDK root that
    # aren't needed once a package is unpacked — remove them to keep this
    # layer from carrying dead weight into the final image.
    && rm -rf "${ANDROID_HOME}/.temp" /root/.android/cache

# Firebase CLI (standalone Linux binary), pinned to an exact released
# version rather than /bin/linux/latest — reproducible: a rebuild of this
# same Dockerfile always gets the same CLI, instead of silently picking up
# whatever firebase-tools shipped that day.
# https://github.com/firebase/firebase-tools/releases
ENV FIREBASE_CLI_VERSION=15.30.0
RUN curl -fsSL "https://firebase.tools/bin/linux/v${FIREBASE_CLI_VERSION}" -o /usr/local/bin/firebase \
    && chmod +x /usr/local/bin/firebase \
    && firebase --version

ARG FLUTTER_REF=stable
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN git clone --depth 1 --branch "${FLUTTER_REF}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && yes | flutter doctor --android-licenses \
    && flutter config --enable-linux-desktop \
    && flutter doctor -v \
    && flutter precache --android --linux --web

# compileSdk platform + NDK are both installed dynamically here, read
# straight out of the just-cloned Flutter SDK's own official constants
# (packages/flutter_tools/lib/src/android/gradle_utils.dart) instead of
# hardcoded version numbers — the exact same values android/app/
# build.gradle.kts resolves to via `compileSdk = flutter.compileSdkVersion`
# and `ndkVersion = flutter.ndkVersion`. Bumping FLUTTER_REF to a release
# with different defaults automatically installs the matching platform/NDK
# here too — no separate Dockerfile bump needed when Flutter's own pins
# change.
RUN GRADLE_UTILS="${FLUTTER_HOME}/packages/flutter_tools/lib/src/android/gradle_utils.dart" \
    && COMPILE_SDK=$(grep -oE "compileSdkVersionInt = [0-9]+" "${GRADLE_UTILS}" | grep -oE "[0-9]+") \
    && NDK_VERSION=$(grep -oE "ndkVersion = '[0-9.]+'" "${GRADLE_UTILS}" | grep -oE "[0-9.]+") \
    && test -n "${COMPILE_SDK}" && test -n "${NDK_VERSION}" \
    && echo "Installing Flutter's official compileSdk: android-${COMPILE_SDK}, NDK: ${NDK_VERSION}" \
    && sdkmanager "platforms;android-${COMPILE_SDK}" "ndk;${NDK_VERSION}" \
    && echo "${COMPILE_SDK}" > /opt/flutter-compilesdk-version.txt \
    && echo "${NDK_VERSION}" > /opt/flutter-ndk-version.txt

# Bake in the exact ref this image was built for, so a build using it can
# assert against it the same way a consuming pipeline's own version check
# does — a stale/wrong image is a build-time failure, not a silent
# wrong-SDK build.
RUN echo "${FLUTTER_REF}" > /opt/flutter-ref.txt
