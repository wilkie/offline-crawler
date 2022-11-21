#!/bin/bash

COURSE=mc
LESSON=1
LEVELS=14

STUDIO_DOMAIN=http://localhost-studio.code.org:3000
MAIN_DOMAIN=http://localhost.code.org:3000
VIDEO_DOMAIN=http://videos.code.org

# Some links are in the form `//localhost-studio.code.org:3000`, etc
BASE_STUDIO_DOMAIN=${STUDIO_DOMAIN:5}
BASE_MAIN_DOMAIN=${MAIN_DOMAIN:5}
BASE_VIDEO_DOMAIN=${VIDEO_DOMAIN:5}

URLS=
for (( i=1; i<=${LEVELS}; i++ ))
do
  URLS="${URLS}${STUDIO_DOMAIN}/s/${COURSE}/lessons/${LESSON}/levels/${i} "
done

mkdir -p build
PREFIX=build/${COURSE}_${LESSON}

wget --domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --adjust-extension --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex="[.]dmg$|[.]exe$|[.]mp4$" --exclude-domains=studio.code.org,video.code.org ${URLS}

# Other dynamic content we want wholesale downloaded (transcripts for the videos)

URLS="notes/mc_intro notes/mc_repeat notes/mc_if_statements"

for url in ${URLS}
do
  dir=$(dirname "${url}")
  mkdir -p ${PREFIX}/${dir}
  wget --domains=localhost-studio.code.org,localhost.code.org --page-requisites --convert-links --directory-prefix ${PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex="[.]dmg$|[.]exe$|[.]mp4$" --exclude-domains=studio.code.org,video.code.org ${STUDIO_DOMAIN}/${url}
done

# Fix-ups
# mc_intro references image assets relative to itself... we must move this to be relative to the level
mkdir -p ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets
mv ${PREFIX}/assets/notes ${PREFIX}/s/${COURSE}/lessons/${LESSON}/assets/.

# Individual fix-ups
for (( i=1; i<=${LEVELS}; i++ ))
do
  path="${PREFIX}/s/${COURSE}/lessons/${LESSON}/levels/${i}.html"

  # Ensure that references to the main domain are also relative links
  sed "s;${MAIN_DOMAIN};../../../../..;gi" -i ${path}
  sed "s;${BASE_MAIN_DOMAIN};../../../../..;gi" -i ${path}

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

VIDEOS="2015/mc/mc_intro.mp4 2015/mc/mc_repeat.mp4 2015/mc/mc_if_statements.mp4"

for url in ${VIDEOS}
do
  dir=$(dirname "${url}")
  filename=$(basename "${url}")
  mkdir -p ${PREFIX}/${dir}
  wget ${VIDEO_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} -nc
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

STATIC="
blockly/media/skins/craft/music/vignette4-intro.mp3
blockly/media/skins/craft/music/vignette5-shortpiano.mp3
blockly/media/skins/craft/music/vignette2-quiet.mp3
blockly/media/skins/craft/music/vignette3.mp3
blockly/media/skins/craft/music/vignette7-funky-chirps-short.mp3
blockly/media/skins/craft/music/vignette1.mp3
blockly/video-js/video-js.css
blockly/media/click.mp3
blockly/media/delete.mp3
blockly/media/canclosed.png
blockly/media/canopen.png
blockly/media/handopen.cur
shared/images/download_button.png
blockly/media/1x1.gif
api/hour/begin_mc.png"

for static in ${STATIC}
do
  dir=$(dirname "${static}")
  filename=$(basename "${static}")
  mkdir -p ${PREFIX}/${dir}
  wget ${STUDIO_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} -nc || rm ${PREFIX}/${dir}/${filename} && wget ${MAIN_DOMAIN}/${dir}/${filename} -O ${PREFIX}/${dir}/${filename} -nc
done

# Copy whole directories

PATHS="blockly/media/skins/craft/audio blockly/media/skins/craft/images blockly/media/craft"

for path in ${PATHS}
do
  dir=$(dirname "${path}")
  mkdir -p ${PREFIX}/${dir}
  cp -r "../code-dot-org/dashboard/public/${path}" ${PREFIX}/${dir}/.
done

# Create an index.html to redirect
echo "<meta http-equiv=\"refresh\" content=\"0; URL=s/${COURSE}/lessons/${LESSON}/levels/1.html\" />" > ${PREFIX}/index.html

# Zip it up
echo
echo "Creating ./dist/${COURSE}/${COURSE}_${LESSON}.zip ..."
cd ${PREFIX}
mkdir -p ../../dist/${COURSE}
if [ -f ../../dist/${COURSE}/${COURSE_LESSON}.zip ]; then
  echo "Removing existing zip."
  rm ../../dist/${COURSE}/${COURSE_LESSON}.zip
fi
zip ../../dist/${COURSE}/${COURSE}_${LESSON}.zip -qr .
cd - > /dev/null 2> /dev/null
echo "Done."
