# Minecraft Adventure

NAME="Minecraft Adventure"

COURSE=mc
LESSON=1
LEVELS=14

# Other URLs to crawl
URLS="
notes/mc_intro
notes/mc_repeat
notes/mc_if_statements
"

# Files to copy over (that might not be crawled)
STATIC="
blockly/media/skins/craft/music/vignette4-intro.mp3
blockly/media/skins/craft/music/vignette5-shortpiano.mp3
blockly/media/skins/craft/music/vignette2-quiet.mp3
blockly/media/skins/craft/music/vignette3.mp3
blockly/media/skins/craft/music/vignette7-funky-chirps-short.mp3
blockly/media/skins/craft/music/vignette1.mp3
blockly/video-js/video-js.css
blockly/media/trash.png
blockly/media/click.mp3
blockly/media/delete.mp3
blockly/media/canclosed.png
blockly/media/canopen.png
blockly/media/handopen.cur
shared/images/download_button.png
blockly/media/1x1.gif
api/hour/begin_mc.png
"

# Files to copy from curriculum.code.org
CURRICULUM_STATIC="
"

# Files to get from the main site using signed cookies
RESTRICTED="
"

# Whole directories to copy over
PATHS="
blockly/media/skins/craft/audio
blockly/media/skins/craft/images
blockly/media/craft
"

VIDEOS="
2015/mc/mc_intro.mp4
2015/mc/mc_repeat.mp4
2015/mc/mc_if_statements.mp4
"

after() {
}
