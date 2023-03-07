#!/bin/bash

ROOT_PATH=$(realpath $(dirname $0))
source ${ROOT_PATH}/account.sh

echo "Logging out ${USERNAME}..."

# Get the appropriate data
HASHED_EMAIL=($(printf "${USERNAME}" | md5sum))

rm -f ${ROOT_PATH}/sessions/${HASHED_EMAIL}-login-cookies.jar
rm -f ${ROOT_PATH}/sessions/${HASHED_EMAIL}-session-cookies.jar

echo ""
echo "Done."
