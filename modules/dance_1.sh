# Dance Party!

NAME="Dance Party"

COURSE=dance-2019
LESSON=1

# Other URLs to crawl
URLS="
"

# Restrict videos to be VERY small
VIDEO_MAX_SIZE=10000000

# Files to copy over (that might not be crawled)
# The dance songs metadata I got from (after a build):
# cat build/dance-2019_1/api/v1/sound-library/hoc_song_meta/testManifest.json | python -mjson.tool | grep "id\":" | awk -F ":" '{ gsub (" ", "", $2); gsub ("\"", "", $2); gsub (",", "", $2); print "api/v1/sound-library/hoc_song_meta/" $2 ".json" }'
STATIC="
api/v1/sound-library/hoc_song_meta/songManifest2022.json
api/v1/sound-library/hoc_song_meta/introtoshamstep_47SOUL.json
api/v1/sound-library/hoc_song_meta/isawthesign_aceofbase.json
api/v1/sound-library/hoc_song_meta/takeonme_aha.json
api/v1/sound-library/hoc_song_meta/showdaspoderosas_anitta.json
api/v1/sound-library/hoc_song_meta/jinglebells_hollywoodchristmas.json
api/v1/sound-library/hoc_song_meta/notearslefttocry_arianagrande.json
api/v1/sound-library/hoc_song_meta/wakemeup_aviciialoeblacc.json
api/v1/sound-library/hoc_song_meta/breakmysoul_beyonce.json
api/v1/sound-library/hoc_song_meta/odetocode_brendandominicpaolini.json
api/v1/sound-library/hoc_song_meta/dancinginthedark_brucespringsteen.json
api/v1/sound-library/hoc_song_meta/summer_calvinharris.json
api/v1/sound-library/hoc_song_meta/callmemaybe_carlyraejepsen.json
api/v1/sound-library/hoc_song_meta/levelup_ciara.json
api/v1/sound-library/hoc_song_meta/higherpower_coldplay.json
api/v1/sound-library/hoc_song_meta/vivalavida_coldplay.json
api/v1/sound-library/hoc_song_meta/sayso_dojacat.json
api/v1/sound-library/hoc_song_meta/levitating_dualipa.json
api/v1/sound-library/hoc_song_meta/dontstartnow_dualipa.json
api/v1/sound-library/hoc_song_meta/shapeofyou_edsheeran.json
api/v1/sound-library/hoc_song_meta/wedonttalkaboutbruno_encanto.json
api/v1/sound-library/hoc_song_meta/occidentalview_francescogabbani.json
api/v1/sound-library/hoc_song_meta/heatwaves_glassanimals.json
api/v1/sound-library/hoc_song_meta/asitwas_harrystyles.json
api/v1/sound-library/hoc_song_meta/watermelonsugar_harrystyles.json
api/v1/sound-library/hoc_song_meta/thunder_imaginedragons.json
api/v1/sound-library/hoc_song_meta/dernieredanse_indila.json
api/v1/sound-library/hoc_song_meta/migente_jbalvin.json
api/v1/sound-library/hoc_song_meta/savagelove_jasonderulo.json
api/v1/sound-library/hoc_song_meta/aire_jessejoy.json
api/v1/sound-library/hoc_song_meta/sucker_jonasbrothers.json
api/v1/sound-library/hoc_song_meta/sorry_justinbieber.json
api/v1/sound-library/hoc_song_meta/firework_katyperry.json
api/v1/sound-library/hoc_song_meta/neverreallyover_katyperry.json
api/v1/sound-library/hoc_song_meta/somebodylikeyou_keithurban.json
api/v1/sound-library/hoc_song_meta/ilkadimisenat_kenandogulu.json
api/v1/sound-library/hoc_song_meta/kidzbop_ificanthaveyou_shawnmendes.json
api/v1/sound-library/hoc_song_meta/needyounow_ladya.json
api/v1/sound-library/hoc_song_meta/bornthisway_ladygaga.json
api/v1/sound-library/hoc_song_meta/rainonme_ladygagaftarianagrande.json
api/v1/sound-library/hoc_song_meta/oldtownroadremix_lilnasx.json
api/v1/sound-library/hoc_song_meta/oldtownroadremix_lilnasx_long.json
api/v1/sound-library/hoc_song_meta/2beloved_lizzo.json
api/v1/sound-library/hoc_song_meta/euphoria_loreen.json
api/v1/sound-library/hoc_song_meta/macarena_losdelrio.json
api/v1/sound-library/hoc_song_meta/countrygirl_lukebryan.json
api/v1/sound-library/hoc_song_meta/cantholdus_macklemore.json
api/v1/sound-library/hoc_song_meta/getintothegroove_madonna.json
api/v1/sound-library/hoc_song_meta/uptownfunk_brunomars.json
api/v1/sound-library/hoc_song_meta/astronautintheocean_maskedwolf.json
api/v1/sound-library/hoc_song_meta/jerusalema_masterkg.json
api/v1/sound-library/hoc_song_meta/canttouchthis_mchammer.json
api/v1/sound-library/hoc_song_meta/wecantstop_mileycyrus.json
api/v1/sound-library/hoc_song_meta/starships_nickiminaj.json
api/v1/sound-library/hoc_song_meta/sunroof_nickyoureanddazy.json
api/v1/sound-library/hoc_song_meta/good4u_oliviarodrigo.json
api/v1/sound-library/hoc_song_meta/heyya_outkast.json
api/v1/sound-library/hoc_song_meta/highhopes_panicatthedisco.json
api/v1/sound-library/hoc_song_meta/calma_pedrocapo.json
api/v1/sound-library/hoc_song_meta/sunflower_postmaloneftswaelee.json
api/v1/sound-library/hoc_song_meta/taconesrojos_sebastianyatra.json
api/v1/sound-library/hoc_song_meta/backtoyou_selenagomez.json
api/v1/sound-library/hoc_song_meta/ificanthaveyou_shawnmendes.json
api/v1/sound-library/hoc_song_meta/cheapthrills_sia.json
api/v1/sound-library/hoc_song_meta/stay_thekidlaroi.json
api/v1/sound-library/hoc_song_meta/dancemonkey_tonesandi.json
api/v1/sound-library/hoc_song_meta/despedidaycierre_vanesamartin.json
api/v1/sound-library/hoc_song_meta/ymca_villagepeople.json
api/v1/sound-library/hoc_song_meta/cantfeelmyface_theweeknd.json
api/v1/sound-library/hoc_song_meta/iliketomoveit_william.json
api/v1/sound-library/hoc_song_meta/wenospeakamericano_yolandabecool.json
"

# Files to copy from curriculum.code.org
#
# I got the image titles from:
# cat build/dance-2019_1/images/sprites/dance_20191106/characters.json | python -mjson.tool | grep spritesheet | awk -F ":" '{ gsub (" ", "", $2); gsub ("\"", "", $2); gsub (",", "", $2); print "images/sprites/dance_20191106/" $2 }'
# And then removed duplicates
CURRICULUM_STATIC="
images/sprites/dance_20191106/higher-power-sheet.png
images/DancePartyLoading.gif
images/sprites/dance_20191106/characters.json
images/sprites/dance_20191106/alien_00.png
images/sprites/dance_20191106/alien_01.png
images/sprites/dance_20191106/alien_02.png
images/sprites/dance_20191106/alien_03.png
images/sprites/dance_20191106/bear_04.png
images/sprites/dance_20191106/bear_05.png
images/sprites/dance_20191106/bear_06.png
images/sprites/dance_20191106/bear_07.png
images/sprites/dance_20191106/cat_08.png
images/sprites/dance_20191106/cat_09.png
images/sprites/dance_20191106/cat_10.png
images/sprites/dance_20191106/cat_11.png
images/sprites/dance_20191106/dog_12.png
images/sprites/dance_20191106/dog_13.png
images/sprites/dance_20191106/dog_14.png
images/sprites/dance_20191106/dog_15.png
images/sprites/dance_20191106/duck_16.png
images/sprites/dance_20191106/duck_17.png
images/sprites/dance_20191106/duck_18.png
images/sprites/dance_20191106/duck_19.png
images/sprites/dance_20191106/frog_20.png
images/sprites/dance_20191106/frog_21.png
images/sprites/dance_20191106/frog_22.png
images/sprites/dance_20191106/frog_23.png
images/sprites/dance_20191106/moose_24.png
images/sprites/dance_20191106/moose_25.png
images/sprites/dance_20191106/moose_26.png
images/sprites/dance_20191106/moose_27.png
images/sprites/dance_20191106/pineapple_28.png
images/sprites/dance_20191106/pineapple_29.png
images/sprites/dance_20191106/pineapple_30.png
images/sprites/dance_20191106/pineapple_31.png
images/sprites/dance_20191106/robot_32.png
images/sprites/dance_20191106/robot_33.png
images/sprites/dance_20191106/robot_34.png
images/sprites/dance_20191106/robot_35.png
images/sprites/dance_20191106/shark_36.png
images/sprites/dance_20191106/shark_37.png
images/sprites/dance_20191106/shark_38.png
images/sprites/dance_20191106/shark_39.png
images/sprites/dance_20191106/sloth_40.png
images/sprites/dance_20191106/sloth_41.png
images/sprites/dance_20191106/sloth_42.png
images/sprites/dance_20191106/sloth_43.png
images/sprites/dance_20191106/unicorn_44.png
images/sprites/dance_20191106/unicorn_45.png
images/sprites/dance_20191106/unicorn_46.png
images/sprites/dance_20191106/unicorn_47.png
"

# Files to get from the main site using signed cookies
# The dance songs metadata list can get you the mp3s:
# cat build/dance-2019_1/api/v1/sound-library/hoc_song_meta/testManifest.json | python -mjson.tool | grep "id\":" | awk -F ":" '{ gsub (" ", "", $2); gsub ("\"", "", $2); gsub (",", "", $2); print "restricted/" $2 ".mp3" }'
RESTRICTED="
restricted/introtoshamstep_47SOUL.mp3
restricted/isawthesign_aceofbase.mp3
restricted/takeonme_aha.mp3
restricted/showdaspoderosas_anitta.mp3
restricted/jinglebells_hollywoodchristmas.mp3
restricted/notearslefttocry_arianagrande.mp3
restricted/wakemeup_aviciialoeblacc.mp3
restricted/breakmysoul_beyonce.mp3
restricted/odetocode_brendandominicpaolini.mp3
restricted/dancinginthedark_brucespringsteen.mp3
restricted/summer_calvinharris.mp3
restricted/callmemaybe_carlyraejepsen.mp3
restricted/levelup_ciara.mp3
restricted/higherpower_coldplay.mp3
restricted/vivalavida_coldplay.mp3
restricted/sayso_dojacat.mp3
restricted/levitating_dualipa.mp3
restricted/dontstartnow_dualipa.mp3
restricted/shapeofyou_edsheeran.mp3
restricted/wedonttalkaboutbruno_encanto.mp3
restricted/occidentalview_francescogabbani.mp3
restricted/heatwaves_glassanimals.mp3
restricted/asitwas_harrystyles.mp3
restricted/watermelonsugar_harrystyles.mp3
restricted/thunder_imaginedragons.mp3
restricted/dernieredanse_indila.mp3
restricted/migente_jbalvin.mp3
restricted/savagelove_jasonderulo.mp3
restricted/aire_jessejoy.mp3
restricted/sucker_jonasbrothers.mp3
restricted/sorry_justinbieber.mp3
restricted/firework_katyperry.mp3
restricted/neverreallyover_katyperry.mp3
restricted/somebodylikeyou_keithurban.mp3
restricted/ilkadimisenat_kenandogulu.mp3
restricted/kidzbop_ificanthaveyou_shawnmendes.mp3
restricted/needyounow_ladya.mp3
restricted/bornthisway_ladygaga.mp3
restricted/rainonme_ladygagaftarianagrande.mp3
restricted/oldtownroadremix_lilnasx.mp3
restricted/oldtownroadremix_lilnasx_long.mp3
restricted/2beloved_lizzo.mp3
restricted/euphoria_loreen.mp3
restricted/macarena_losdelrio.mp3
restricted/countrygirl_lukebryan.mp3
restricted/cantholdus_macklemore.mp3
restricted/getintothegroove_madonna.mp3
restricted/uptownfunk_brunomars.mp3
restricted/astronautintheocean_maskedwolf.mp3
restricted/jerusalema_masterkg.mp3
restricted/canttouchthis_mchammer.mp3
restricted/wecantstop_mileycyrus.mp3
restricted/starships_nickiminaj.mp3
restricted/sunroof_nickyoureanddazy.mp3
restricted/good4u_oliviarodrigo.mp3
restricted/heyya_outkast.mp3
restricted/highhopes_panicatthedisco.mp3
restricted/calma_pedrocapo.mp3
restricted/sunflower_postmaloneftswaelee.mp3
restricted/taconesrojos_sebastianyatra.mp3
restricted/backtoyou_selenagomez.mp3
restricted/ificanthaveyou_shawnmendes.mp3
restricted/cheapthrills_sia.mp3
restricted/stay_thekidlaroi.mp3
restricted/dancemonkey_tonesandi.mp3
restricted/despedidaycierre_vanesamartin.mp3
restricted/ymca_villagepeople.mp3
restricted/cantfeelmyface_theweeknd.mp3
restricted/iliketomoveit_william.mp3
restricted/wenospeakamericano_yolandabecool.mp3
"

# Whole directories to copy over
PATHS="
blockly/media/skins/dance
"

VIDEOS="
"

after() {
  # We need to replace the test manifest with the song list
  mv ${PREFIX}/api/v1/sound-library/hoc_song_meta/songManifest* ${PREFIX}/api/v1/sound-library/hoc_song_meta/testManifest.json
}
