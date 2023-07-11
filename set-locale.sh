#!/bin/bash

# This takes a session cookie and sets its 'language' via the locale action.

ROOT_PATH=$(realpath $(dirname $0))
source ${ROOT_PATH}/account.sh

DOMAIN=https://studio.code.org
if [[ ! -z ${DOMAIN_PREFIX} ]]; then
    DOMAIN=https://${DOMAIN_PREFIX}-studio.code.org
fi

DOMAIN_TOKEN="studio"
if [[ ! -z ${DOMAIN_PREFIX} ]]; then
    DOMAIN_TOKEN="${DOMAIN_PREFIX}-${DOMAIN_TOKEN}"
fi

LOCALE=$1
SESSION=
if [[ ! -z "$2" && "$2" != "--quiet" ]]; then
    HASHED_EMAIL=$2
    SESSION_COOKIE=${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-cookies.jar
    SESSION="--load-cookies ${SESSION_COOKIE}"

    echo "Setting locale for existing session..."
else
    HASHED_EMAIL=guest
    echo "Setting locale for guest session..."
fi

echo "[GET] Getting a page with a locale dropdown using our session"
rm -f sign_in
wget ${SESSION} --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Cache-Control: no-cache" --header "Connection: keep-alive" ${DOMAIN}/users/sign_in 2> /dev/null > /dev/null

# Get authenticity token
TOKEN=`grep -C2 -e "action=[\"][^\"]\+locale[\"]" sign_in | grep -ohe "authenticity_token[\"].\+value\s*=\s*[\"][^\"]\+" | sed -e 's;.*value=";;'`

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

# Remove sign_in
rm -f sign_in

# Generate new session for this locale
RETURN_TO="${DOMAIN}/home"
PAYLOAD=$(printf "authenticity_token="; urlencode ${TOKEN}; printf "&user_return_to="; urlencode ${RETURN_TO}; printf "&locale="; urlencode ${LOCALE})
wget --keep-session-cookies ${SESSION} --save-cookies ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-${LOCALE}-cookies.jar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Referer: ${DOMAIN}/users/sign_in" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Cache-Control: no-cache" --header "Content-Type: application/x-www-form-urlencoded" --header "Connection: keep-alive" ${DOMAIN}/locale --post-data "${PAYLOAD}" 2> /dev/null > /dev/null

# Remove this page
rm -f locale

echo "Successfully set locale: ${ROOT_PATH}/sessions/${HASHED_EMAIL}-${DOMAIN_TOKEN}-session-${LOCALE}-cookies.jar"

if [[ ${2} != "--quiet" && ${3} != "--quiet" ]]; then
echo ""
echo "Done."
fi
