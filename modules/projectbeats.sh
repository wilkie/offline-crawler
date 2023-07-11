# Project Beats (Music Lab)

NAME="Project Beats"

COURSE=projectbeats
LESSON=0

# Other URLs to crawl
URLS="
docs/ide/projectbeats
docs/ide/projectbeats/expressions/play_sample
"

# Files to copy over (that might not be crawled)
STATIC="
"

# Whole directories to copy over
PATHS="
blockly/media/music
"

VIDEOS="
"

# Look for the intrument sets
after() {
  echo ""
  echo "Downloading the music-library.json"
  url=https://curriculum.code.org/media/musiclab/music-library.json
  download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${url} "${PREFIX}/wget-musiclab-assets.log"
  mkdir -p ${PREFIX}/media/musiclab
  cp ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json ${PREFIX}/media/musiclab/music-library.json

  echo ""
  echo "Downloading instruments"
  ensure_jq

  GROUP_COUNT=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq ".groups | length"`
  echo ""
  echo "Downloading ${GROUP_COUNT} groups..."

  for (( i=0; i < "${GROUP_COUNT}"; i++ )); do
      # Look at the group description
      group_name=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].name"`
      group_path=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].path"`
      echo "Downloading group \`${group_name}\` within \`${group_path}\`"

      # Look at the 'folders'
      FOLDER_COUNT=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq ".groups[${i}].folders | length"`
      for (( j=0; j < "${FOLDER_COUNT}"; j++ )); do
          # Look at the folder description
          folder_name=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].folders[${j}].name"`
          folder_path=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].folders[${j}].path"`
          echo "Downloading folder \`${folder_name}\` within \`${folder_path}\`"

          # Look at sounds!
          SOUND_COUNT=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq ".groups[${i}].folders[${j}].sounds | length"`
          for (( k=0; k < "${SOUND_COUNT}"; k++ )); do
              # Look at the folder description
              sound_name=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].folders[${j}].sounds[${k}].name"`
              sound_src=`cat ${ROOT_PATH}/${SHARED}/media/musiclab/music-library.json | jq -r ".groups[${i}].folders[${j}].sounds[${k}].src"`
              echo "Downloading sound \`${sound_name}\` within \`${sound_src}\`"

              sound_url="${CURRICULUM_DOMAIN}/media/musiclab/${group_path}/${folder_path}/${sound_src}.mp3"
              download_shared "--reject-regex=\"${REJECT_REGEX}\" --exclude-domains=videos.code.org" ${sound_url} "${PREFIX}/wget-musiclab-assets.log"

              relative_path=media/musiclab/${group_path}/${folder_path}
              mkdir -p ${PREFIX}/${relative_path}
              if [ -e ${PREFIX}/${relative_path}/${sound_src}.mp3 ]; then
                  cp ${ROOT_PATH}/${SHARED}/${relative_path}/${sound_src}.mp3 ${PREFIX}/${relative_path}/${sound_src}.mp3
              fi
          done
      done
  done

  # Download youtube video embedded in the musiclab source
  YT_URL=`grep -oe "iframe[^{]\+[^)]\+" ${PREFIX}/assets/js/musiclab/index*.min.js | grep -ohe "src:\"[^\"]\+" | sed "s;src:\";;"`
  YT_ID=`echo "${YT_URL}" | grep -ohe "embed/[a-zA-Z0-9]\+" | sed "s;embed/;;"`

  # Download it (the result is in `video_path` and `video_url`)
  download_youtube "https://youtube.com/watch?v=${YT_ID}"

  # Set it, now
  sed 's;iframe",{;video",{controls:true,;' -i ${PREFIX}/assets/js/musiclab/index*.min.js
  sed "s;${YT_URL};${RELATIVE_PATH}/${video_url};" -i ${PREFIX}/assets/js/musiclab/index*.min.js

  echo ""
  echo "Downloading docs..."

  DOC_PREFIX=${PREFIX}/docs-tmp

  url=docs/ide/projectbeats
  base_doc_link=${url}
  base_doc_path="${DOC_PREFIX}/${url}.html"
  mkdir -p ${DOC_PREFIX}
  download "--domains=${DOMAINS} --page-requisites --convert-links --adjust-extension --directory-prefix ${DOC_PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}|.*js|.*css\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}/${url} "${PREFIX}/wget-musiclab-docs.log"

  # Get the docs pages
  grep -ohe "data-categoriesfornavigation='[^']\+" ${base_doc_path} | sed "s;data-categoriesfornavigation=';;" > ${PREFIX}/docs.json
  DOCS_CATEGORY_COUNT=`cat ${PREFIX}/docs.json | jq '. | length'`

  for (( i=0; i < "${DOCS_CATEGORY_COUNT}"; i++ )); do
      DOCS_ITEM_COUNT=`cat ${PREFIX}/docs.json | jq ".[${i}].docs | length"`
      category_name=`cat ${PREFIX}/docs.json | jq -r ".[${i}].key"`

      for (( j=0; j < "${DOCS_ITEM_COUNT}"; j++ )); do
          doc_link=`cat ${PREFIX}/docs.json | jq -r ".[${i}].docs[${j}].link" | sed "s;.html;;" | sed "s;^[.]/;/;"`

          doc_path="${DOC_PREFIX}${doc_link}.html"

          # TODO: DO FOR EACH LOCALE
          download "--domains=${DOMAINS} --page-requisites --convert-links --adjust-extension --directory-prefix ${DOC_PREFIX} --no-host-directories --continue -H --span-hosts --tries=2 --reject-regex=\"${REJECT_REGEX}|.*js|.*css\" --exclude-domains=${EXCLUDE_DOMAINS}" ${STUDIO_DOMAIN}${doc_link} "${PREFIX}/wget-musiclab-docs.log"
          fixup ${doc_path} "../../../.."
          dir=$(dirname "${doc_link}")
          mkdir -p ${PREFIX}${dir}
          cp ${doc_path} ${PREFIX}${doc_link}.html
      done
  done

  fixup ${base_doc_path} "../.."
  dir=$(dirname "${base_doc_link}")
  mkdir -p ${PREFIX}/${dir}
  cp ${base_doc_path} "${PREFIX}/${base_doc_link}.html"
}
