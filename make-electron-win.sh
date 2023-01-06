#!/bin/bash

ELECTRON_VERSION=21.2.0

ROOT_PATH=$(realpath $(dirname $0))
cd ${ROOT_PATH}

if [[ -z "${MODULE}" ]]; then
  MODULE=$1
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
  echo "Usage: ./build-win.sh \${MODULE}"
  echo "Example: ./build-win.sh mc_1"
  exit 1
fi

echo "Downloading Electron"
echo "===================="

mkdir -p electron
cd electron

wget -nc "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-win32-x64.zip"

echo "Installing Dependencies"
echo "======================="

npm install

echo "Copying"
echo "======="

PREFIX=build/${COURSE}_${LESSON}

if [ ! -d "../${PREFIX}" ]; then
  echo "Error: No built module found."
  echo "       Use \`package.sh\` in the root directory to create."
  exit
fi

mkdir -p builds/windows/${COURSE}_${LESSON}
cd builds/windows/${COURSE}_${LESSON}
unzip -u ../../../electron*win32-x64.zip
mv electron.exe ${COURSE}_${LESSON}.exe
mkdir -p resources/app/public/js
cp -r ../../../../${PREFIX}/* resources/app/.
cp -r ../../../node_modules resources/app/.
cp ../../../require.js resources/app/.
cp ../../../main.js resources/app/.
cp ../../../package.json resources/app/.
cd ../../..

echo ""
echo "Packaging"
echo "========="

mkdir -p ../dist/releases
cd builds/windows/${COURSE}_${LESSON}

rm -rf ../../../../dist/releases/${COURSE}_${LESSON}-win32-x64.zip
zip -yr ../../../../dist/releases/${COURSE}_${LESSON}-win32-x64.zip *
