#!/bin/bash

ROOT_PATH=$(realpath $(dirname $0))
cd ${ROOT_PATH}

./electron/make.sh win32 x64 "${1}"
