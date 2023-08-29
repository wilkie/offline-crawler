#!/bin/bash

ROOT_PATH=$(realpath $(dirname $0))

if [[ ! -f ${ROOT_PATH}/account.sh ]]; then
    echo "Account information not found in \`account.sh\`"
    echo ""
    echo "Write a file called \`account.sh\` in the root of this repo."
    echo "In it define USERNAME and PASSWORD variables."
    echo "Use \`example.account.sh\` as a guide."
    exit 1
fi

source ${ROOT_PATH}/account.sh
exit

# Get the appropriate data
export HASHED_EMAIL=($(printf "${USERNAME}" | md5sum))
echo "Logging in as ${USERNAME} [${HASHED_EMAIL}]..."

mkdir -p ${ROOT_PATH}/sessions

# Log us out
${ROOT_PATH}/logout.sh 2> /dev/null > /dev/null

DOMAIN=https://studio.code.org
if [[ ! -z ${DOMAIN_PREFIX} ]]; then
    DOMAIN=https://${DOMAIN_PREFIX}-studio.code.org
fi

DOMAIN_TOKEN="studio"
if [[ ! -z ${DOMAIN_PREFIX} ]]; then
    DOMAIN_TOKEN="${DOMAIN_PREFIX}-${DOMAIN_TOKEN}"
fi

# Generates a user session
echo "[GET] Getting a session (login-cookies.jar)"
rm -f sign_in
wget --keep-session-cookies --save-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-login-cookies.jar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Cache-Control: no-cache" --header "Connection: keep-alive" ${DOMAIN}/users/sign_in 2> /dev/null > /dev/null

# Read the csrf token
TOKEN=`grep sign_in -C0 -e csrf-token | grep -ohe "content\s*=\s*\"[^\"]\+" | sed -e 's;content\s*=\s*";;'`

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}

# Fulfill the user login form
PAYLOAD=$(printf "authenticity_token="; urlencode ${TOKEN}; printf "&user[hashed_email]="; urlencode ${HASHED_EMAIL}; printf "&user[login]=&user[password]="; urlencode ${PASSWORD})

rm -f sign_in
wget --keep-session-cookies --load-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-login-cookies.jar --save-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-cookies.jar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Referer: ${DOMAIN}/users/sign_in" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Cache-Control: no-cache" --header "Content-Type: application/x-www-form-urlencoded" --header "Connection: keep-alive" ${DOMAIN}/users/sign_in --post-data "${PAYLOAD}" 2> /dev/null > /dev/null
rm -f sign_in

# Sign the cookies, if you WANT to (allows access to certain buckets)
#wget --keep-session-cookies --load-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-cookies.jar --save-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-signed-cookies.jar https://studio.code.org/dashboardapi/sign_cookies -O ${PREFIX}/dashboardapi/sign_cookies 2> /dev/null > /dev/null

echo "Successfully logged in: ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-cookies.jar"

if [[ -z ${1} ]]; then
  echo ""
  echo "Done."
fi
