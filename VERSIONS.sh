#!/bin/bash

# This contains versions for third-party things we need in order to run the
# crawler or any associated tooling.

# The place for finding youtube-dl binary
YOUTUBE_DL_VERSION=2023.03.14.334
YOUTUBE_DL_RELEASE_URL="https://github.com/ytdl-patched/youtube-dl/releases/download/${YOUTUBE_DL_VERSION}/youtube-dl"

ARCH=`uname -m`
if [[ ${ARCH} == "aarch64" ]]; then
  ARCH='arm64'
else
  ARCH='amd64'
fi

FFMPEG_RELEASE_URL=https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${ARCH}-static.tar.xz
