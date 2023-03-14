#!/bin/bash

ELECTRON_VERSION=21.2.0
TARGET=$1
ARCH=$2

ROOT_PATH=$(realpath $(dirname $0)/..)
cd ${ROOT_PATH}

if [[ -z "${MODULE}" ]]; then
  MODULE=$3
fi

if [[ "${MODULE}" == *".sh" ]]; then
  MODULE=${MODULE::-3}
fi

if [ -f ./modules/${MODULE}.sh ]; then
  source ./modules/${MODULE}.sh
else
  if [[ -z "${MODULE}" ]]; then
    echo "Error: No module specified."
  else
    echo "Error: Cannot find '${MODULE}.sh' in './modules'."
  fi
  echo ""
  echo "Usage: ./make.sh win32 x64 \${MODULE}"
  echo "Example: ./make.sh win32 x64 mc_1"
  exit 1
fi

echo "Downloading Electron"
echo "===================="

cd electron

wget -nc "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-${TARGET}-${ARCH}.zip"

echo "Installing Dependencies"
echo "======================="

npm install

echo "Copying"
echo "======="

BUILD_DIR=${COURSE}
PREFIX=build/${BUILD_DIR}

if [ ! -d "../${PREFIX}" ]; then
  echo "Error: No built module found."
  echo "       Use \`package.sh\` in the root directory to create."
  exit
fi

mkdir -p builds/${TARGET}/${ARCH}/${BUILD_DIR}
cd builds/${TARGET}/${ARCH}/${BUILD_DIR}
unzip -u ${ROOT_PATH}/electron/electron-v${ELECTRON_VERSION}-${TARGET}-${ARCH}.zip
mv electron.exe ${COURSE}.exe
mkdir -p resources/app/public/js
cp -r ${ROOT_PATH}/${PREFIX}/* resources/app/.
cp -r ${ROOT_PATH}/electron/node_modules resources/app/.
cp ${ROOT_PATH}/electron/require.js resources/app/.
cp ${ROOT_PATH}/electron/main.js resources/app/.
cp ${ROOT_PATH}/electron/package.json resources/app/.
cd ${ROOT_PATH}

echo ""
echo "Packaging"
echo "========="

cd electron

mkdir -p ${ROOT_PATH}/dist/releases
cd builds/${TARGET}/${ARCH}/${BUILD_DIR}

rm -rf ${ROOT_PATH}/dist/releases/${BUILD_DIR}-${TARGET}-${ARCH}.zip
zip -yr ${ROOT_PATH}/dist/releases/${BUILD_DIR}-${TARGET}-${ARCH}.zip *

echo ""
echo "Done."
echo ""

cd ${ROOT_PATH}
echo "ls dist/releases/${BUILD_DIR}-${TARGET}-${ARCH}.zip -al"
ls dist/releases/${BUILD_DIR}-${TARGET}-${ARCH}.zip -al
