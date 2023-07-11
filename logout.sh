#!/bin/bash

ROOT_PATH=$(realpath $(dirname $0))
source ${ROOT_PATH}/account.sh

echo "Logging out ${USERNAME}..."

# Get the appropriate data
HASHED_EMAIL=($(printf "${USERNAME}" | md5sum))

DOMAIN_TOKEN="studio"
if [[ ! -z ${DOMAIN_PREFIX} ]]; then
    DOMAIN_TOKEN="${DOMAIN_PREFIX}-${DOMAIN_TOKEN}"
fi

rm -f ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-login-cookies.jar
rm -f ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-cookies.jar

echo ""
echo "Done."
