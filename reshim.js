#!/bin/bash

# This is generally best run against a development server that is using the
# minimized JS assets. Therefore, locals.yml has:
#
#   optimize_webpack_assets: true
#   use_my_apps: true
#
# These above settings set. And then running yarn build:dist in `apps`

echo "Starting crawler..."

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
  echo "Usage: ./package.sh \${MODULE}"
  echo "Example: ./package.sh mc_1"
  exit 1
fi

PREFIX=build/${COURSE}_${LESSON}

# Add shims

echo ""
echo "Adding JS/CSS shims..."

DEST="assets/application.js js/jquery.min.js assets/js/webpack*.js assets/js/vendor*.js assets/js/essential*.js assets/js/common*.js assets/js/code-studio-*.js"

for js in ${DEST}
do
  path=`echo ${PREFIX}/${js} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] shim.js -> ${path}"
    cat shim.js ${PREFIX}/${js} > ${PREFIX}/${js}.new
    mv ${PREFIX}/${js}.new ${PREFIX}/${js}
  fi
done
