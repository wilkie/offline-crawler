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

# Where the code-dot-org repo is
CODE_DOT_ORG_REPO_PATH=../code-dot-org

if [ ! -d ${CODE_DOT_ORG_REPO_PATH} ]; then
  echo "Error: Cannot find the 'code-dot-org' repo in \${CODE_DOT_ORG_REPO_PATH} as ${CODE_DOT_ORG_REPO_PATH}."
  exit 1
else
  echo "Using assets found locally in $(realpath ${CODE_DOT_ORG_REPO_PATH})."
fi

STUDIO_DOMAIN=http://localhost-studio.code.org:3000
MAIN_DOMAIN=http://localhost.code.org:3000
CURRICULUM_DOMAIN=https://curriculum.code.org
VIDEO_DOMAIN=http://videos.code.org

# Some links are in the form `//localhost-studio.code.org:3000`, etc
BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:5}
BASE_MAIN_DOMAIN=${MAIN_DOMAIN:5}
BASE_CURRICULUM_DOMAIN=${CURRICULUM_DOMAIN:6}
BASE_VIDEO_DOMAIN=${VIDEO_DOMAIN:5}

mkdir -p build
PREFIX=build/${COURSE}_${LESSON}
# Remove old path
if [ -d ${PREFIX} ]; then
  rm -r ${PREFIX}
fi

mkdir -p ${PREFIX}
touch ${PREFIX}/wget_log.txt

# This function invokes wget
download() {
  wget ${1} ${2} |& tee -a ${3} | grep --line-buffered -ohe "[0-9]--\(\s\s.\+\)$" -e"Converting links in \(.\+\)$" | sed -u "s/in /[CONVERT-LINKS] /" | sed -u "s/--\s/ x [GET]/" | cut -d " " -f3,4
}

# Crawl initial page
echo "Crawling ${COURSE}/lessons/${LESSON}/levels/{position}..."
download "-O ${PREFIX}/base.html -nc" "${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/1" "${PREFIX}/wget-levels.log"

# Determine the number of levels
LEVELS=`grep ${PREFIX}/base.html -ohe "levels/[0-9]\+\"" | sed -u "s;levels/;;" | sed -u "s;\";;" | sort -n | tail -n1`
LEVELS="${LEVELS/$'\n'/}"

if [[ -z "${LEVELS/$'\n'/}" ]]; then
  echo "Error: Cannot determine the number of levels."
  exit 1
fi

LEVEL_URLS=
for (( i=1; i<=${LEVELS}; i++ ))
do
  LEVEL_URLS="${LEVEL_URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i} "
done

echo ""
echo "Downloading ${LEVELS} levels..."

download "--domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=curriculum.code.org,studio.code.org,videos.code.org" "${LEVEL_URLS}" "${PREFIX}/wget-levels.log"

echo ""
echo "Gathering videos..."

for (( i=1; i<=${LEVELS}; i++ ))
do
  path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
  video=`grep ${path} -ohe "data-download\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2 | sed -u "s;${VIDEO_DOMAIN}/;;" | sed -u "s;https://videos.code.org/;;"`
  if [[ ! -z "${video/$'\n'/}" ]]; then
    echo "[FOUND] ${video}"
    VIDEOS="${VIDEOS} ${video}"

    note=`grep ${path} -ohe "data-key\s*=\s*['\"][^'\"]\+['\"]" | cut -d '"' -f2`
    echo "[FOUND] notes/${note}"
    URLS="${URLS} notes/${note}"
  fi
done

# Videos

echo ""
echo "Downloading any videos..."

for url in ${VIDEOS}
do
  dir=$(dirname "${url}")
  filename=$(basename "${url}")
  mkdir -p ${PREFIX}/${dir}
  mkdir -p videos/${dir}
  if [ -f videos/${dir}/${filename} ]; then
    echo "[EXISTS] ${VIDEO_DOMAIN}/${dir}/${filename}"
  fi
  download "-O videos/${dir}/${filename} -nc --tries=2" ${VIDEO_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-videos.log"
  cp videos/${dir}/${filename} ${PREFIX}/${dir}/${filename}
done

# Other dynamic content we want wholesale downloaded (transcripts for the videos)

echo ""
echo "Downloading other pages..."

for url in ${URLS}
do
  dir=$(dirname "${url}")
  mkdir -p ${PREFIX}/${dir}

  download "--domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=studio.code.org,videos.code.org" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-other.log"
done

echo ""
echo "Gathering assets from levels..."

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
      download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${url} "${PREFIX}/wget-assets.log"
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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
  done
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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-assets.log"
  done
done

# Fix-ups
# video transcripts reference image assets relative to itself...
# we must move this to be relative to the level
if [ -d ${PREFIX}/assets/notes ]; then
  echo ""
  echo "Fixing video transcripts..."

  echo "[MOVE] ./assets/notes -> ./s/${COURSE}/lessons/${LESSON}/assets/."
  mkdir -p ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets
  mv ${PREFIX}/assets/notes ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets/.
fi

# Copy over webpacked chunks

echo ""
echo "Copying webpack chunks..."

for js in `ls ${CODE_DOT_ORG_REPO_PATH}/apps/build/package/js/{1,2,3,4,5,6,7,8,9}*wp*.min.js 2> /dev/null`
do
  dir=$(dirname "${js}")
  filename=$(basename "${js}")

  mkdir -p ${PREFIX}/assets/js
  echo "[COPYING] ${PREFIX}/assets/js/${filename}"
  cp ${js} ${PREFIX}/assets/js/.
done

# Individual fix-ups
FIXUP_PATHS=

for (( i=1; i<=${LEVELS}; i++ ))
do
  path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
  FIXUP_PATHS="${FIXUP_PATHS} ${path}"
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
libraries="${libraries}FDSAASDF"

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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" https://studio.code.org/${url} "${PREFIX}/wget-assets.log"
  done
done

echo ""
echo "Fixing links in pages..."

for path in ${FIXUP_PATHS}
do
  echo "[FIXUP] ${path}"

  # Replace Blockly.assetUrl paths appropriately
  sed "s;Blockly.assetUrl(\"\([^\"]\+\)\");\"${STUDIO_DOMAIN}/blockly/\1\";g" -i ${path}

  # Ensure that references to the main domain are also relative links
  sed "s;${MAIN_DOMAIN};../../../../..;gi" -i ${path}
  sed "s;${BASE_MAIN_DOMAIN};../../../../..;gi" -i ${path}

  # Ensure that references to the curriculum domain are also relative links
  sed "s;${CURRICULUM_DOMAIN};../../../../..;gi" -i ${path}
  sed "s;${BASE_CURRICULUM_DOMAIN};../../../../..;gi" -i ${path}

  # All other video source has to be truncated, too
  sed "s;${VIDEO_DOMAIN};../../../../..;gi" -i ${path}
  sed "s;${BASE_VIDEO_DOMAIN};../../../../..;gi" -i ${path}

  # For some reason, these don't all get converted either
  sed "s;${STUDIO_DOMAIN};../../../../..;gi" -i ${path}
  sed "s;${BASE_STUDIO_DOMAIN};../../../../..;gi" -i ${path}

  # The video 'poster' has an absolute path and not picked up by the crawler
  sed "s;poster=\"/;poster=\";gi" -i ${path}

  # Fix the 'continue' button (and other metadata fields to use relative paths)
  KEYS="nextLevelUrl level_path redirect"
  for key in ${KEYS}
  do
    # Sigh to all of this.
    # Fix normal "key":"/s/blah/1" -> "key":"../../../../../s/blah/1.html"
    sed "s;${key}\":\"\([^\"]\+\);${key}\":\"../../../../..\1.html;gi" -i ${path}
    # Fix slash escaped \"key\":\"/s/blah/1, etc
    sed "s,${key}\\\\\":\\\\\"\([^\\]\+\),${key}\\\\\":\\\\\"../../../../..\1.html,gi" -i ${path}
    # Fix html escaped &quot;key&quot;:&quot;/s/blah/1, etc
    sed "s,${key}\&quot;:\&quot;\([^\&]\+\),${key}\&quot;:\&quot;../../../../..\1.html,gi" -i ${path}
    # Fix slash escaped html escaped \&quot;key\&quot;:\&quot;/s/blah/1, etc
    sed "s,${key}\\\\\&quot;:\\\\\&quot;\([^\\]\+\),${key}\\\\\&quot;:\\\\\&quot;../../../../..\1.html,gi" -i ${path}
  done

  # Finally and brutally fix any remaining absolute pathed stuff
  # (this breaks the data-appoptions JSON for some levels, unfortunately)
  #sed "s;\"/\([^\"]\+[^/\"]\);\"../../../../../\1.html;gi" -i ${path}
done

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

DEST="assets/css/common.css"

for css in ${DEST}
do
  path=`echo ${PREFIX}/${css} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "[PREPEND] shim.css -> ${path}"
    cat shim.css ${PREFIX}/${css} > ${PREFIX}/${css}.new
    mv ${PREFIX}/${css}.new ${PREFIX}/${css}
  fi
done

# Repair stylesheets

echo ""
echo "Repairing stylesheets..."

CSS=`ls ${PREFIX}/assets/css/*.css`
for css in ${CSS}
do
  echo "[CONVERT-LINKS] ${css}"
  sed "s;${STUDIO_DOMAIN};../..;" -i ${css}
done

# Repair firehose
sed "s/return \(.\)\.putRecord/return null; return \1.putRecord/" -i ${PREFIX}/assets/js/code-studio-co*.js

# Copy in necessary other static files

echo ""
echo "Copying static data..."

cp -r static/api ${PREFIX}/.
cp -r static/dashboardapi ${PREFIX}/.
cp -r static/levels ${PREFIX}/.

# Copy in static content
for static in ${STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  download "-O ${PREFIX}/${dir}/${filename} --tries=1 -nc --timeout=20" ${STUDIO_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-static.log"
  if [ $? -ne 0 ]; then
    # If that failed, try the main domain instead of the studio domain
    rm ${PREFIX}/${dir}/${filename}
    download "-O ${PREFIX}/${dir}/${filename} --tries=1 -nc --timeout=20" ${MAIN_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-static.log"

    if [ $? -ne 0 ]; then
      # If THAT failed, try the live domain instead of any local domains
      rm ${PREFIX}/${dir}/${filename}
      download "-O ${PREFIX}/${dir}/${filename} --tries=1 -nc --timeout=20" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-static.log"
    fi
  fi
done

# Copy whole directories
for path in ${PATHS}
do
  dir=$(dirname "${path}")
  mkdir -p ${PREFIX}/${dir}
  echo "[COPY] ${path}"
  cp -r "../code-dot-org/dashboard/public/${path}" ${PREFIX}/${dir}/.
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
      download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" ${url} "${PREFIX}/wget-parsed-static.log"
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
  download "-O ${PREFIX}/${dir}/${filename} --tries=1 -nc" ${CURRICULUM_DOMAIN}/${dir}/${filename} "${PREFIX}/wget-curriculum.log"
done

if [[ ! -z "${RESTRICTED/$'\n'/}" ]]; then
  echo ""
  echo "Copying restricted data..."

  # Remove lingering cookie jar
  if [ -f cookies.jar ]; then
    echo "[DELETE] cookies.jar"
    rm -f cookies.jar
  fi

  if [ -f signed-cookies.jar ]; then
    echo "[DELETE] signed-cookies.jar"
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
    download "--reject-regex=\"[.]dmg$|[.]exe$|[.]mp4$\" --exclude-domains=videos.code.org -nc -O ${PREFIX}/${dir}/${filename}" https://studio.code.org/${dir}/${filename} "${PREFIX}/wget-assets.log"
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
    echo "[EXISTS] https://studio.code.org/${dir}/${filename}"
  fi

  download "--load-cookies signed-cookies.jar -O restricted/${dir}/${filename} --tries=1 -nc" "https://studio.code.org/${dir}/${filename}" "${PREFIX}/wget-restricted.log"
  cp restricted/${dir}/${filename} ${PREFIX}/${dir}/${filename}
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
echo "[CREATE] index.html"
echo "<meta http-equiv=\"refresh\" content=\"0; URL=s/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/index.html
echo "[CREATE] sandbox.html"
echo "<html><head><style>body,html{padding:0;margin:0;width:100%;height:100%;}iframe{position:absolute;left:0;right:0;top:0;bottom:0;width:100%;height:100%;}</style></head><body><iframe src=\"index.html\" sandbox=\"allow-scripts allow-same-origin\"></body></html>" > ${PREFIX}/sandbox.html
echo "[CREATE] kolibri.html"
# Kolibri uses these sandbox options
echo "<html><head><style>body,html{padding:0;margin:0;width:100%;height:100%;}iframe{position:absolute;left:0;right:0;top:0;bottom:0;width:100%;height:100%;}</style></head><body><iframe src=\"index.html\" sandbox=\"allow-scripts allow-same-origin\"></body></html>" > ${PREFIX}/kolibri.html

# Zip it up
echo
echo "Creating ./dist/${COURSE}/${COURSE}_${LESSON}.zip ..."

cd ${PREFIX}
mkdir -p ../../dist/${COURSE}
if [ -f ../../dist/${COURSE}/${COURSE}_${LESSON}.zip ]; then
  echo "[DELETE] dist/${COURSE}/${COURSE}_${LESSON}.zip"
  rm ../../dist/${COURSE}/${COURSE}_${LESSON}.zip
fi
echo "[ZIP] ${PREFIX} -> dist/${COURSE}/${COURSE}_${LESSON}.zip"
zip ../../dist/${COURSE}/${COURSE}_${LESSON}.zip -qr .
cd - > /dev/null 2> /dev/null

echo ""
echo "Done."
echo ""

echo "ls dist/${COURSE}/${COURSE}_${LESSON}.zip -al"
ls dist/${COURSE}/${COURSE}_${LESSON}.zip -al
