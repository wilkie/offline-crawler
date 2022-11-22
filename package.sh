#!/bin/bash

# This is generally best run against a development server that is using the
# minimized JS assets. Therefore, locals.yml has:
#
#   optimize_webpack_assets: true
#   use_my_apps: true
#
# These above settings set. And then running yarn build:dist in `apps`

echo "Starting crawler..."

if [[ -z "${MODULE}" ]]; then
  MODULE=$1
fi

if [ -f ./modules/${MODULE}.sh ]; then
  source ./modules/${MODULE}.sh
else
  if [[ -z "${MODULE}" ]]; then
    echo "Error: No module specified."
  else
    echo "Error: Cannot find '${MODULE}.sh' in './modules'."
  fi
  echo "Usage: ./package.sh \${MODULE}"
  exit 1
fi

echo "Crawling ${COURSE}/lessons/${LESSON}/levels/1...${LEVELS}"

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

LEVEL_URLS=
for (( i=1; i<=${LEVELS}; i++ ))
do
  LEVEL_URLS="${LEVEL_URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i} "
done

mkdir -p build
PREFIX=build/${COURSE}_${LESSON}

# Remove old path
if [ -d ${PREFIX} ]; then
  rm -r ${PREFIX}
fi

wget --domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex="[.]dmg$|[.]exe$|[.]mp4$" --exclude-domains=curriculum.code.org,studio.code.org,video.code.org ${LEVEL_URLS}

# Other dynamic content we want wholesale downloaded (transcripts for the videos)

for url in ${URLS}
do
  dir=$(dirname "${url}")
  mkdir -p ${PREFIX}/${dir}
  wget --domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex="[.]dmg$|[.]exe$|[.]mp4$" --exclude-domains=studio.code.org,video.code.org ${STUDIO_DOMAIN}/${url}
done

# Fix-ups
# video transcripts reference image assets relative to itself...
# we must move this to be relative to the level
if [ -d ${PREFIX}/assets/notes ]; then
  mkdir -p ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets
  mv ${PREFIX}/assets/notes ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets/.
fi

# Individual fix-ups
FIXUP_PATHS=

for (( i=1; i<=${LEVELS}; i++ ))
do
  path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"
  FIXUP_PATHS="${FIXUP_PATHS} ${path}"
done

# Also add the javascript
for js in `ls ${PREFIX}/assets/js/*.js`
do
  FIXUP_PATHS="${FIXUP_PATHS} ${js}"
done

for path in ${FIXUP_PATHS}
do
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

# Videos

for url in ${VIDEOS}
do
  dir=$(dirname "${url}")
  filename=$(basename "${url}")
  mkdir -p ${PREFIX}/${dir}
  mkdir -p videos/${dir}
  wget ${VIDEO_DOMAIN}/${dir}/${filename} -O videos/${dir}/${filename} -nc --tries=2
  cp videos/${dir}/${filename} ${PREFIX}/${dir}/${filename}
done

# Copy over webpacked chunks

for js in `ls ${CODE_DOT_ORG_REPO_PATH}/apps/build/package/js/{1,2,3,4,5,6,7,8,9}*wp*.min.js 2> /dev/null`
do
  mkdir -p ${PREFIX}/assets/js
  cp ${js} ${PREFIX}/assets/js/.
done

# Add shims

DEST="assets/application.js js/jquery.min.js assets/js/essential*.js assets/js/common*.js assets/js/code-studio-*.js"

for js in ${DEST}
do
  path=`echo ${PREFIX}/${js} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "cat shim.js ${path} > ${path}.new"
    cat shim.js ${PREFIX}/${js} > ${PREFIX}/${js}.new
    mv ${PREFIX}/${js}.new ${PREFIX}/${js}
  fi
done

DEST="assets/css/common.css"

for css in ${DEST}
do
  path=`echo ${PREFIX}/${css} 2> /dev/null`
  if [ -f ${path} ]; then
    echo "cat shim.css ${path} > ${path}.new"
    cat shim.css ${PREFIX}/${css} > ${PREFIX}/${css}.new
    mv ${PREFIX}/${css}.new ${PREFIX}/${css}
  fi
done

# Repair stylesheets

CSS=`ls ${PREFIX}/assets/css/*.css`
for css in ${CSS}
do
  sed "s;${STUDIO_DOMAIN};../..;" -i ${css}
done

# Repair firehose
sed "s/return \(.\)\.putRecord/return null; return \1.putRecord/" -i ${PREFIX}/assets/js/code-studio-co*.js

# Copy in necessary other static files

cp -r static/api ${PREFIX}/.
cp -r static/dashboardapi ${PREFIX}/.
cp -r static/levels ${PREFIX}/.

# Copy in static content
for static in ${STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  wget ${STUDIO_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} --tries=1 -nc --timeout=20 || rm ${PREFIX}/${dir}/${filename} && wget ${MAIN_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} --tries=1 -nc || rm ${PREFIX}/${dir}/${filename} && wget https://studio.code.org/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} --tries=1 -nc --timeout=20 
done

# Copy in curriculum static content
for static in ${CURRICULUM_STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  wget ${CURRICULUM_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} --tries=1 -nc
done

# Remove lingering cookie jar
rm -f cookies.jar signed-cookies.jar

# Get signed / restricted content
for static in ${RESTRICTED}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  mkdir -p restricted/${dir}

  if [[ -z "${COOKIES}" ]]; then
    # Get a local user session
    wget --keep-session-cookies --save-cookies cookies.jar --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --header "Host: studio.code.org" --header "Accept-Language: en-US,en;q=0.5" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Pragma: no-cache" --header "Upgrade-Insecure-Requests: 1" --header "DNT: 1" --header "Accept-Encoding: gzip, deflate, br" --header "Cache-Control: no-cache" --header "Connection: keep-alive" https://studio.code.org/s/${COURSE}/lessons/${LESSON}/levels/1

    # Sign the cookies
    wget --keep-session-cookies --load-cookies cookies.jar --save-cookies signed-cookies.jar https://studio.code.org/dashboardapi/sign_cookies -O ${PREFIX}/dashboardapi/sign_cookies

    COOKIES=signed-cookies.jar
  fi

  # Acquire the thing
  wget --load-cookies signed-cookies.jar https://studio.code.org/${dir}/${filename} -O restricted/${dir}/${filename} --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:107.0) Gecko/20100101 Firefox/107.0" --tries=1 -nc
  cp restricted/${dir}/${filename} ${PREFIX}/${dir}/${filename}
done

# Copy whole directories
for path in ${PATHS}
do
  dir=$(dirname "${path}")
  mkdir -p ${PREFIX}/${dir}
  cp -r "../code-dot-org/dashboard/public/${path}" ${PREFIX}/${dir}/.
done

# Perform the 'after' callback
after

# Remove newly created cookie jar
rm -f cookies.jar signed-cookies.jar

# Create an index.html to redirect
echo "<meta http-equiv=\"refresh\" content=\"0; URL=s/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/index.html

# Zip it up
echo
echo "Creating ./dist/${COURSE}/${COURSE}_${LESSON}.zip ..."
cd ${PREFIX}
mkdir -p ../../dist/${COURSE}
if [ -f ../../dist/${COURSE}/${COURSE}_${LESSON}.zip ]; then
  echo "Removing existing zip."
  rm ../../dist/${COURSE}/${COURSE}_${LESSON}.zip
fi
zip ../../dist/${COURSE}/${COURSE}_${LESSON}.zip -qr .
cd - > /dev/null 2> /dev/null
echo "Done."
