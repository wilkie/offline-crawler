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

# Gather the version and URLs for third-party tools
source ${ROOT_PATH}/VERSIONS.sh

# If LESSON is specified into this script, we are creating a lesson module from
# a whole course
if [[ ! -z "${LESSON}" ]]; then
  PARTIAL=${LESSON}
fi

# Negotiate the module requested
if [ -f ${ROOT_PATH}/modules/${MODULE}.sh ]; then
  source ${ROOT_PATH}/modules/${MODULE}.sh
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

# This depicts a base path, for cases that exist like this
# For instance, studio.code.org/projectbeats
if [[ "${LESSON}" == "0" ]]; then
  if [[ -z "${RELATIVE_PATH}" ]]; then
    RELATIVE_PATH=.
  fi
else
  if [[ -z "${RELATIVE_PATH}" ]]; then
    RELATIVE_PATH=../../../../..
  fi
fi

if [[ ! -z "${WARN}" ]]; then
  if [[ -z "${DO_ANYWAY}" ]]; then
    echo "Error: This module is currently not working for offline. (WARN=1)"
    echo "       To produce anyway, set the environment variable DO_ANYWAY"
    echo "Usage: DO_ANYWAY=1 ./package.sh \${MODULE}"
    exit 1
  fi
fi

# Where the code-dot-org repo is (for copying static assets more quickly)
if [[ -z "${CODE_DOT_ORG_REPO_PATH}" ]]; then
  CODE_DOT_ORG_REPO_PATH=${ROOT_PATH}/../code-dot-org
fi

# Determine if that path exists.
if [ ! -d ${CODE_DOT_ORG_REPO_PATH} ]; then
  echo "Error: Cannot find the 'code-dot-org' repo in \${CODE_DOT_ORG_REPO_PATH} as ${CODE_DOT_ORG_REPO_PATH}."
  exit 1
else
  echo "Using assets found locally in $(realpath ${CODE_DOT_ORG_REPO_PATH})."
fi

# Determine the URLs that we will crawl. If USE_REMOTE is set, it crawls the
# production site instead of a development instance.
if [[ -z "${VIDEO_MAX_SIZE}" ]]; then
  VIDEO_MAX_SIZE=80000000
fi
echo "Using video max size: ${VIDEO_MAX_SIZE} bytes"

if [[ -z "${USE_REMOTE}" ]]; then
    USE_REMOTE=1
fi

if [[ "${USE_REMOTE}" != "0" ]]; then
  if [[ -z "${DOMAIN_PREFIX}" ]]; then
    STUDIO_DOMAIN=https://studio.code.org
    MAIN_DOMAIN=https://code.org
    DOMAINS=studio.code.org,code.org,images.code.org
  else
    STUDIO_DOMAIN=https://${DOMAIN_PREFIX}-studio.code.org
    MAIN_DOMAIN=https://${DOMAIN_PREFIX}.code.org
    DOMAINS=${DOMAIN_PREFIX}-studio.code.org,${DOMAIN_PREFIX}.code.org,images.code.org,${DOMAIN_PREFIX}-images.code.org
  fi
  EXCLUDE_DOMAINS=curriculum.code.org,videos.code.org
  BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:6}
  BASE_MAIN_DOMAIN=${MAIN_DOMAIN:6}
else
  if [[ -z "${DOMAIN_PREFIX}" ]]; then
    DOMAIN_PREFIX="localhost"
  fi

  if [[ -z "${PORT}" ]]; then
    PORT="3000"
  fi

  if [[ "${PORT}" != "80" ]]; then
    STUDIO_DOMAIN=http://${DOMAIN_PREFIX}-studio.code.org:${PORT}
    MAIN_DOMAIN=http://${DOMAIN_PREFIX}.code.org:${PORT}
  else
    STUDIO_DOMAIN=http://${DOMAIN_PREFIX}-studio.code.org
    MAIN_DOMAIN=http://${DOMAIN_PREFIX}.code.org
  fi
  DOMAINS=${DOMAIN_PREFIX}-studio.code.org,${DOMAIN_PREFIX}.code.org
  EXCLUDE_DOMAINS=curriculum.code.org,studio.code.org,videos.code.org
  BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:5}
  BASE_MAIN_DOMAIN=${MAIN_DOMAIN:5}
fi

# These are content domains. They must be our production sites since the
# crawler will not be able to access the AWS buckets themselves.
CURRICULUM_DOMAIN=https://curriculum.code.org
VIDEO_DOMAIN=http://videos.code.org
IMAGE_DOMAIN=http://images.code.org
VIDEO_SSL_DOMAIN=https://videos.code.org
IMAGE_SSL_DOMAIN=https://images.code.org
DSCO_DOMAIN=https://dsco.code.org
TTS_DOMAIN=https://tts.code.org
LESSON_PLAN_DOMAIN=https://lesson-plans.code.org

# Some links are in the form `//localhost-studio.code.org:3000`, etc
BASE_CURRICULUM_DOMAIN=${CURRICULUM_DOMAIN:6}
BASE_VIDEO_DOMAIN=${VIDEO_DOMAIN:5}
BASE_IMAGE_DOMAIN=${IMAGE_DOMAIN:5}
BASE_TTS_DOMAIN=${TTS_DOMAIN:6}
BASE_DSCO_DOMAIN=${DSCO_DOMAIN:6}

# Create the build path. This contains the crawled pages.
mkdir -p build

# The build directory will have a `tmp` path which contains the pages
# 'in-flight' before they are placed in locale-specific places.
BUILD_DIR=${COURSE}

# If we are building just one lesson of the course module, augment the build dir
if [[ ! -z ${PARTIAL} ]]; then
  BUILD_DIR=${BUILD_DIR}-${LESSON}
fi

# PREFIX_ROOT is always the root path of our module
PREFIX_ROOT=build/${BUILD_DIR}
# PREFIX points to the current place we are messing with things
# We eventually copy the finished things to the PREFIX_ROOT
# Some static content generally wants to just go into PREFIX_ROOT directly
PREFIX=build/${BUILD_DIR}/tmp

# The shared directory for common assets
SHARED=shared

# Remove old path (maybe)
if [ -d ${PREFIX} ]; then
  rm -r ${PREFIX}
fi

# Create that build path (./build/<course>/tmp)
mkdir -p ${PREFIX}
touch ${PREFIX}/wget_log.txt

# This the reject regex that disallows certain content from being downloaded
REJECT_REGEX="[.]dmg$|[.]exe$|[.]mp4$|robots.txt$"

# This is the argument to wget to use a logged in user session. We use the
# 'login.sh' script to create a user session, if required. Otherwise, we just
# use a session-less connection.
#
# When the session exists, the flag to wget is augmented to use those cookies
# such that this user is requesting the pages and performing the crawl.
SESSION=
HASHED_EMAIL=
if [[ ! -z "${LOGIN}" ]]; then
  echo ""
  ${ROOT_PATH}/login.sh --quiet | tee ${ROOT_PATH}/${PREFIX}/login-log.txt
  echo ""
  SESSION_COOKIE=`cat ${ROOT_PATH}/${PREFIX}/login-log.txt | grep -C0 -e "Successfully logged in: " | sed -e "s;Successfully logged in: ;;"`

  # Get the hashed email for the logged in user
  HASHED_EMAIL=$(basename ${SESSION_COOKIE})
  HASHED_EMAIL=${HASHED_EMAIL%-*}
  HASHED_EMAIL=${HASHED_EMAIL%-*}
  HASHED_EMAIL=${HASHED_EMAIL%-*}
  HASHED_EMAIL=${HASHED_EMAIL%-*}

  SESSION="--load-cookies ${SESSION_COOKIE}"
fi

# The 'LOCALE' variable specifically crawls just one locale. So, it
# overrides the locale list.
if [[ ! -z "${LOCALE}" ]]; then
  LOCALE=${LOCALE//_/-}
  LOCALES=${LOCALE}
fi

# The 'LOCALES' variable can be a space-delimited list of locale codes to crawl
# and aggregate in the module. If not given, they will be determined later on
# when a page is crawled. By default, they will be ALL supported locales listed
# in the site's locale dropdown. This behavior is overwritten by specifying that
# LOCALES variable before performing the script.
if [[ ! -z "${LOCALES}" ]]; then
  # Ensure that LOCALES is treated as an array and get the 'initial' locale as
  # the first item in that list.
  LOCALES=(${LOCALES})
  STARTING_LOCALE=${LOCALES[0]}
fi

# This function invokes wget to download a set of URLs.
#
# Invoke as:
#   download "<wget options>" "<URL>" "<log file>"
#
# The log file will be appended with the full wget output.
#
# The output is filtered to make it clearer to read while the crawler is in
# motion. It will show you the URL being downloaded and also note when wget
# is rewriting links.
download() {
  echo wget ${SESSION} --directory-prefix ${PREFIX} ${1} ${2} >> ${3}
  wget ${SESSION} --directory-prefix ${PREFIX} ${1} ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4
}

ensure_jq() {
  if [ ! -e ${ROOT_PATH}/bin/jq ]; then
    mkdir -p ${ROOT_PATH}/bin
    echo "[GET] 'jq'"
    wget ${JQ_BINARY_URL} -O ${ROOT_PATH}/${SHARED}/jq/jq.tar.xz -nc
    mkdir -p ${ROOT_PATH}/${SHARED}/jq
    cd ${ROOT_PATH}/${SHARED}/jq
    tar xf jq.tar.xz
    mv usr/bin/* ${ROOT_PATH}/bin/.
    cd ${ROOT_PATH}
  fi
  if [[ ! -z "${JQ_LIB_URL}" ]]; then
    if [ ! -L ${ROOT_PATH}/lib/libonig.so ]; then
      mkdir -p ${ROOT_PATH}/lib
      echo "[GET] 'liboniguruma' (for jq)"
      wget ${JQ_LIB_URL} -O ${ROOT_PATH}/${SHARED}/jq/oniguruma.tar.xz -nc
      mkdir -p ${ROOT_PATH}/${SHARED}/jq
      cd ${ROOT_PATH}/${SHARED}/jq
      tar xf oniguruma.tar.xz
      mv usr/lib/* ${ROOT_PATH}/lib/.
      cd ${ROOT_PATH}
    fi
  fi
}

jq() {
  LD_LIBRARY_PATH=${ROOT_PATH}/lib ${ROOT_PATH}/bin/jq "$@"
}

ensure_ffmpeg() {
  mkdir -p ${ROOT_PATH}/bin
  if [ ! -e ${ROOT_PATH}/bin/ffmpeg ]; then
    echo "[GET] 'ffmpeg'"
    wget ${FFMPEG_RELEASE_URL} -O ${ROOT_PATH}/${SHARED}/ffmpeg.tar.xz -nc
    cd ${ROOT_PATH}/shared
    tar xf ffmpeg.tar.xz
    mv ffmpeg-*-static/* ${ROOT_PATH}/bin/.
    cd ${ROOT_PATH}
  fi
}

# Specifically for downloading video content
#
# Invoke as:
#   download_video "<download path>" "<URL>" "<log file>"
#   echo "${video_path}"
#
# Example:
#   download_video "foo/bar.mp4" "https://videos.code.org/foo/bar.mp4" "${PREFIX}/wget-videos.log"
#   # We expect '${video_path}' to be something like:
#   # "${ROOT_PATH}/videos/foo/bar.mp4
#   # If the video had to be made smaller, we expect to see something like:
#   # "${ROOT_PATH}/videos/smaller/foo/bar.mp4
download_video() {
  # Analyze the video
  # If it is too big, we downsize it via ffmpeg
  dir=$(dirname "${1}")
  filename=$(basename "${1}")

  # Replace any '?', '%', or '=' with '-'
  filename=$(urldecode ${filename})

  video_path=${ROOT_PATH}/videos/${dir}/${filename}
  wget ${SESSION} --directory-prefix ${PREFIX} -O ${video_path} -nc --tries=2 ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4

  size=$(stat -c %s "${video_path}")

  if (( "${size}" >= "${VIDEO_MAX_SIZE}" )); then
    echo "[WARN] Video too big for our purposes (${size} bytes). Attempting downsize."

    # Ensure we have the ffmpeg program
    ensure_ffmpeg

    # Use ffmpeg to generate a smaller video
    video_path=${ROOT_PATH}/videos/smaller/${dir}/${filename}
    mkdir -p ${ROOT_PATH}/videos/smaller/${dir}
    if [ ! -e ${ROOT_PATH}/videos/smaller/${dir}/${filename} ]; then
      # Create a downsized video
      echo "[CREATE] \`smaller/${dir}/${filename}\`"
      ${ROOT_PATH}/bin/ffmpeg -i ${ROOT_PATH}/videos/${dir}/${filename} -filter:v scale=1280:720 -c:a copy ${ROOT_PATH}/videos/smaller/${dir}/${filename}
    else
      echo "[EXISTS] \`smaller/${dir}/${filename}\`"
    fi
  fi

  # Make it EVEN SMALLER maybe
  size=$(stat -c %s "${video_path}")

  if (( "${size}" >= "${VIDEO_MAX_SIZE}" )); then
    echo "[WARN] Video still too big for our purposes (${size} bytes). Attempting downsize."
    cd ${ROOT_PATH}

    # Use ffmpeg to generate an even smaller video
    video_path=${ROOT_PATH}/videos/smallest/${dir}/${filename}
    mkdir -p ${ROOT_PATH}/videos/smallest/${dir}
    if [ ! -e ${ROOT_PATH}/videos/smallest/${dir}/${filename} ]; then
      # Create a downsized video
      echo "[CREATE] \`smallest/${dir}/${filename}\`"
      ${ROOT_PATH}/bin/ffmpeg -i ${ROOT_PATH}/videos/${dir}/${filename} -filter:v scale=854:480 -c:a copy ${ROOT_PATH}/videos/smallest/${dir}/${filename}
    else
      echo "[EXISTS] \`smallest/${dir}/${filename}\`"
    fi
  fi

  # Make it EVEN EVEN SMALLER maybe
  size=$(stat -c %s "${video_path}")

  if (( "${size}" >= "${VIDEO_MAX_SIZE}" )); then
    echo "[WARN] Video still too big for our purposes (${size} bytes). Attempting downsize."
    cd ${ROOT_PATH}

    # Use ffmpeg to generate an even smaller video
    video_path=${ROOT_PATH}/videos/smallestest/${dir}/${filename}
    mkdir -p ${ROOT_PATH}/videos/smallestest/${dir}
    if [ ! -e ${ROOT_PATH}/videos/smallestest/${dir}/${filename} ]; then
      # Create a downsized video
      echo "[CREATE] \`smallestest/${dir}/${filename}\`"
      ${ROOT_PATH}/bin/ffmpeg -i ${ROOT_PATH}/videos/${dir}/${filename} -filter:v scale=640:360 -c:a copy ${ROOT_PATH}/videos/smallestest/${dir}/${filename}
    else
      echo "[EXISTS] \`smallestest/${dir}/${filename}\`"
    fi
  fi
}

# This function downloads a set of URLs assuming they are shared resources.
# These resources will not be downloaded again by any other module if already
# found in the `/shared/` path.
#
# The resource is downloaded to that `shared` path if needed. Then, it is copied
# to the `build` path from the `shared` path if it doesn't exist there already.
#
# Invoke as (same as normal 'download'):
#   download_shared "<wget options>" "<URL>" "<log file>"
#
# See `download()` above for information about the logging process.
download_shared() {
  relative=`echo "${2}" | sed -E 's/^\s*.*:\/\/[^/]+\/[/]?//g'`
  dir=$(dirname "${relative}")
  filename=$(basename "${relative}")

  # Decode spaces
  filename=${filename//\%20/ }

  # Replace any '?', '%', or '=' with '-'
  filename=${filename//\?/-}
  filename=${filename//\=/-}
  filename=${filename//\%/-}

  mkdir -p "${SHARED}/${dir}"
  mkdir -p "${PREFIX}/${dir}"

  wget ${SESSION} --directory-prefix ${SHARED} -nc -O "${SHARED}/${dir}/${filename}" ${1} ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4

  if [ ! -e "${PREFIX}/${dir}/${filename}" ]; then
    cp "${SHARED}/${dir}/${filename}" "${PREFIX}/${dir}/${filename}"
  fi
}

# This function downloads a youtube link as an mp4 using a third-party program.
# The 'video_path' variable contains the path to the downloaded video.
# The 'video_id' variable contains the youtube id for this video.
# The 'video_url' variable would be the url for the video relative to the root
# page.
#
# Invoke as:
#   download_youtube "<youtube url>"
#   echo "${video_id}: ${video_path} -> ${video_url}"
#
# Example:
#   download_youtube "https://www.youtube.com/watch?v=Vlj1_X474to"
#   # We expect '${video_path}' to be something like:
#   # "blah/videos/youtube/Debugging_Global_vs._Local_Variables-Vlj1_X474to.mp4"
download_youtube() {
  url=${1}

  echo "[YTDL] Getting youtube video: ${url} ..."

  # Ensure we have the youtube-dl program
  mkdir -p ${ROOT_PATH}/bin
  if [ ! -e ${ROOT_PATH}/bin/youtube-dl ]; then
    echo "[GET] 'youtube-dl'"
    wget ${YOUTUBE_DL_RELEASE_URL} -O ${ROOT_PATH}/bin/youtube-dl 2> /dev/null > /dev/null
    chmod a+rx ${ROOT_PATH}/bin/youtube-dl
  fi

  # Ensure there is a 'youtube' video path
  mkdir -p ${ROOT_PATH}/videos/youtube

  # Do a quick check for the presence of the video file, first
  video_id=${url##*=}
  video_path=`ls ${ROOT_PATH}/videos/youtube/*${video_id}.mp4 2> /dev/null`
  if [ ! -e "${video_path}" ]; then
    # Invoke youtube-dl on the given URL and store the filename of the downloaded
    # video into 'video_path'. The output will be placed in a shared place for all
    # downloaded videos across all modules.
    #
    # The '--restrict-filenames' ensures that no spaces or non-ASCII characters
    # are in the filename.
    #
    # The '-o' tells it to place the output video in the given path with the
    # format 'title-id.ext' where the title is the youtube video title and the id
    # is the id of the video on youtube.
    #
    # The '-w' tells the program to only download it if the video doesn't already
    # exist.
    ${ROOT_PATH}/bin/youtube-dl -w ${url} -o "${ROOT_PATH}/videos/youtube/%(title)s-%(id)s.%(ext)s" --restrict-filenames > /dev/null 2> /dev/null
    video_path=`ls ${ROOT_PATH}/videos/youtube/*${video_id}.mp4 2> /dev/null`
    echo "Downloaded ${url} as $(basename "${video_path}")"
  fi

  # Determine the relative url
  video_url="videos/youtube/$(basename "${video_path}")"

  # Negotiate whether or not the video was downloaded and then whether or not
  # a copy of it exists in the module's build path.
  if [ -e "${video_path}" ]; then
    mkdir -p ${PREFIX_ROOT}/videos/youtube
    if [ ! -e "${PREFIX_ROOT}/videos/youtube/$(basename "${video_path}")" ]; then
      cp "${video_path}" ${PREFIX_ROOT}/videos/youtube
      echo "Copied $(basename "${video_path}") to module."
    else
      echo "Video file $(basename "${video_path}") already exists in module."
    fi
  else
    echo "WARNING: could not download youtube video: ${url}"
  fi
}

download_googledoc() {
  # We can download pdfs of public google docs via:
  # https://docs.google.com/document/u/0/export?format=pdf&id=${GDOC_ID}

  # So, we want to transform any url of the form:
  # https://docs.google.com/a/code.org/document/d/1ylIlO7Pppk6W3Jt58VHS5mjvnshg9URvj3iCU0Ok6qY/edit?usp=sharing

  # To:
  # https://docs.google.com/document/u/0/export?format=pdf&id=1ylIlO7Pppk6W3Jt58VHS5mjvnshg9URvj3iCU0Ok6qY

  # The '/document/' part could be '/presentation/' for slides
  url=${1}

  # Get the id from the URL
  gdoc_id=`echo ${url} | grep -oe "/d/[^/]\+" | sed -u "s;/d/;;"`
  document_type=`echo ${url} | grep -oe ".com/[^/]\+" | sed -u "s;.com;;"`
  echo ${gdoc_id}

  pdf_path=
  if [[ ! -z "${gdoc_id}" ]]; then
    pdf_url="https://docs.google.com/${document_type}/u/0/export?format=pdf&id=${gdoc_id}"
    pdf_path=pdfs/${document_type}/${gdoc_id}.pdf

    mkdir -p "${PREFIX}/pdfs/${document_type}"

    wget ${SESSION} -nc -O ${PREFIX}/${pdf_path} ${pdf_url} |& tee -a ${2} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4
  fi
}

urldecode() { local i="${*//+/ }"; echo -e "${i//%/\\x}"; }

# This function 'fixes' links in resources.
#
# The `wget` program does an OK job at rewriting links, but only focuses on
# those links found in the normal HTML crawling path. So, links embedded in our
# <script> tags or within CSS or JS that are even slightly unusual will not be
# updated properly. This function does that work.
#
# Invoke as:
#   fixup "<file path>" "<path prefix>" ["<locale>"]
#
# The `path prefix` is the path that is prepended to absolute links in the
# resource to form appropriate relative paths.
#
# The `locale` string optionally allows the fixup to properly augment links
# that are affected by locale. So, when it is a link to a localized page from
# a localized page, that link is updated to properly go to the crawled page for
# the same locale.
fixup() {
  path=${1}
  replace=${2}
  replace_locale=${3}

  echo "[FIXUP] \`${path}\`"

  # Replace Blockly.assetUrl paths appropriately
  sed "s;Blockly.assetUrl(\"\([^\"]\+\)\");\"${STUDIO_DOMAIN}/blockly/\1\";g" -i ${path}

  # And blockly media:... urls
  sed "s;Blockly.assetUrl(\"\([^\"]\+\)\");\"${STUDIO_DOMAIN}/blockly/\1\";g" -i ${path}
  sed "s;,media:\"/blockly/;,media:\"${STUDIO_DOMAIN}/blockly/;" -i ${path}

  # Fix up EXTERNAL_VIDEOS to point internally
  for url in ${EXTERNAL_VIDEOS}; do
    part=${url#https://*/}
    host=${url%"/${part}"}
    sed "s;${host};${replace};gi" -i ${path}
  done

  # Ensure that references to the main domain are also relative links
  sed "s;${MAIN_DOMAIN};${replace};gi" -i ${path}
  sed "s;http:${BASE_MAIN_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_MAIN_DOMAIN};${replace};gi" -i ${path}

  # Ensure that references to the curriculum domain are also relative links
  sed "s;${CURRICULUM_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_CURRICULUM_DOMAIN};${replace};gi" -i ${path}

  # All other video sources have to be truncated, too
  # The bare video domain confuses URLs that contain the video domain as a
  # directory path. (aws.amazon.com/videos.code.org/...)
  #sed "s;${VIDEO_DOMAIN};${replace};gi" -i ${path}
  sed "s;${VIDEO_SSL_DOMAIN};${replace};gi" -i ${path}
  sed "s;http:${BASE_VIDEO_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_VIDEO_DOMAIN};${replace};gi" -i ${path}

  # All other image sources have to be truncated, too
  sed "s;${IMAGE_DOMAIN};${replace};gi" -i ${path}
  sed "s;${IMAGE_SSL_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_IMAGE_DOMAIN};${replace};gi" -i ${path}

  # All tts content should also redirect
  sed "s;${TTS_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_TTS_DOMAIN};${replace};gi" -i ${path}

  # DSCO content should redirect
  sed "s;${DSCO_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_DSCO_DOMAIN};${replace};gi" -i ${path}

  # All levelbuilder-studio assets (hmm??)
  sed "s;https://levelbuilder-${BASE_STUDIO_DOMAIN};${replace};gi" -i ${path}

  # For some reason, these don't all get converted either
  sed "s;${STUDIO_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_STUDIO_DOMAIN};${replace};gi" -i ${path}

  # Replace 'media?u='-style links
  sed "s;src\s*=\s*\\\\\"[^\"]\+media?u=[^\"]\+%2F\([^\\\\\"]\+\);src=\\\\\"${replace}/\1;gi" -i ${path}
  sed "s:src\s*=\s*\\\\&quot;[^\]\+media?u=[^\]\+%2F\([^\]\+\)\\\\:src=\\\\\&quot;${replace}/\1\\\\:gi" -i ${path}

  # Repair any weird extension mess that wget introduced
  sed "s;[.]css[.]html;.css;gi" -i ${path}
  sed "s;[.]js[.]html;.js;gi" -i ${path}
  sed "s;[.]woff[.]html;.woff;gi" -i ${path}
  sed "s;[.]woff2[.]html;.woff2;gi" -i ${path}
  sed "s;[.]ttf[.]html;.ttf;gi" -i ${path}
  sed "s;[.]png[.]html;.png;gi" -i ${path}
  sed "s;[.]svg[.]html;.svg;gi" -i ${path}
  sed "s;[.]gif[.]html;.gif;gi" -i ${path}

  # Repair any unaltered footer links
  sed "s;privacy\";privacy.html\";gi" -i ${path}
  sed "s;tos\";tos.html\";gi" -i ${path}

  # Fix links to extra levels to point to the levels path
  # (We assume all level content is nested at a certain directory depth)
  # (That is, /s/lessons/2/levels/1.html, so extras need to move from
  # /s/lessons/2/extras?level_name-etc.html to that path)
  sed "s;\/extras;\/levels\/extras;g" -i ${path}
  sed "s;\/extras?level_name=;\/extras-level_name-;g" -i ${path}

  # We need to fix 'sprite' lookups which have the form:
  # /v3/animations/TPOfgJbbhT3urA-rYwkeIWlv0iKT6g_YbJM9RQYZWxs/0226a484-bc4a-4a82-b1f6-24bd014ed06a.png?version=nLn_XD0CYBhbZ1GMAgw8QidKxkO5eeET
  # and replace it with something of the form:
  # /v3/animations/TPOfgJbbhT3urA-rYwkeIWlv0iKT6g_YbJM9RQYZWxs/0226a484-bc4a-4a82-b1f6-24bd014ed06a.png-version-nLn_XD0CYBhbZ1GMAgw8QidKxkO5eeET
  sed "s;png[?]version[=];png-version-;gi" -i ${path}

  # The video 'poster' has an absolute path and not picked up by the crawler
  sed "s;poster=\"/;poster=\";gi" -i ${path}

  # Fix the 'continue' button (and other metadata fields to use relative paths)
  KEYS="nextLevelUrl level_path redirect"
  for key in ${KEYS}
  do
    # Sigh to all of this.
    # Fix normal "key":"/s/blah/1" -> "key":"${replace}/s-en-US/blah/1.html"
    sed "s;${key}\":\"/s\([^\"]\+\);${key}\":\"${replace}/s-${replace_locale}\1.html;gi" -i ${path}
    # Fix slash escaped \"key\":\"/s/blah/1, etc
    sed "s,${key}\\\\\":\\\\\"/s\([^\\]\+\),${key}\\\\\":\\\\\"${replace}/s-${replace_locale}\1.html,gi" -i ${path}
    # Fix html escaped &quot;key&quot;:&quot;/s/blah/1, etc
    sed "s,${key}\&quot;:\&quot;/s\([^\&]\+\),${key}\&quot;:\&quot;${replace}/s-${replace_locale}\1.html,gi" -i ${path}
    # Fix slash escaped html escaped \&quot;key\&quot;:\&quot;/s/blah/1, etc
    sed "s,${key}\\\\\&quot;:\\\\\&quot;/s\([^\\]\+\),${key}\\\\\&quot;:\\\\\&quot;${replace}/s-${replace_locale}\1.html,gi" -i ${path}
  done

  # Let's also take the time to just remove references to next lessons.
  # This should replace links for /lessons/${LESSON + 1}/levels/1 with /lessons/${LESSON}/levels/1
  if [[ -z ${IS_COURSE} ]]; then
    NEXT_LESSON=$((LESSON + 1))
    sed "s;/lessons/${NEXT_LESSON}/levels;/lessons/${LESSON}/levels;g" -i ${path}
  fi

  # Rewrite finish link in each level to work with correct locale
  sed "s;\(finishLink\"\s*:\s*\"[^\"]\+\)\";\1.${replace_locale}.html\";gi" -i ${path}

  # Finally and brutally fix any remaining absolute pathed stuff
  # (this breaks the data-appoptions JSON for some levels, unfortunately)
  #sed "s;\"/\([^\"]\+[^/\"]\);\"${replace}/\1.html;gi" -i ${path}

  # Do so for 'src' attributes embedded into things like JavaScript sometimes
  # e.g. the download_button.png image for videos is generated on the fly.
  sed "s;src=\"/\([^\"]\+[^/\"]\);src=\"${replace}/\1;gi" -i ${path}

  # Do so for 'link' sections for docs json
  sed "s;\"link\":\"/\([^\"]\+[^/\"]\);\"link\":\"${replace}/\1.html;gi" -i ${path}

  # Do so for 'href' items in react components
  # First, look for uninterrupted and non-concatenated things we assume are html
  sed "s;\([^a-zA-Z0-9]\)href:\"\([^\.\"]\+\)\"\([^\.+]\);\1\"href\":\"\2.html\"\3;" -i ${path}
  # (this might be image assets in SVG elements, so we can't assume it ends in html)
  sed "s;\"href\":\"/\([^\"]\+[^/\"]\);\"href\":\"${replace}/\1;gi" -i ${path}

  # Fix any absolute stylesheets that still exist
  sed "s;href=\"/\([^\"]\+[^/\"]\).css;href=\"${replace}/\1.css;gi" -i ${path}

  # Fix 'sourceUrl' keys in JavaScript
  sed "s;\"sourceUrl\":\"/\([^\"]\+[^/\"]\);\"sourceUrl\":\"${replace}/\1;gi" -i ${path}

  # Fix 'baseUrl' keys in JavaScript (asset root path)
  sed "s;\"baseUrl\":\"/\([^\"]\+[^/\"]\);\"baseUrl\":\"${replace}/\1;gi" -i ${path}

  # Just fix any locale specific urls
  if [[ ! -z ${replace_locale} ]]; then
    sed "s;\/s\/;\/s-${replace_locale}\/;g" -i ${path}
  fi

  # Fix links to 'standards' pages
  sed "s;\(\/s[^/]\+\/[^/]\+\)\/standards\([^.]\);${replace}\1\/standards.html\2;g" -i ${path}
}

# Determine if this is a full Course (multiple lessons) or a single Lesson
# It is a single lesson if LESSON is provided, otherwise, we determine the
# number of lessons and iterate
IS_COURSE=
if [[ ! -z "${LESSON}" ]]; then
  # Ensure we crawl just the one lesson and not the entire course
  LESSONS=${LESSON}
else
  # Crawl Course page
  echo "Crawling ${COURSE}..."

  IS_COURSE=1
  COURSE_URL="${STUDIO_DOMAIN}/s/${COURSE}"

  download "-O ${PREFIX}/../base_course.html -nc" ${COURSE_URL} "${PREFIX}/wget-course.log"
  LESSONS=`grep -ohe "/lessons/[0-9]\+/levels/" ${PREFIX}/../base_course.html | sed -e "s;/lessons/;;" | sed -e "s;/levels/;;" | sort -n | uniq`

  download "--domains=${DOMAINS} -nc --page-requisites --convert-links --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}\" --exclude-domains=${EXCLUDE_DOMAINS}" "${COURSE_URL} https://code.org/tos https://code.org/privacy" "${PREFIX}/wget-course.log"

  fixup "${PREFIX}/s/${COURSE}.html" ".."
  fixup "${PREFIX}/tos.html" "."
  fixup "${PREFIX}/privacy.html" "."

  echo ""

  # However, if we are marking this 'PARTIAL', we actually want to re-run this
  # script on each lesson so it modularizes them all. Each lesson will become
  # its own module.

  if [[ ! -z "${PARTIAL}" ]]; then
    echo "Crawling each lesson as a module (PARTIAL is set)"
    echo ""

    # Delete the temp path
    if [[ -d ${ROOT_PATH}/build/${BUILD_DIR} ]]; then
      rm -rf ${ROOT_PATH}/build/${BUILD_DIR}
    fi

    for LESSON in ${LESSONS}
    do
      echo "Crawling lesson ${LESSON} as a module."
      echo ""
      LESSON="${LESSON}" ${ROOT_PATH}/package.sh $@
    done

    echo ""
    echo "Done."
    exit 0
  fi
fi

# Perform the 'before' callback
if [[ "$(type -t before)" != 'function' ]]; then
  echo ""
  echo "No before() specified."
else
  echo ""
  echo "Running before() callback..."
  before
fi

# Things we are collecting. We like collecting URLs.
FINISH_LINK=
LESSON_LEVELS=
LEVEL_URLS=

# Ensure we get the 'standards' page for teacher assessment
PLAN_URLS="${STUDIO_DOMAIN}/s/${COURSE}/standards "
for LESSON in ${LESSONS}
do
  if [[ "${LESSON}" == "0" ]]; then
    echo "Crawling base path ${COURSE} from ${STUDIO_DOMAIN}..."
    download "-O ${PREFIX}/../base_${LESSON}.html -nc" "${STUDIO_DOMAIN}/${COURSE}" "${PREFIX}/wget-levels.log"
  else
    # Crawl initial page for the lesson
    echo "Crawling ${COURSE}/lessons/${LESSON}/levels/{position} from ${STUDIO_DOMAIN}..."
    download "-O ${PREFIX}/../base_${LESSON}.html -nc" "${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/1" "${PREFIX}/wget-levels.log"
  fi

  # Negotiate which locales we want to crawl. If the LOCALES variable is
  # specified, those locales are crawled and placed in the distribution.
  # However, if nothing is specified, all locales are downloaded that the site
  # lists in the locale dropdown.
  if [[ -z "${LOCALES}" ]]; then
    echo "Determining locales..."

    # Look at the i18nDropdown JSON object
    SITE_LOCALES=`cat ${PREFIX}/../base_${LESSON}.html | grep -e "i18nDropdown\":" | grep -ohe "value%3D%22[^%]\+" | sed -u 's;value%3D%22;;'`

    if [[ -z ${SITE_LOCALES} ]]; then
      # Look at the actual locale dropdown if the static one exists
      SITE_LOCALES=`cat ${PREFIX}/../base_${LESSON}.html | grep -e "id\s*=\s*\"locale\"" -A100 | grep -oe "value\s*=\s*\"[^\"]\+" | sed -u 's;value\s*=\s*";;'`

      # Get the default locale (probably en_US, but who knows)
      STARTING_LOCALE=`cat ${PREFIX}/../base_${LESSON}.html | grep -e "id\s*=\s*\"locale\"" -A100 | grep -e "selected" | grep -oe "value\s*=\s*\"[^\"]\+" | sed -u 's;value\s*=\s*";;'`
    fi

    # If all else fails, just get the English version
    if [[ -z ${SITE_LOCALES} ]]; then
      SITE_LOCALES="en-US"
    fi

    # Replace _ with - (we do both, sigh)
    SITE_LOCALES=${SITE_LOCALES//_/-}

    # Ensure that LOCALES is treated as an array and get the 'initial' locale as
    # the first item in that list.
    LOCALES=(${SITE_LOCALES})

    # Get the default locale, if we didn't get it specifically above, as the
    # first locale in the list. This is the locale the module will initially
    # load.
    if [[ -z ${STARTING_LOCALE} ]]; then
      STARTING_LOCALE=${LOCALES[0]}
    fi

    # Tell us what we found
    echo "Packaging locales: ${LOCALES[@]}"
  fi

  if [[ "${LESSON}" != "0" ]]; then
    # Determine the number of levels
    echo "Determining the number of levels in the lesson..."
    LEVELS=`grep ${PREFIX}/../base_${LESSON}.html -ohe "\d/levels/[0-9]\+\"" | sed -u "s;\d/levels/;;" | sed -u "s;\";;" | sort -n | tail -n1`
    LEVELS="${LEVELS/$'\n'/}"

    # Determine any "finish" link
    FINISH_LINK=`grep -ohe "finishLink\"\s*:\s*\"[^\"]\+" ${PREFIX}/../base_${LESSON}.html | sed -u "s;finishLink\"\s*:\s*\";;" | sed -u "s;//[^/]\+/;https://code.org/;"`

    # If we cannot find it via 'levels/{num}' paths, try to find it using JSON information
    # via "levels":..."position":{num}
    if [[ -z "${LEVELS/$'\n'/}" ]]; then
      LEVELS=`grep ${PREFIX}/../base_${LESSON}.html -ohe "levels\":.*\"position\":[0-9]\+" | sed -u "s;levels\":.*\"position\":;;" | sort -n | tail -n1`
      LEVELS="${LEVELS/$'\n'/}"
    fi

    if [[ -z "${LEVELS/$'\n'/}" ]]; then
      echo "Error: Cannot determine the number of levels."
      exit 1
    fi

    LESSON_LEVELS="${LESSON_LEVELS} ${LEVELS}"

    echo "Found ${LEVELS} levels..."

    for (( i=1; i<=${LEVELS}; i++ ))
    do
      LEVEL_URLS="${LEVEL_URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i} "
    done

    # Retain lesson plan page
    PLAN_URLS="${PLAN_URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON} "

    # Determine if we have any 'extra' levels
    EXTRAS_LINK=`grep -ohe "lesson_extras_level_url\"\s*:\s*\"[^\"]\+" ${PREFIX}/../base_${LESSON}.html | sed -u "s;lesson_extras_level_url\"\s*:\s*\";;"`
  else
    LEVEL_URLS="${LEVEL_URLS}${STUDIO_DOMAIN}/${COURSE} "
  fi

  # Add the 'extras' page to the mix
  if [[ ! -z "${EXTRAS_LINK}" ]]; then
    echo "Found 'extras' link."
    LEVEL_URLS="${LEVEL_URLS}${EXTRAS_LINK} "

    # We will want to crawl the extras page for the actual levels
    download "-O ${PREFIX}/../base_${LESSON}_extras.html -nc" "${EXTRAS_LINK}" "${PREFIX}/wget-levels-extra.log"

    # Look at the level data and pull those extra levels out
    # We get tuples of 'id' and 'url' for extra levels with '~' in between
    EXTRAS_LEVEL_TUPLES=`grep "${PREFIX}/../base_${LESSON}_extras.html" -e "data-extras" | grep -ohe "id\"\s*:\s*\"[^\"]\+[^}]\+url\"\s*:\s*\"[^\"]\+" | sed -u "s;id\"\s*:\s*\";;" | sed -u "s;^\([^\"]\+\).\+\"url\"\s*:\s*\"//studio.code.org/;\1~;"`
    EXTRAS_LEVEL_TUPLES=(${EXTRAS_LEVEL_TUPLES})

    # For each of these, tease them out for EXTRAS_LEVEL_IDS
    EXTRAS_LEVEL_URLS=
    EXTRAS_LEVEL_IDS=
    for extras_level_tuple in "${EXTRAS_LEVEL_TUPLES[@]}"; do
      # Split by '~' and gather the id and url for each extra level
      tuple_parts=(${extras_level_tuple//\~/ })
      extras_level_id=${tuple_parts[0]}
      extras_level_url="${STUDIO_DOMAIN}/${tuple_parts[1]}"
      EXTRAS_LEVEL_IDS="${EXTRAS_LEVEL_IDS}${extras_level_id} "
      EXTRAS_LEVEL_URLS="${EXTRAS_LEVEL_URLS}${extras_level_url} "
    done

    # Add extra levels to our crawled levels
    LEVEL_URLS="${LEVEL_URLS}${EXTRAS_LEVEL_URLS} "
    EXTRAS_LEVEL_URLS=(${EXTRAS_LEVEL_URLS})
    EXTRAS_LEVEL_IDS=(${EXTRAS_LEVEL_IDS})
  fi

  # If we haven't pulled this via the course page, pull the privacy/tos pages too
  if [[ -z "${IS_COURSE}" ]]; then
    LEVEL_URLS="${LEVEL_URLS}https://code.org/tos https://code.org/privacy "
  fi
done
LESSON_LEVELS=(${LESSON_LEVELS})

# Whether or not we have crawled the site with one locale
# (We don't need to do all the steps for second locales)
DONE_ONCE=
for locale in "${LOCALES[@]}"; do
  echo ""
  echo "Using ${locale} locale."

  if [[ ! -z "${HASHED_EMAIL}" ]]; then
    echo ""
    ${ROOT_PATH}/set-locale.sh ${locale} ${HASHED_EMAIL} --quiet | tee ${ROOT_PATH}/${PREFIX}/set-locale-${locale}-log.txt
    echo ""
  else
    echo ""
    ${ROOT_PATH}/set-locale.sh ${locale} --quiet | tee ${ROOT_PATH}/${PREFIX}/set-locale-${locale}-log.txt
    echo ""
  fi

  SESSION_COOKIE=`cat ${ROOT_PATH}/${PREFIX}/set-locale-${locale}-log.txt | grep -C0 -e "Successfully set locale: " | sed -e "s;Successfully set locale: ;;"`
  SESSION="--load-cookies ${SESSION_COOKIE}"

  echo ""
  echo "Downloading all levels..."

  download "--domains=${DOMAINS} -nc --page-requisites --convert-links --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}\" --exclude-domains=${EXCLUDE_DOMAINS}" "${LEVEL_URLS} ${PLAN_URLS} ${FINISH_LINK}" "${PREFIX}/wget-levels.log"

  if [[ -z "${DONE_ONCE}" && -z "${IS_COURSE}" ]]; then
    echo ""
    echo "Fixing up privacy/tos pages..."
    fixup "${PREFIX}/tos.html" "."
    fixup "${PREFIX}/privacy.html" "."
  fi

  # Extra levels are special. They need to be in the same path as other levels
  # so they reach common assets the same way. So, they are moved.
  #
  # They are often accessed via query parameters, so the files are renamed to
  # reflect those parameters since there is no server in the background that can
  # understand that. This also involves changing the urls to update the '?' and
  # '=', etc, to simple '-' characters.
  #
  # The 'URL' for an extra level is expressed two different ways, unfortunately.
  # The first is the URL given by the bonus level specifically which is marked by
  # the level name. The other is a URL where it is specified by the level id. We
  # must support the use of both of those.
  if [[ ! -z "${EXTRAS_LINK}" ]]; then
    echo ""
    echo "Fixing up extra levels..."

    extras_path=`echo "${EXTRAS_LINK}" | sed -u "s;http[s]\?:${BASE_STUDIO_DOMAIN}\/;;"`
    extras_path="${extras_path}.html"

    dir=$(dirname "${extras_path}")
    filename=$(basename "${extras_path}")
    echo "[MOVE] ${extras_path} -> ${dir}/levels/${filename}"
    mv ${PREFIX}/${extras_path} ${PREFIX}/${dir}/levels/${filename}
    sed 's;../../../..;;' -i ${PREFIX}/${dir}/levels/${filename}
    fixup "${PREFIX}/${dir}/levels/${filename}" "${RELATIVE_PATH}"

    # For every extras level known, fix it up
    EXTRAS_LEVEL_FILENAMES=
    for k in "${!EXTRAS_LEVEL_URLS[@]}"; do
      extras_url=${EXTRAS_LEVEL_URLS[${k}]}
      extras_id=${EXTRAS_LEVEL_IDS[${k}]}
      extras_path=`echo "${extras_url}" | sed -u "s;http[s]\?:${BASE_STUDIO_DOMAIN}\/;;"`
      extras_path="${extras_path}.html"
      if [[ -e "${PREFIX}/${extras_path}" ]]; then
        dir=$(dirname "${extras_path}")
        filename=$(basename "${extras_path}")

        # Replace any '?', '%', or '=' with '-'
        filename=${filename//\?/-}
        filename=${filename//\=/-}
        filename=${filename//\%/-}

        # Move the extras html page to the proper nesting (matches other levels)
        # and remove any special characters from the filename
        # (the page fixup() function fixes links to reflect the changed filename
        # and path)
        echo "[MOVE] ${extras_path} -> ${dir}/levels/${filename}"
        mv ${PREFIX}/${extras_path} ${PREFIX}/${dir}/levels/${filename}
        sed 's;../../../..;;' -i ${PREFIX}/${dir}/levels/${filename}

        EXTRAS_LEVEL_FILENAMES="${EXTRAS_LEVEL_FILENAMES}${filename} "
      fi
    done
    EXTRAS_LEVEL_FILENAMES=(${EXTRAS_LEVEL_FILENAMES})
  fi

  echo ""
  echo "Downloading other pages..."

  FIXUP_PATHS=
  EXTRA_PATHS=
  for url in ${URLS}
  do
    dir=$(dirname "${url}")
    filename=$(basename "${url}")
    mkdir -p ${PREFIX}/${dir}

    download "--domains=${DOMAINS} --page-requisites --convert-links --adjust-extension --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-other.log"

    # We need to look for content within this page (and do fixups)
    EXTRA_PATHS="${EXTRA_PATHS} ${PREFIX}/${dir}/${filename}.html"
  done

  echo ""
  echo "Downloading any videos..."

  for url in ${VIDEOS}
  do
    dir=$(dirname "${url}")
    filename=$(basename "${url}")
    mkdir -p ${PREFIX}/${dir}
    mkdir -p videos/${dir}
    if [ -f videos/${dir}/${filename} ]; then
      echo "[EXISTS] \`${VIDEO_DOMAIN}/${dir}/${filename}\`"
    fi
    download_video "${dir}/${filename}" "${VIDEO_DOMAIN}/${dir}/${filename}" "${PREFIX}/wget-videos.log"
    cp ${video_path} ${PREFIX}/${dir}/${filename}
  done

  j=0
  for LESSON in ${LESSONS}
  do
    URLS=
    VIDEOS=
    IMAGES=
    EXTERNAL_VIDEOS=
    YT_URLS=
    GDOC_URLS=

    echo ""
    if [[ "${LESSON}" == "0" ]]; then
      LEVEL_PATHS=`ls ${PREFIX}/${COURSE}/*.html`
      LEVELS="0"
      echo "Analyzing ${COURSE} levels."
    else
      LEVEL_PATHS=`ls ${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/*.html ${PREFIX}/s/${COURSE}/lessons/*.html`
      LEVELS=${LESSON_LEVELS[j]}
      echo "Analyzing lesson ${LESSON} with ${LEVELS} levels."
    fi

    j=$((j + 1))

    echo ""
    echo "Downloading level properties, if any..."

    if [[ "${LESSON}" != "0" ]]; then
      for (( i=1; i<=${LEVELS}; i++ )); do
        mkdir -p ${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}
        download "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}/level_properties" ${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i}/level_properties "${PREFIX}/wget-level-properties.log"
      done
    fi

    echo ""
    echo "Downloading any possible script metadata..."

    for level_path in ${LEVEL_PATHS}; do
      # Find script_id and level_id
      script_id=`grep ${ROOT_PATH}/${level_path} -ohe "\"script_id\"\s*:\s*[0-9]\+" | sed -u 's;^\"script_id\"\s*:\s*;;' | head -n1`
      level_id=`grep ${ROOT_PATH}/${level_path} -ohe '\\\\\"level_id\\\\\":[0-9]\+' |  sed -u 's;^\\\\\"level_id\\\\\"\s*:\s*;;' | head -n1`

      if [[ ! -z ${script_id} ]]; then
        if [[ ! -z ${level_id} ]]; then
          url=${STUDIO_DOMAIN}/projects/script/${script_id}/level/${level_id}
          mkdir -p ${PREFIX}/projects/script/${script_id}/level
          download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" "${url}" "${PREFIX}/wget-scripts-level-metadata.log"
        fi
      fi
    done

    echo ""
    echo "Gathering videos and images..."

    # Look at every level html file and lesson file
    ALL_PATHS="${LEVEL_PATHS} ${EXTRA_PATHS}"
    for level_path in ${ALL_PATHS}; do
      # Find popup videos by their download links
      video=`grep ${level_path} -ohe "data-download\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2 | sed -u "s;${VIDEO_DOMAIN}/;;" | sed -u "s;http[s]\?://videos.code.org/;;"`
      if [[ ! -z "${video/$'\n'/}" ]]; then
        echo "[FOUND] \`${video}\`"
        VIDEOS="${VIDEOS} ${video}"

        note=`grep ${level_path} -ohe "data-key\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2`
        echo "[FOUND] \`notes/${note}\`"
        URLS="${URLS} notes/${note}"
      fi

      # Find youtube embed videos by their signature
      video=`grep ${level_path} -ohe "data-videooptions\s*=\s*['\"].\+\"download\"\s*:\s*\"[^\"]\+" | sed -u 's;^data-videooptions.\+download\s*\":\"/\?;;' | sed -u 's;http[s]\?://videos.code.org/;;'`
      if [[ ! -z "${video/$'\n'/}" ]]; then
        echo "[FOUND] \`${video}\`"
        VIDEOS="${VIDEOS} ${video}"
      fi

      # Find any internal or external video
      video=`grep ${level_path} -ohe "data-videooptions\s*=\s*['\"].\+\"download\"\s*:\s*\"https://[^\"]\+" | sed -u 's;^data-videooptions.\+download\s*\":\";;'`
      if [[ ! -z "${video/$'\n'/}" ]]; then
        if [[ "${video}" == https://videos.code.org* ]]; then
          echo "[FOUND] (internal) \`${video}\`"
          # Remove the https://videos.code.org/ prefix
          video=${video#"https://videos.code.org/"}
          VIDEOS="${VIDEOS} ${video}"
        else
          echo "[FOUND] (external) \`${video}\`"
          EXTERNAL_VIDEOS="${EXTERNAL_VIDEOS} ${video}"
        fi
      fi

      # Also find thumbnails
      asset=`grep ${level_path} -ohe "data-videooptions\s*=\s*['\"].\+\"thumbnail\"\s*:\s*\"[^\"]\+" | sed -u 's;^data-videooptions.\+thumbnail\s*\":\"/\?;;'`
      if [[ ! -z "${asset/$'\n'/}" ]]; then
        echo "[FOUND] \`${asset}\`"
        URLS="${URLS} ${asset}"
      fi

      # Find youtube links
      videos=`grep ${level_path} -ohe "youtube.com/watch[^\"#& )]\+"`
      for yt_url in ${videos}; do
        echo "[FOUND] \`${yt_url}\` (youtube)"
        YT_URLS="${YT_URLS} ${yt_url}"
      done

      # Find google doc links
      gdocs=`grep ${level_path} -ohe "\(http[s]\?://\)\?docs.google.com/[^\"#& )]\+"`
      for gdoc_url in ${gdocs}; do
        echo "[FOUND] \`${gdoc_url}\` (gdoc)"
        GDOC_URLS="${GDOC_URLS} ${gdoc_url}"
      done
      
      # Get any images (delimeted by ' or " or ) (from markdown) or & (for &quot;))
      image=`grep ${level_path} -ohe "\(${IMAGE_DOMAIN}\|${IMAGE_SSL_DOMAIN}\)/[^\"&')]\+" | sed -u 's;\s;%20;g'`
      if [[ ! -z "${image/$'\n'/}" ]]; then
        echo "[FOUND] \`${image}\`"
        IMAGES="${IMAGES} ${image}"
      fi
    done

    # Videos

    echo ""
    echo "Downloading any videos..."

    for url in ${VIDEOS}; do
      dir=$(dirname "${url}")
      filename=$(basename "${url}")
      mkdir -p ${PREFIX}/${dir}
      mkdir -p videos/${dir}
      if [ -f videos/${dir}/${filename} ]; then
        echo "[EXISTS] \`${VIDEO_DOMAIN}/${dir}/${filename}\`"
      fi
      download_video "${dir}/${filename}" "${VIDEO_DOMAIN}/${dir}/${filename}" "${PREFIX}/wget-videos.log"
      cp ${video_path} ${PREFIX}/${dir}/${filename}
    done

    for url in ${EXTERNAL_VIDEOS}; do
      video=${url#https://*/}
      dir=$(dirname "${video}")
      filename=$(basename "${video}")
      mkdir -p ${PREFIX}/${dir}
      mkdir -p videos/${dir}
      if [ -f videos/${dir}/${filename} ]; then
        echo "[EXISTS] \`${dir}/${filename}\`"
      fi
      download_video "${dir}/${filename}" "${url}" "${PREFIX}/wget-videos.log"
      cp ${video_path} ${PREFIX}/${dir}/${filename}
    done

    for yt_url in ${YT_URLS}; do
      download_youtube "${yt_url}"

      YOUTUBE_VIDEOS="${video_id}=${video_url} ${YOUTUBE_VIDEOS}"
    done

    for gdoc_url in ${GDOC_URLS}; do
      # Download and replace the link text with the local pdf
      # This function sets `gdoc_id` and `pdf_path`
      download_googledoc "${gdoc_url}" "${PREFIX}/wget-gdocs.log"

      if [[ ! -z "${pdf_path}" ]]; then
        GDOC_PDFS="${gdoc_id}=${pdf_path} ${GDOC_PDFS}"
      fi
    done

    # Images

    echo ""
    echo "Downloading any images..."

    for url in ${IMAGES}; do
      dir=$(dirname "${url}")
      filename=$(basename "${url}")
      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
    done

    # Other dynamic content we want wholesale downloaded (transcripts for the videos)

    echo ""
    echo "Downloading other pages..."

    for url in ${URLS}
    do
      dir=$(dirname "${url}")
      mkdir -p ${PREFIX}/${dir}

      download "--domains=${DOMAINS} --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-other.log"
    done

    if [[ ! -z ${FINISH_LINK} ]]; then
      echo ""
      echo "Gathering assets for certificate page..."
      path=`echo ${FINISH_LINK} | sed -u 's;http[s]\?://[^/]\+/;;'`
      mv ${PREFIX}/${path}.html ${PREFIX}/${path}.${locale}.html
      path="${PREFIX}/${path}.${locale}.html"
      ASSETS=`grep ${path} -ohe "certificate_image_url\"\s*:\s*\"[^\"]\+" | sed -u "s;[^\"]\+\"\s*:\s*\";;g" | sed -u "s;^//;https://;"`

      for url in ${ASSETS}
      do
        path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
        dir=$(dirname "${path}")
        filename=$(basename "${path}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
      done
    fi

    echo ""
    echo "Gathering assets from levels..."

    # wget occasionally trips up getting script tags in the body, too, for some reason
    path="${PREFIX}/../base_${LESSON}.html"
    ASSETS=`grep ${path} -e "<[sS][cC][rR][iI][pP][tT].\+[sS][rR][cC]\s*=\s*\"/" | grep -ohe "[sS][rR][cC]\s*=\s*\"[^\"]\+" | sed -u "s;[sS][rR][cC]\s*=\s*\"/;;"`
    for url in ${ASSETS}
    do
      dir=$(dirname "${url}")
      filename=$(basename "${url}")

      mkdir -p ${PREFIX}/${dir}
      download "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done

    LEVEL_PATHS=`ls ${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/*.html`
    for level_path in ${LEVEL_PATHS}; do
      ASSETS=`grep ${level_path} -ohe "appOptions\s*=\s*\({.\+\)\s*;\s*$" | sed -u "s;appOptions\s*=\s*;;" | sed -u "s/;$//" | grep -ohe "http[s]://[^ )\\\\\"\']\+"`

      for url in ${ASSETS}
      do
        domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
        path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
        dir=$(dirname "${path}")
        filename=$(basename "${path}")

        if [[ ${domain} == "studio.code.org" || ${domain} == "tts.code.org" || ${domain} == "images.code.org" ]]; then
          mkdir -p ${PREFIX}/${dir}
          download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
        fi
      done

      # Gather helper libraries
      ASSETS=`grep ${level_path} -ohe "helperLibraries\"\s*:\s*\[[^]]\+\]" | cut -d ":" -f2 | sed -u "s;\[\|\"\|\];;g" | sed -u "s;,; ;g"`
      for url in ${ASSETS}
      do
        LIBRARIES="${LIBRARIES} ${url}"
      done

      # Gather static assets from the base html, too
      # These are any api urls of the form \"/api/v1/etc\"
      ASSETS=`grep ${level_path} -ohe "[\]\"/api/v1/[^\"]\+[\]\"" | sed -u "s;[\]\"/\?;;g"`
      for url in ${ASSETS}
      do
        dir=$(dirname "${url}")
        filename=$(basename "${url}")

        mkdir -p ${PREFIX}/${dir}
        echo "[FOUND] ${url}"
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
      done

      # wget does not find stylesheets that are in <link> tags inside the <body>
      # ... mostly because that makes such little sense.
      ASSETS=`grep ${level_path} -e "<[lL][iI][nN][kK].\+[hH][rR][eE][fF]\s*=\s*\"/" | grep -ohe "[hH][rR][eE][fF]\s*=\s*\"[^\"]\+" | sed -u "s;[hH][rR][eE][fF]\s*=\s*\"/;;"`
      for url in ${ASSETS}
      do
        dir=$(dirname "${url}")
        filename=$(basename "${url}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
      done

      ASSETS=`grep ${level_path} -e "<[lL][iI][nN][kK].\+[hH][rR][eE][fF]\s*=\s*\"${STUDIO_DOMAIN}" | grep -ohe "[hH][rR][eE][fF]\s*=\s*\"[^\"]\+" | sed -u "s;[hH][rR][eE][fF]\s*=\s*\"${STUDIO_DOMAIN}/;;"`
      for url in ${ASSETS}
      do
        domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
        path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
        dir=$(dirname "${path}")
        filename=$(basename "${path}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
      done

      # Get ID of application this level represents ('craft', 'dance', etc)
      APP_ID=`grep ${level_path} -ohe "app\s*:\s*['\"][a-z][a-z][^\"']*['\"]" | sed -u "s;app\s*:\s*['\"]\([^'\"]\+\)['\"];\1;" | tail -n1`
      if [ ! -z "${APP_ID}" ]; then
        echo "[DETECTED] Found '${APP_ID}' app via ${level_path}"

        # We probably want the skins and media paths for this app type
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/${APP_ID}"
        fi
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/skins/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/skins/${APP_ID}"
        fi
      fi

      # Get Skin, if any
      SKIN_ID=`grep ${level_path} -ohe "skin['\"]\s*:\s*['\"][a-z][a-z][^\"']*['\"]" | sed -u "s;skin['\"]\s*:\s*['\"]\([^'\"]\+\)['\"];\1;" | tail -n1`
      if [ ! -z "${SKIN_ID}" ]; then
        echo "[DETECTED] Found '${SKIN_ID}' skin via ${level_path}"

        # Gather static path
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/skins/${SKIN_ID}" ]; then
          PATHS="${PATHS} blockly/media/skins/${SKIN_ID}"
        fi
      fi
    done

    # Fix-ups
    # video transcripts reference image assets relative to itself...
    # we must move this to be relative to the level

    if [[ -z "${LOCAL_NOTES}" ]]; then
      if [ -d ${PREFIX}/assets/notes ]; then
        echo ""
        echo "Fixing video transcripts..."

        echo "[MOVE] \`./assets/notes\` -> \`./s/${COURSE}/lessons/${LESSON}/assets/.\`"
        mkdir -p ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets
        mv ${PREFIX}/assets/notes ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets/.
      fi
    fi

    # Individual fix-ups
    LEVEL_PATHS=`ls ${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/*.html`
    for level_path in ${LEVEL_PATHS}; do
      FIXUP_PATHS="${FIXUP_PATHS} ${level_path}"
    done

    # Just go ahead and fixup the finish link page
    if [[ ! -z ${FINISH_LINK} ]]; then
      # Ensure the finish page (certificate page) has relative links to the
      # root of the module.
      path=`echo ${FINISH_LINK} | sed -u 's;http[s]\?://[^/]\+/;;'`
      route=$(dirname "${path}")
      replace=`echo ${route} | sed -u 's;\(/\|^\)[^/]\+;\1..;g'`
      path="${PREFIX}/${path}.${locale}.html"
      fixup ${path} ${replace} ${locale}

      # Ensure it gets copied over
      mkdir -p ${PREFIX}/../${route}
      cp ${path} ${PREFIX}/../${route}
    fi

    # Detect usage of the Ace Editor and pull those assets as well
    # This is true if blockly/js/ace.js is present in ASSETS
    ACE_FOUND=0
    for (( i=1; i<=${LEVELS} && ${ACE_FOUND}==0; i++ ))
    do
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      if grep "${path}" -ohe "blockly/js/ace" 2> /dev/null > /dev/null; then
        echo "[DETECTED] Ace Editor"
        PATHS="${PATHS} blockly/js/ace"
        ACE_FOUND=1
      fi
    done
  done

  echo ""
  echo "Gathering assets from css..."

  # Gather assets from CSS
  CSS=`find ${PREFIX} -name \*.css`
  for css in ${CSS}
  do
    ASSETS=`grep ${css} -e "url([\"]\?${STUDIO_DOMAIN}" | grep -ohe "url([\"]\?${STUDIO_DOMAIN}[^\")]\+" | sed -u "s;url([\"]\?${STUDIO_DOMAIN}/;;"`
    for url in ${ASSETS}
    do
      domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
      path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
      dir=$(dirname "${path}")
      filename=$(basename "${path}")

      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done

    # Find DSCO assets
    ASSETS=`grep ${css} -e "url([\"]\?${DSCO_DOMAIN}" | grep -ohe "url([\"]\?${DSCO_DOMAIN}[^\")]\+" | sed -u "s;url([\"]\?${DSCO_DOMAIN}/;;"`
    for url in ${ASSETS}
    do
      domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
      path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
      dir=$(dirname "${path}")
      filename=$(basename "${path}")

      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${DSCO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done

    # Also grab any relative resources. These are relative to the CSS file,
    # annoyingly. For some reason, they are not picked up by wget.
    ASSETS=`grep ${css} -oe "url([\"]\?[.][.][^)]\+" | sed -u 's;url([\"]\?;;'`
    for relative_url in ${ASSETS}
    do
      path="assets/css/${relative_url}"
      url=${path}
      dir=$(dirname "${path}")
      filename=$(basename "${path}")

      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done
  done

  echo ""
  echo "Fixing links in pages..."

  for path in ${FIXUP_PATHS}; do
    fixup ${path} "${RELATIVE_PATH}" ${locale}
  done

  for path in ${EXTRA_PATHS}; do
    # Compute relative path from the extra path
    relative_path=`echo $(dirname $path) | sed "s;^${PREFIX};;" | sed "s;/[^/]\+;/..;g" | sed "s;^/;;"`
    fixup ${path} "${relative_path}" ${locale}
  done

  # We're done analyzing any 'extra paths'
  # EXTRA_PATHS are specific pages pulled via 'URLS'
  EXTRA_PATHS=

  # Fix up lesson plan pages
  plan_paths=`ls ${PREFIX}/s/${COURSE}/lessons/*.html`
  for path in ${plan_paths}; do
    fixup ${path} "../../.." ${locale}
  done

  # Fix up standards page
  if [ -e "${PREFIX}/s/${COURSE}/standards.html" ]; then
      fixup "${PREFIX}/s/${COURSE}/standards.html" "../.." ${locale}
  fi

  # And any strange placeholder graphics built in our apps chain
  for img in `ls ${CODE_DOT_ORG_REPO_PATH}/apps/build/package/js/*.{jpg,png} 2> /dev/null`
  do
    dir=$(dirname "${img}")
    filename=$(basename "${img}")

    mkdir -p ${PREFIX}/assets/js
    echo "[COPYING] \`${PREFIX}/assets/js/${filename}\`"
    cp ${img} ${PREFIX}/assets/js/.
  done

  FIXUP_PATHS=
  if [[ -z "${DONE_ONCE}" ]]; then
    echo ""
    echo "Gathering webpack chunks..."

    WEBPACK_CHUNK_JS=`grep ${PREFIX}/assets/js/webpack*.js -ohe '"wp"+{[^}]\+' | sed -u 's;"wp"+{;;' | sed -u 's;:";wp;g' | sed -u 's;",;.min.js ;g'`
    for webpack_chunk in ${WEBPACK_CHUNK_JS}; do
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/assets/js/${webpack_chunk} "${PREFIX}/wget-assets.log"
    done

    echo ""
    echo "Gathering assets from JavaScript..."

    LIBRARIES_FILES=`ls ${CODE_DOT_ORG_REPO_PATH}/dashboard/config/libraries`
    libraries=
    for library in ${LIBRARIES_FILES}
    do
      library="${library%%.*}"
      libraries="${libraries}\"${library}\"\|"
    done

    # Also add the javascript (and assets found within)
    for js in `ls ${PREFIX}/assets/js/*.js ${PREFIX}/assets/js/*/*.js`
    do
      FIXUP_PATHS="${FIXUP_PATHS} ${js}"

      # Gather static assets from javascript
      # Replace Trashcan graphics... if we can
      TRASHCAN_CLOSED_URL=`grep ${js} -ohe "Blockly.Trashcan.CLOSED_URL_\s*=\s*\"[^\"]\+\"" | sed -u "s;Blockly.Trashcan.CLOSED_URL_\s*=\s*\"\([^\"]\+\)\";\1;" | tail -n1`
      if [ ! -z "${TRASHCAN_CLOSED_URL}" ]; then
        sed "s;Blockly.Trashcan.CLOSED_URL_);\"${TRASHCAN_CLOSED_URL}\");gi" -i ${js}
      fi
      TRASHCAN_OPEN_URL=`grep ${js} -ohe "Blockly.Trashcan.OPEN_URL_\s*=\s*\"[^\"]\+\"" | sed -u "s;Blockly.Trashcan.OPEN_URL_\s*=\s*\"\([^\"]\+\)\";\1;" | tail -n1`
      if [ ! -z "${TRASHCAN_OPEN_URL}" ]; then
        sed "s;Blockly.Trashcan.OPEN_URL_);\"${TRASHCAN_OPEN_URL}\");gi" -i ${js}
      fi

      for blocklyAsset in `grep ${js} -ohe "Blockly.assetUrl(\"[^)]\+\(mp3\|png\|gif\|cur\)\")" | sed -u "s;Blockly.assetUrl(\"\(.\+\)\")$;blockly/\1;g"`; do
        STATIC="${STATIC} ${blocklyAsset}"
      done

      # Get ID of application this JS file represents ('craft', 'dance', etc)
      APP_ID=`grep ${js} -ohe "{app\s*:\s*['\"][a-z][a-z][^\"']*['\"]" | sed -u "s;{app\s*:\s*['\"]\([^'\"]\+\)['\"];\1;" | tail -n1`
      if [ ! -z "${APP_ID}" ]; then
        echo "[DETECTED] Found '${APP_ID}' app via $(basename ${js})"

        # We probably want the skins and media paths for this app type
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/${APP_ID}"
        fi
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/skins/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/skins/${APP_ID}"
        fi

        # Now we can determine the asset root (blockly/media/skins/${APP_ID}/...)
        ASSET_ROOT=blockly/media/skins/${APP_ID}/

        # Gather them
        ITEMS=`grep ${js} -ohe "this.assetRoot\s*+\s*['\"][^'\"]\+\(mp3\|png\|gif\|cur\)['\"]" | sed -u "s;this.assetRoot\s*+\s*['\"]\([^'\"]\+\)['\"];${ASSET_ROOT}\1;g"`
        for asset in ${ITEMS}; do
          STATIC="${STATIC} ${asset}"
        done
      fi

      # Immersive Reader (external things)
      ITEMS=`grep ${js} -ohe "https://contentstorage.onenote[^\"]\+"`
      for url in ${ITEMS}; do
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
      done
      sed "s;https://contentstorage.onenote.office.net;${RELATIVE_PATH};gi" -i ${js}

      MEDIA_URL=`grep ${js} -ohe "MEDIA_URL\s*=\s*\"[^\"]\+\"" | sed -u "s;MEDIA_URL\s*=\s*\"/\([^\"]\+\)\";\1;" | tail -n1`
      if [ ! -z "${MEDIA_URL}" ]; then
        echo "[DETECTED] Found an asset path: ${MEDIA_URL}"

        # Gather MEDIA_URL items
        ITEMS=`grep ${js} -ohe "MEDIA_URL\s*+\s*\"[^,]\+\"" | sed -u "s;MEDIA_URL\s*+\s*\"\([^\"]\+\)\";${MEDIA_URL}\1;"`
        for asset in ${ITEMS}; do
          STATIC="${STATIC} ${asset}"
        done
      fi

      # Look for library referenced in the JavaScript and add it
      references=`grep ${js} -ohe "${libraries}" | sed -u "s;\";;g"`

      if [ ! -z "${references}" ]; then
        for reference in ${references}
        do
          LIBRARIES="${LIBRARIES} ${reference}"
        done
      fi

      # Get the hard-coded images (download_button for video, etc)
      ASSETS=`grep ${js} -ohe "src\s*=\s*\"/[^\"]*" | sed -u 's;^src\s*=\s*"/;;g'`
      for url in ${ASSETS}
      do
        STATIC="${STATIC} ${url}"
      done

      # Get blockly assets that are hard-coded
      ASSETS=`grep ${js} -ohe "src:\s*\"/blockly/[^\"]*" | sed -u 's;^src:\s*"/;;g'`
      for url in ${ASSETS}
      do
        STATIC="${STATIC} ${url}"
      done

      # Get blockly trash can picture
      ASSETS=`grep ${js} -ohe "TRASH_URL=\"[^\"]\+" | sed -u "s;TRASH_URL=\"/;;g"`
      for url in ${ASSETS}
      do
        STATIC="${STATIC} ${url}"
      done

      # Everything EXCEPT the really large sound-library should be included
      ASSETS=`grep ${js} -ohe "\"\(https://studio.code.org\)\?/api/v1/[^s][^o][^u][^\"]\+/\?\"[^.]" | sed -u 's;\"\(https://studio.code.org\)\?/\?\([^.]$\)\?;;g'`
      for url in ${ASSETS}
      do
        dir=$(dirname "${url}")
        filename=$(basename "${url}")

        # If the 'filename' does not have an extension... it is probably a route
        # that we need to rewrite.
        if [[ "$filename" != *"."* ]]; then
          sed "s;${url}\/\?\";${url}.json\";g" -i ${js}
          filename="${filename}.json"
        fi

        mkdir -p ${PREFIX}/${dir}
        echo "[FOUND] ${url}"
        download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" https://studio.code.org/${url} "${PREFIX}/wget-assets.log"
      done
    done
  fi

  echo ""
  echo "Fixing links in pages..."

  for path in ${FIXUP_PATHS}
  do
    fixup ${path} "${RELATIVE_PATH}" ${locale}
  done

  # Add some of the extra silly things
  if [[ ! -e "${PREFIX}/s/${COURSE}/hidden_lessons" ]]; then
    mkdir -p "${PREFIX}/s/${COURSE}"
    echo "[]" > "${PREFIX}/s/${COURSE}/hidden_lessons"
  fi

  # Move the 'levels' to a locale-specific place
  mv ${PREFIX}/s ${PREFIX}/../s-${locale}

  # Move the video transcripts to a locale-specific place
  mv ${PREFIX}/notes ${PREFIX}/../notes-${locale}

  # For all content, move it over to the resulting directory if it doesn't
  # already exist
  cd ${ROOT_PATH}
  cd ${PREFIX}
  echo ""
  echo "Moving new files."
  find . -print0 | while read -d $'\0' file; do
    path=${file:2}
    dir=$(dirname "${path}")
    if [[ ! -e "${ROOT_PATH}/${PREFIX}/../${dir}" ]]; then
      echo "[MKDR] ${dir}"
      mkdir -p "${ROOT_PATH}/${PREFIX}/../${dir}"
    fi
    if [[ ! -e "${ROOT_PATH}/${PREFIX}/../${path}" ]]; then
      echo "[MOVE] ${path}"
      mv "${ROOT_PATH}/${PREFIX}/${path}" "${ROOT_PATH}/${PREFIX}/../${path}"
    fi
  done
  cd ${ROOT_PATH}

  # Remove our temporary space so we can do it again
  rm -rf ${PREFIX}
  mkdir -p ${PREFIX}

  # Set our variable to denote that we have done this loop at least once.
  DONE_ONCE=1
done

# Point to our resulting build path
PREFIX=build/${BUILD_DIR}

# Add shims

echo ""
echo "Adding JS/CSS shims..."

DEST="${PREFIX}/assets/application*.js ${PREFIX}/js/jquery.min*.js ${PREFIX}/assets/js/webpack*.js ${PREFIX}/assets/js/vendor*.js ${PREFIX}/assets/js/essential*.js ${PREFIX}/assets/js/common*.js ${PREFIX}/assets/js/code-studio-*.js"
DEST=`ls ${DEST}`

YOUTUBE_VIDEOS=(${YOUTUBE_VIDEOS})
GDOC_PDFS=(${GDOC_PDFS})

for js in ${DEST}
do
  path=`echo ${js} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] \`shims/shim.js\` -> \`${path}\`"

    # Create a new file with the shims prepended
    cat shims/shim.js ${js} > ${js}.new

    # Add REPLACE
    sed "s;%REPLACE%;${RELATIVE_PATH};" -i ${js}.new

    # Updates to add LOCALES
    LOCALE_ARRAY=
    for locale in "${LOCALES[@]}"; do
      if [[ -z "${LOCALE_ARRAY}" ]]; then
        LOCALE_ARRAY="${locale}"
      else
        LOCALE_ARRAY="${locale}\", \"${LOCALE_ARRAY}"
      fi
    done
    sed "s;%LOCALES%;${LOCALE_ARRAY};" -i ${js}.new

    # Updates to add YOUTUBE_VIDEOS
    YOUTUBE_VIDEOS_ARRAY=
    for yt_tuple in "${YOUTUBE_VIDEOS[@]}"; do
      if [[ -z "${YOUTUBE_VIDEOS_ARRAY}" ]]; then
        YOUTUBE_VIDEOS_ARRAY="${yt_tuple}"
      else
        YOUTUBE_VIDEOS_ARRAY="${yt_tuple}\", \"${YOUTUBE_VIDEOS_ARRAY}"
      fi
    done
    sed "s;%YOUTUBE_VIDEOS%;${YOUTUBE_VIDEOS_ARRAY};" -i ${js}.new

    # Updates to add YOUTUBE_VIDEOS
    GDOC_PDFS_ARRAY=
    for gdoc_tuple in "${GDOC_PDFS[@]}"; do
      if [[ -z "${GDOC_PDFS_ARRAY}" ]]; then
        GDOC_PDFS_ARRAY="${gdoc_tuple}"
      else
        GDOC_PDFS_ARRAY="${gdoc_tuple}\", \"${GDOC_PDFS_ARRAY}"
      fi
    done
    sed "s;%GDOC_PDFS%;${GDOC_PDFS_ARRAY};" -i ${js}.new

    # Updates to add EXTRA_LEVELS
    EXTRA_LEVELS_ARRAY=
    for k in "${!EXTRAS_LEVEL_URLS[@]}"; do
      extras_path=${EXTRAS_LEVEL_FILENAMES[${k}]}
      extras_id=${EXTRAS_LEVEL_IDS[${k}]}
      extras_level_tuple="${extras_id}=${extras_path}"

      if [[ -z "${EXTRA_LEVELS_ARRAY}" ]]; then
        EXTRA_LEVELS_ARRAY="${extras_level_tuple}"
      else
        EXTRA_LEVELS_ARRAY="${extras_level_tuple}\", \"${EXTRA_LEVELS_ARRAY}"
      fi
    done
    sed "s;%EXTRA_LEVELS%;${EXTRA_LEVELS_ARRAY};" -i ${js}.new

    # Commit it
    mv ${js}.new ${js}
  fi
done

# Look at css files within the assets path
DEST=`ls ${PREFIX}/assets/css/*.css`
for css in ${DEST}
do
  path=`echo ${css} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] \`shims/shim.css\` -> \`${path}\`"
    cat shims/shim.css ${css} > ${css}.new
    mv ${css}.new ${css}
  fi
done

# Also handle css files at 'root'
DEST=`ls ${PREFIX}/*.css`
for css in ${DEST}
do
  path=`echo ${css} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] \`shims/shim.css\` -> \`${path}\`"
    cat shims/shim.css ${css} > ${css}.new
    mv ${css}.new ${css}
  fi
done

# Repair firehose
sed "s/return \(.\)\.putRecord/return null; return \1.putRecord/" -i ${PREFIX}/assets/js/code-studio-co*.js

# Copy in necessary other static files

echo ""
echo "Copying static data..."

cp -r static/api ${PREFIX}/.
cp -r static/dashboardapi ${PREFIX}/.
cp -r static/levels ${PREFIX}/.

# Add common things to STATIC
STATIC="${STATIC} shared/images/Powered-By_logo-horiz_RGB.png"

# Copy in static content
for static in ${STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  download_shared "--tries=1 --timeout=20" ${STUDIO_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-static.log"
  if [ $? -ne 0 ]; then
    # If that failed, try the main domain instead of the studio domain
    rm ${PREFIX}/${dir}/${filename}
    download_shared "--tries=1 --timeout=20" ${MAIN_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-static.log"

    if [ $? -ne 0 ]; then
      # If THAT failed, try the live domain instead of any local domains
      rm ${PREFIX}/${dir}/${filename}
      download_shared "--tries=1 --timeout=20" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-static.log"
    fi
  fi
done

# Copy whole directories
PATHS=`for path in ${PATHS}; do echo "${path}"; done | sort -u`
for path in ${PATHS}
do
  dir=$(dirname "${path}")
  mkdir -p ${PREFIX}/${dir}
  echo "[COPY] \`${path}\`"
  cp -r "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/${path}" ${PREFIX}/${dir}/.
done

# Parse files
for path in ${PARSE}
do
  THINGS=`cat ${PREFIX}/${path} | grep -ohe "http[s]://[^ )\\\\\"\']\+"`

  for url in ${THINGS}
  do
    domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
    subpath=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
    dir=$(dirname "${subpath}")
    filename=$(basename "${subpath}")

    if [[ ${domain} == "studio.code.org" || ${domain} == "tts.code.org" || ${domain} == "images.code.org" ]]; then
      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-parsed-static.log"
    fi
  done

  # We also then want to 'fixup' any of the absolute URLs in this content
  # so it actually points to these assets.
  fixup "${PREFIX}/${path}" "${RELATIVE_PATH}"
done

if [[ ! -z "${CURRICULUM_STATIC/$'\n'/}" ]]; then
  echo ""
  echo "Copying curriculum static data..."
else
  echo ""
  echo "No curriculum static data to copy over."
fi

# Copy in curriculum static content
for static in ${CURRICULUM_STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  download_shared "--tries=1" ${CURRICULUM_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-curriculum.log"
done

if [[ ! -z "${RESTRICTED/$'\n'/}" ]]; then
  echo ""
  echo "Copying restricted data..."

  # Remove lingering cookie jar
  if [ -f cookies.jar ]; then
    echo "[DELETE] \`cookies.jar\`"
    rm -f cookies.jar
  fi

  if [ -f signed-cookies.jar ]; then
    echo "[DELETE] \`signed-cookies.jar\`"
    rm -f signed-cookies.jar
  fi
else
  echo ""
  echo "No restricted data to copy over."
fi

# Get signed / restricted content
for static in ${RESTRICTED}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  mkdir -p restricted/${dir}

  if [[ -z "${COOKIES}" ]]; then
    # Get a local user session
    echo "[GET] Getting a signed cookie (cookies.jar / signed-cookies.jar)"
    wget --keep-session-cookies --save-cookies cookies.jar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Host: studio.code.org" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Accept-Encoding: gzip, deflate, br" --header "Cache-Control: no-cache" --header "Connection: keep-alive" https://studio.code.org/s/${COURSE}/lessons/${LESSON}/levels/1 2> /dev/null > /dev/null

    # Sign the cookies
    wget --keep-session-cookies --load-cookies cookies.jar --save-cookies signed-cookies.jar https://studio.code.org/dashboardapi/sign_cookies -O ${PREFIX}/dashboardapi/sign_cookies 2> /dev/null > /dev/null

    COOKIES=signed-cookies.jar
  fi

  # Acquire the thing
  if [ -f restricted/${dir}/${filename} ]; then
    echo "[EXISTS] \`https://studio.code.org/${dir}/${filename}\`"
  fi

  download "--load-cookies signed-cookies.jar -O restricted/${dir}/${filename} --tries=1 -nc" "https://studio.code.org/${dir}/${filename}" "${PREFIX}/wget-restricted.log"

  # Ensure we have the ffmpeg program
  ensure_ffmpeg

  # Make smaller versions

  # Use ffmpeg to generate a smaller video
  smaller_path=${ROOT_PATH}/restricted/smaller/${dir}/${filename}
  mkdir -p ${ROOT_PATH}/restricted/smaller/${dir}
  if [ ! -e ${ROOT_PATH}/restricted/smaller/${dir}/${filename} ]; then
    # Create a downsized audio
    echo "[CREATE] \`restricted/smaller/${dir}/${filename}\`"
    ../bin/ffmpeg -i ../build/dance-2019/restricted/breakmysoul_beyonce.mp3 -map 0:a:0 -b:a 96k output.mp3
    ${ROOT_PATH}/bin/ffmpeg -i ${ROOT_PATH}/restricted/${dir}/${filename} -map 0:a:0 -b:a 96k ${ROOT_PATH}/restricted/smaller/${dir}/${filename}
  else
    echo "[EXISTS] \`restricted/smaller/${dir}/${filename}\`"
  fi

  cp ${ROOT_PATH}/restricted/smaller/${dir}/${filename} ${PREFIX}/${dir}/${filename}
done

if [[ ! -z "${LIBRARIES/$'\n'/}" ]]; then
  echo ""
  echo "Copying helper libraries..."

  for url in ${LIBRARIES}
  do
    url="libraries/${url}"
    dir=$(dirname "${url}")
    filename=$(basename "${url}")

    mkdir -p ${PREFIX}/${dir}
    download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
  done
else
  echo ""
  echo "No helper libraries."
fi

# Repair stylesheets

echo ""
echo "Repairing stylesheets..."

CSS=`ls ${PREFIX}/assets/*/*/*/*.css`
for css in ${CSS}
do
  fixup ${css} "../../../.."
done

CSS=`ls ${PREFIX}/assets/*/*/*.css`
for css in ${CSS}
do
  fixup ${css} "../../.."
done

CSS=`ls ${PREFIX}/assets/*/*.css`
for css in ${CSS}
do
  fixup ${css} "../.."
done

CSS=`ls ${PREFIX}/assets/*.css`
for css in ${CSS}
do
  fixup ${css} ".."
done

# Perform the 'after' callback
if [[ "$(type -t after)" != 'function' ]]; then
  echo ""
  echo "No after() specified. Done finalizing."
else
  echo ""
  echo "Running after() callback..."
  after
fi

# Remove newly created cookie jar
rm -f cookies.jar signed-cookies.jar

# Create an index.html to redirect
echo
echo "Creating index.html to redirect to the first level."
echo "[CREATE] \`index.html\` for RACHEL"
if [[ "${LESSON}" == "0" ]]; then
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${COURSE}.html\" />" > ${PREFIX}/index.html
else
  if [[ -z "${IS_COURSE}" ]]; then
    echo "<meta http-equiv=\"refresh\" content=\"0; URL=s-${STARTING_LOCALE}/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/index.html
  else
    echo "<meta http-equiv=\"refresh\" content=\"0; URL=${COURSE}.html\" />" > ${PREFIX}/index.html
  fi
fi
echo "[CREATE] \`index.html\` for Kolibri"
mkdir -p ${PREFIX}/zip-root
if [[ "${LESSON}" == "0" ]]; then
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/${COURSE}.html\" />" > ${PREFIX}/zip-root/index.html
else
  if [[ -z "${IS_COURSE}" ]]; then
    echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/zip-root/index.html
  else
    echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}.html\" />" > ${PREFIX}/zip-root/index.html
  fi
fi
echo "[CREATE] \`index.html\` for Kolibri teachers"
mkdir -p ${PREFIX}/zip-root-teacher
if [[ -z "${IS_COURSE}" ]]; then
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}/lessons/${LESSON}.html\" />" > ${PREFIX}/zip-root-teacher/index.html
else
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}/lessons/1.html\" />" > ${PREFIX}/zip-root-teacher/index.html
fi
echo "[CREATE] \`sandbox.html\`"
echo "<html><head><style>body,html{padding:0;margin:0;width:100%;height:100%;}iframe{position:absolute;left:0;right:0;top:0;bottom:0;width:100%;height:100%;}</style></head><body><iframe src=\"index.html\" sandbox=\"allow-scripts allow-same-origin\"></body></html>" > ${PREFIX}/sandbox.html
echo "[CREATE] \`kolibri.html\`"
# Kolibri uses these sandbox options
echo "<html><head><style>body,html{padding:0;margin:0;width:100%;height:100%;}iframe{position:absolute;left:0;right:0;top:0;bottom:0;width:100%;height:100%;}</style></head><body><iframe src=\"index.html\" sandbox=\"allow-scripts allow-same-origin\"></body></html>" > ${PREFIX}/kolibri.html
echo "[CREATE] \`rachel-index.php\`"
cp ${ROOT_PATH}/static/rachel-index.php ${PREFIX}/rachel-index.php
sed "s;TITLE;${NAME};" -i ${PREFIX}/rachel-index.php
sed "s;DESCRIPTION;${DESCRIPTION};" -i ${PREFIX}/rachel-index.php
echo "[CREATE] \`flag.png\`"
cp "${ROOT_PATH}/static/code-dot-org-logo-inset.svg" ${PREFIX}/flag.svg
#cp "${ROOT_PATH}/static/code-dot-org-logo-inset.png" ${PREFIX}/flag.png
cp "${CODE_DOT_ORG_REPO_PATH}/dashboard/app/assets/images/logo.png" ${PREFIX}/flag.png
cp ${ROOT_PATH}/static/rachel-index.php ${PREFIX}/rachel-index.php

# Zip it up
echo
echo "Creating \`./dist/${COURSE}/${BUILD_DIR}.zip\` ..."

cd ${PREFIX}/..
mkdir -p ${ROOT_PATH}/dist/${COURSE}
if [ -f ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}.zip ]; then
  echo "[DELETE] \`dist/${COURSE}/${BUILD_DIR}.zip\`"
  rm ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}.zip
fi
echo "[ZIP] \`${PREFIX}\` -> \`dist/${COURSE}/${BUILD_DIR}.zip\`"
zip ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}.zip -qr ${BUILD_DIR}
cd ${ROOT_PATH}/${PREFIX}/zip-root
zip ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}.zip -qg index.html
cd ${ROOT_PATH}

echo
echo "Creating \`./dist/${COURSE}/${BUILD_DIR}_teacher.zip\` ..."
cd ${PREFIX}/..
if [ -f ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}_teacher.zip ]; then
  echo "[DELETE] \`dist/${COURSE}/${BUILD_DIR}_teacher.zip\`"
  rm ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}_teacher.zip
fi
echo "[ZIP] \`${PREFIX}\` -> \`dist/${COURSE}/${BUILD_DIR}_teacher.zip\`"
zip ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}_teacher.zip -qr ${BUILD_DIR}
cd ${ROOT_PATH}/${PREFIX}/zip-root-teacher
zip ${ROOT_PATH}/dist/${COURSE}/${BUILD_DIR}_teacher.zip -qg index.html
cd ${ROOT_PATH}

echo ""
echo "Done."
echo ""

echo "ls dist/${COURSE}/${BUILD_DIR}.zip -al"
ls dist/${COURSE}/${BUILD_DIR}.zip -al
