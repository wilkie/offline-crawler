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

if [[ ${ARCH} == "arm64" ]]; then
  JQ_LIB_URL=http://mirror.archlinuxarm.org/aarch64/community/oniguruma-6.9.8-1-aarch64.pkg.tar.xz
  JQ_BINARY_URL=http://mirror.archlinuxarm.org/aarch64/community/jq-1.6-4-aarch64.pkg.tar.xz
else
  JQ_LIB_URL=
  JQ_BINARY_URL=https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
fi
