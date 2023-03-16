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
if [[ -z "${USE_REMOTE}" ]]; then
  STUDIO_DOMAIN=http://localhost-studio.code.org:3000
  MAIN_DOMAIN=http://localhost.code.org:3000
  DOMAINS=localhost-studio.code.org,localhost.code.org
  EXCLUDE_DOMAINS=curriculum.code.org,studio.code.org,videos.code.org
  BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:5}
  BASE_MAIN_DOMAIN=${MAIN_DOMAIN:5}
else
  STUDIO_DOMAIN=https://studio.code.org
  MAIN_DOMAIN=https://code.org
  DOMAINS=studio.code.org,code.org
  EXCLUDE_DOMAINS=curriculum.code.org,videos.code.org
  BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:6}
  BASE_MAIN_DOMAIN=${MAIN_DOMAIN:6}
fi

# These are content domains. They must be our production sites since the
# crawler will not be able to access the AWS buckets themselves.
CURRICULUM_DOMAIN=https://curriculum.code.org
VIDEO_DOMAIN=http://videos.code.org
IMAGE_DOMAIN=http://images.code.org
VIDEO_SSL_DOMAIN=https://videos.code.org
IMAGE_SSL_DOMAIN=https://images.code.org
TTS_DOMAIN=https://tts.code.org

# Some links are in the form `//localhost-studio.code.org:3000`, etc
BASE_CURRICULUM_DOMAIN=${CURRICULUM_DOMAIN:6}
BASE_VIDEO_DOMAIN=${VIDEO_DOMAIN:5}
BASE_IMAGE_DOMAIN=${IMAGE_DOMAIN:5}
BASE_TTS_DOMAIN=${VIDEO_DOMAIN:6}

# Create the build path. This contains the crawled pages.
mkdir -p build

# The build directory will have a `tmp` path which contains the pages
# 'in-flight' before they are placed in locale-specific places.
BUILD_DIR=${COURSE}
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

  SESSION="--load-cookies ${SESSION_COOKIE}"
fi

# The 'LOCALE' variable specifically crawls just one locale. So, it
# overrides the locale list.
if [[ ! -z "${LOCALE}" ]]; then
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
  wget ${SESSION} --directory-prefix ${PREFIX} ${1} ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4
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

  # Replace any '?' or '=' with '-'
  filename=${filename//\?/-}
  filename=${filename//\=/-}

  mkdir -p "${SHARED}/${dir}"
  mkdir -p "${PREFIX}/${dir}"

  wget ${SESSION} --directory-prefix ${SHARED} -nc -O ${SHARED}/${dir}/${filename} ${1} ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4

  if [ ! -e ${PREFIX}/${dir}/${filename} ]; then
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
#   # We expect '${video_file}' to be something like:
#   # "blah/videos/youtube/Debugging_Global_vs._Local_Variables-Vlj1_X474to.mp4"
download_youtube() {
  url=${1}

  echo "[YTDL] Getting youtube video: ${url} ..."

  # Ensure we have the youtube-dl program
  mkdir -p ${ROOT_PATH}/bin
  if [ ! -e ${ROOT_PATH}/bin/youtube-dl ]; then
    echo "Getting 'youtube-dl'"
    wget ${YOUTUBE_DL_RELEASE_URL} -O ${ROOT_PATH}/bin/youtube-dl 2> /dev/null > /dev/null
    chmod a+rx ${ROOT_PATH}/bin/youtube-dl
    echo "Done."
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
    mkdir -p ${PREFIX}/../videos/youtube
    if [ ! -e "${PREFIX}/../videos/youtube/$(basename "${video_path}")" ]; then
      cp "${video_path}" ${PREFIX}/../videos/youtube
      echo "Copied $(basename "${video_path}") to module."
    else
      echo "Video file $(basename "${video_path}") already exists in module."
    fi
  else
    echo "WARNING: could not download youtube video: ${url}"
  fi
}

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

  # Ensure that references to the main domain are also relative links
  sed "s;${MAIN_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_MAIN_DOMAIN};${replace};gi" -i ${path}

  # Ensure that references to the curriculum domain are also relative links
  sed "s;${CURRICULUM_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_CURRICULUM_DOMAIN};${replace};gi" -i ${path}

  # All other video sources have to be truncated, too
  sed "s;${VIDEO_DOMAIN};${replace};gi" -i ${path}
  sed "s;${VIDEO_SSL_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_VIDEO_DOMAIN};${replace};gi" -i ${path}

  # All other image sources have to be truncated, too
  sed "s;${IMAGE_DOMAIN};${replace};gi" -i ${path}
  sed "s;${IMAGE_SSL_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_IMAGE_DOMAIN};${replace};gi" -i ${path}

  # All tts content should also redirect
  sed "s;${TTS_DOMAIN};${replace};gi" -i ${path}
  sed "s;${BASE_TTS_DOMAIN};${replace};gi" -i ${path}

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

  # Rewrite finish link in each level to work with correct locale
  sed "s;\(finishLink\"\s*:\s*\"[^\"]\+\)\";\1.${replace_locale}.html\";gi" -i ${path}

  # Finally and brutally fix any remaining absolute pathed stuff
  # (this breaks the data-appoptions JSON for some levels, unfortunately)
  #sed "s;\"/\([^\"]\+[^/\"]\);\"${replace}/\1.html;gi" -i ${path}

  # Do so for 'src' attributes embedded into things like JavaScript sometimes
  # e.g. the download_button.png image for videos is generated on the fly.
  sed "s;src=\"/\([^\"]\+[^/\"]\);src=\"${replace}/\1.html;gi" -i ${path}
}

# Determine if this is a full Course (multiple lessons) or a single Lesson
# It is a single lesson if LESSON is provided, otherwise, we determine the
# number of lessons and iterate
IS_COURSE=
if [[ ! -z "${LESSON}" ]]; then
  LESSONS=${LESSON}
else
  # Crawl Course page
  echo "Crawling ${COURSE}..."

  IS_COURSE=1
  COURSE_URL="${STUDIO_DOMAIN}/s/${COURSE}"

  download "-O ${PREFIX}/../base_course.html -nc" ${COURSE_URL} "${PREFIX}/wget-course.log"
  LESSONS=`grep -ohe "/lessons/[0-9]\+/levels/" ${PREFIX}/../base_course.html | sed -e "s;/lessons/;;" | sed -e "s;/levels/;;" | sort -n | uniq`

  download "--domains=${DOMAINS} -nc --page-requisites --convert-links --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=${EXCLUDE_DOMAINS}" "${COURSE_URL} https://code.org/tos https://code.org/privacy" "${PREFIX}/wget-course.log"

  fixup "${PREFIX}/s/${COURSE}.html" ".."
  fixup "${PREFIX}/tos.html" "."
  fixup "${PREFIX}/privacy.html" "."

  echo ""
fi

FINISH_LINK=
LESSON_LEVELS=
LEVEL_URLS=
for LESSON in ${LESSONS}
do
  # Crawl initial page for the lesson
  echo "Crawling ${COURSE}/lessons/${LESSON}/levels/{position}..."
  download "-O ${PREFIX}/../base_${LESSON}.html -nc" "${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/1" "${PREFIX}/wget-levels.log"

  # Negotiate which locales we want to crawl. If the LOCALES variable is
  # specified, those locales are crawled and placed in the distribution.
  # However, if nothing is specified, all locales are downloaded that the site
  # lists in the locale dropdown.
  if [[ -z "${LOCALES}" ]]; then
    SITE_LOCALES=`cat ${PREFIX}/../base_${LESSON}.html | grep -e "i18nDropdown\":" | grep -ohe "value%3D%22[^%]\+" | sed -u 's;value%3D%22;;'`

    # Ensure that LOCALES is treated as an array and get the 'initial' locale as
    # the first item in that list.
    LOCALES=(${SITE_LOCALES})
    STARTING_LOCALE=${LOCALES[0]}
  fi

  # Determine the number of levels
  LEVELS=`grep ${PREFIX}/../base_${LESSON}.html -ohe "levels/[0-9]\+\"" | sed -u "s;levels/;;" | sed -u "s;\";;" | sort -n | tail -n1`
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

  for (( i=1; i<=${LEVELS}; i++ ))
  do
    LEVEL_URLS="${LEVEL_URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i} "
  done

  # If we haven't pulled this via the course page, pull the privacy/tos pages too
  if [[ -z "${IS_COURSE}" ]]; then
    LEVEL_URLS="${LEVEL_URLS}https://code.org/tos https://code.org/privacy "
  fi
done
LESSON_LEVELS=(${LESSON_LEVELS})

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

  download "--domains=${DOMAINS} -nc --page-requisites --convert-links --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=${EXCLUDE_DOMAINS}" "${LEVEL_URLS} ${FINISH_LINK}" "${PREFIX}/wget-levels.log"

  if [[ -z "${IS_COURSE}" ]]; then
    echo ""
    echo "Fixing up privacy/tos pages..."
    fixup "${PREFIX}/tos.html" "."
    fixup "${PREFIX}/privacy.html" "."
  fi

  echo ""
  echo "Downloading other pages..."

  for url in ${URLS}
  do
    dir=$(dirname "${url}")
    mkdir -p ${PREFIX}/${dir}

    download "--domains=${DOMAINS} --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-other.log"
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
    download "-O videos/${dir}/${filename} -nc --tries=2" ${VIDEO_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-videos.log"
    cp videos/${dir}/${filename} ${PREFIX}/${dir}/${filename}
  done

  FIXUP_PATHS=
  j=0
  for LESSON in ${LESSONS}
  do
    LEVELS=${LESSON_LEVELS[j]}
    j=$((j + 1))
    echo ""
    echo "Analyzing lesson ${LESSON} with ${LEVELS} levels."
    echo ""
    echo "Gathering videos..."

    URLS=
    VIDEOS=
    YT_URLS=
    for (( i=1; i<=${LEVELS}; i++ ))
    do
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      video=`grep ${path} -ohe "data-download\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2 | sed -u "s;${VIDEO_DOMAIN}/;;" | sed -u "s;https://videos.code.org/;;"`
      if [[ ! -z "${video/$'\n'/}" ]]; then
        echo "[FOUND] \`${video}\`"
        VIDEOS="${VIDEOS} ${video}"

        note=`grep ${path} -ohe "data-key\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2`
        echo "[FOUND] \`notes/${note}\`"
        URLS="${URLS} notes/${note}"
      fi

      # Find youtube links
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      videos=`grep ${path} -ohe "youtube.com/watch[^\")]\+"`
      for yt_url in ${videos}; do
        echo "[FOUND] \`${yt_url}\`"
        YT_URLS="${YT_URLS} ${yt_url}"
      done
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
      download "-O videos/${dir}/${filename} -nc --tries=2" ${VIDEO_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-videos.log"
      cp videos/${dir}/${filename} ${PREFIX}/${dir}/${filename}
    done

    for yt_url in ${YT_URLS}; do
      download_youtube "${yt_url}"

      YOUTUBE_VIDEOS="${video_id}=${video_url} ${YOUTUBE_VIDEOS}"
    done

    # Other dynamic content we want wholesale downloaded (transcripts for the videos)

    echo ""
    echo "Downloading other pages..."

    for url in ${URLS}
    do
      dir=$(dirname "${url}")
      mkdir -p ${PREFIX}/${dir}

      download "--domains=${DOMAINS} --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-other.log"
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
        echo "OK? ${url}"

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
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
      download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done

    for (( i=1; i<=${LEVELS}; i++ ))
    do
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      ASSETS=`grep ${path} -ohe "appOptions\s*=\s*\({.\+\)\s*;\s*$" | sed -u "s;appOptions\s*=\s*;;" | sed -u "s/;$//" | grep -ohe "http[s]://[^ )\\\\\"\']\+"`

      for url in ${ASSETS}
      do
        domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
        path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
        dir=$(dirname "${path}")
        filename=$(basename "${path}")

        if [[ ${domain} == "studio.code.org" || ${domain} == "tts.code.org" || ${domain} == "images.code.org" ]]; then
          mkdir -p ${PREFIX}/${dir}
          download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
        fi
      done

      # Gather helper libraries
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      ASSETS=`grep ${path} -ohe "helperLibraries\"\s*:\s*\[[^]]\+\]" | cut -d ":" -f2 | sed -u "s;\[\|\"\|\];;g" | sed -u "s;,; ;g"`
      for url in ${ASSETS}
      do
        LIBRARIES="${LIBRARIES} ${url}"
      done

      # Gather static assets from the base html, too
      # These are any api urls of the form \"/api/v1/etc\"
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      ASSETS=`grep ${path} -ohe "[\]\"/api/v1/[^\"]\+[\]\"" | sed -u "s;[\]\"/\?;;g"`
      for url in ${ASSETS}
      do
        dir=$(dirname "${url}")
        filename=$(basename "${url}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
      done

      # wget does not find stylesheets that are in <link> tags inside the <body>
      # ... mostly because that makes such little sense.
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      ASSETS=`grep ${path} -e "<[lL][iI][nN][kK].\+[hH][rR][eE][fF]\s*=\s*\"/" | grep -ohe "[hH][rR][eE][fF]\s*=\s*\"[^\"]\+" | sed -u "s;[hH][rR][eE][fF]\s*=\s*\"/;;"`
      for url in ${ASSETS}
      do
        dir=$(dirname "${url}")
        filename=$(basename "${url}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
      done

      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      ASSETS=`grep ${path} -e "<[lL][iI][nN][kK].\+[hH][rR][eE][fF]\s*=\s*\"${STUDIO_DOMAIN}" | grep -ohe "[hH][rR][eE][fF]\s*=\s*\"[^\"]\+" | sed -u "s;[hH][rR][eE][fF]\s*=\s*\"${STUDIO_DOMAIN}/;;"`
      for url in ${ASSETS}
      do
        domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
        path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
        dir=$(dirname "${path}")
        filename=$(basename "${path}")

        mkdir -p ${PREFIX}/${dir}
        download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
      done

      # Get ID of application this level represents ('craft', 'dance', etc)
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      APP_ID=`grep ${path} -ohe "app\s*:\s*['\"][a-z][a-z][^\"']*['\"]" | sed -u "s;app\s*:\s*['\"]\([^'\"]\+\)['\"];\1;" | tail -n1`
      if [ ! -z "${APP_ID}" ]; then
        echo "[DETECTED] Found '${APP_ID}' app via ${path}"

        # We probably want the skins and media paths for this app type
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/${APP_ID}"
        fi
        if [ -d "${CODE_DOT_ORG_REPO_PATH}/dashboard/public/blockly/media/skins/${APP_ID}" ]; then
          PATHS="${PATHS} blockly/media/skins/${APP_ID}"
        fi
      fi

      # Get Skin, if any
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      SKIN_ID=`grep ${path} -ohe "skin['\"]\s*:\s*['\"][a-z][a-z][^\"']*['\"]" | sed -u "s;skin['\"]\s*:\s*['\"]\([^'\"]\+\)['\"];\1;" | tail -n1`
      if [ ! -z "${SKIN_ID}" ]; then
        echo "[DETECTED] Found '${SKIN_ID}' skin via ${path}"

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
    for (( i=1; i<=${LEVELS}; i++ ))
    do
      path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
      FIXUP_PATHS="${FIXUP_PATHS} ${path}"
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
  echo "Fixing links in pages..."

  for path in ${FIXUP_PATHS}
  do
    fixup ${path} "../../../../.." ${locale}
  done

  echo ""
  echo "Gathering assets from css..."

  # Gather assets from CSS
  CSS=`ls ${PREFIX}/assets/css/*.css`
  for css in ${CSS}
  do
    ASSETS=`grep ${css} -e "url(\"${STUDIO_DOMAIN}" | grep -ohe "url(\"${STUDIO_DOMAIN}[^\"]\+" | sed -u "s;url(\"${STUDIO_DOMAIN}/;;"`
    for url in ${ASSETS}
    do
      domain=`echo ${url} | sed -u "s;http[s]\?://\([^/]\+\).\+;\1;"`
      path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
      dir=$(dirname "${path}")
      filename=$(basename "${path}")

      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
    done
  done

  # Copy over webpacked chunks

  echo ""
  echo "Copying webpack chunks..."

  for js in `ls ${CODE_DOT_ORG_REPO_PATH}/apps/build/package/js/{1,2,3,4,5,6,7,8,9}*wp*.min.js 2> /dev/null`
  do
    dir=$(dirname "${js}")
    filename=$(basename "${js}")

    mkdir -p ${PREFIX}/assets/js
    echo "[COPYING] \`${PREFIX}/assets/js/${filename}\`"
    cp ${js} ${PREFIX}/assets/js/.
  done

  # And any strange placeholder graphics built in our apps chain
  for img in `ls ${CODE_DOT_ORG_REPO_PATH}/apps/build/package/js/*.{jpg,png} 2> /dev/null`
  do
    dir=$(dirname "${img}")
    filename=$(basename "${img}")

    mkdir -p ${PREFIX}/assets/js
    echo "[COPYING] \`${PREFIX}/assets/js/${filename}\`"
    cp ${img} ${PREFIX}/assets/js/.
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

  FIXUP_PATHS=
  # Also add the javascript (and assets found within)
  for js in `ls ${PREFIX}/assets/js/*.js`
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
      download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-assets.log"
    done
    sed "s;https://contentstorage.onenote.office.net;../../../../..;gi" -i ${js}

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
      download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" https://studio.code.org/${url} "${PREFIX}/wget-assets.log"
    done
  done

  echo ""
  echo "Fixing links in pages..."

  for path in ${FIXUP_PATHS}
  do
    fixup ${path} "../../../../.." ${locale}
  done

  # Add some of the extra silly things
  mkdir -p ${PREFIX}/s/${COURSE}/hidden_lessons
  echo "[]" > ${PREFIX}/s/${COURSE}/hidden_lessons

  # Move the 'levels' to a locale-specific place
  mv ${PREFIX}/s ${PREFIX}/../s-${locale}

  # Move the video transcripts to a locale-specific place
  mv ${PREFIX}/notes ${PREFIX}/../notes-${locale}

  # For all content, move it over to the resulting directory if it doesn't
  # already exist
  for item in `ls ${PREFIX}`; do
    if [[ ! -e ${PREFIX}/../${item} ]]; then
      mv ${PREFIX}/${item} ${PREFIX}/../${item}
    fi
  done

  # Move any new css files
  for item in `ls ${PREFIX}/assets/css`; do
    if [[ ! -e ${PREFIX}/../assets/css/${item} ]]; then
      mv ${PREFIX}/assets/css/${item} ${PREFIX}/../assets/css/${item}
    fi
  done

  # Move any new js files
  for item in `ls ${PREFIX}/assets/js`; do
    if [[ ! -e ${PREFIX}/../assets/js/${item} ]]; then
      mv ${PREFIX}/assets/js/${item} ${PREFIX}/../assets/js/${item}
    fi
  done

  # Remove our temporary space so we can do it again
  rm -rf ${PREFIX}
  mkdir -p ${PREFIX}
done

# Point to our resulting build path
PREFIX=build/${BUILD_DIR}

# Add shims

echo ""
echo "Adding JS/CSS shims..."

DEST="${PREFIX}/assets/application*.js ${PREFIX}/js/jquery.min*.js ${PREFIX}/assets/js/webpack*.js ${PREFIX}/assets/js/vendor*.js ${PREFIX}/assets/js/essential*.js ${PREFIX}/assets/js/common*.js ${PREFIX}/assets/js/code-studio-*.js"
DEST=`ls ${DEST}`

for js in ${DEST}
do
  path=`echo ${js} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] \`shims/shim.js\` -> \`${path}\`"

    # Create a new file with the shims prepended
    cat shims/shim.js ${js} > ${js}.new

    # Updates to add LOCALES
    LOCALE_ARRAY=
    for locale in "${LOCALES[@]}"; do
      if [[ -z "${YOUTUBE_VIDEOS_ARRAY}" ]]; then
        LOCALE_ARRAY="${locale}"
      else
        LOCALE_ARRAY="${locale}\", \"${LOCALE_ARRAY}"
      fi
    done
    sed "s;%LOCALES%;${LOCALE_ARRAY};" -i ${js}.new

    # Updates to add YOUTUBE_VIDEOS
    YOUTUBE_VIDEOS_ARRAY=
    for yt_tuple in ${YOUTUBE_VIDEOS}; do
      if [[ -z "${YOUTUBE_VIDEOS_ARRAY}" ]]; then
        YOUTUBE_VIDEOS_ARRAY="${yt_tuple}"
      else
        YOUTUBE_VIDEOS_ARRAY="${yt_tuple}\", \"${YOUTUBE_VIDEOS_ARRAY}"
      fi
    done
    sed "s;%YOUTUBE_VIDEOS%;${YOUTUBE_VIDEOS_ARRAY};" -i ${js}.new

    # Commit it
    mv ${js}.new ${js}
  fi
done

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
    path=`echo ${url} | sed -u "s;http[s]\?://[^/]\+/\+;;"`
    dir=$(dirname "${path}")
    filename=$(basename "${path}")

    if [[ ${domain} == "studio.code.org" || ${domain} == "tts.code.org" || ${domain} == "images.code.org" ]]; then
      mkdir -p ${PREFIX}/${dir}
      download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-parsed-static.log"
    fi
  done
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

if [[ ! -z "${LIBRARIES/$'\n'/}" ]]; then
  echo ""
  echo "Copying helper libraries..."

  for url in ${LIBRARIES}
  do
    url="libraries/${url}"
    dir=$(dirname "${url}")
    filename=$(basename "${url}")

    mkdir -p ${PREFIX}/${dir}
    download_shared "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
  done
else
  echo ""
  echo "No helper libraries."
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
  cp restricted/${dir}/${filename} ${PREFIX}/${dir}/${filename}
done

# Repair stylesheets

echo ""
echo "Repairing stylesheets..."

CSS=`ls ${PREFIX}/assets/css/*.css`
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
if [[ -z "${after}" ]]; then
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
echo "[CREATE] \`index.html\`"
if [[ -z "${IS_COURSE}" ]]; then
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=s-${STARTING_LOCALE}/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/index.html
else
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=s-${STARTING_LOCALE}/${COURSE}.html\" />" > ${PREFIX}/index.html
fi
echo "[CREATE] \`index.html\`"
mkdir -p ${PREFIX}/zip-root
if [[ -z "${IS_COURSE}" ]]; then
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/zip-root/index.html
else
  echo "<meta http-equiv=\"refresh\" content=\"0; URL=${BUILD_DIR}/s-${STARTING_LOCALE}/${COURSE}.html\" />" > ${PREFIX}/zip-root/index.html
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

echo ""
echo "Done."
echo ""

echo "ls dist/${COURSE}/${BUILD_DIR}.zip -al"
ls dist/${COURSE}/${BUILD_DIR}.zip -al
