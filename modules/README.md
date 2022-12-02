# Module Description File

The modules are themselves described as bash scripts containing variables that
direct the behavior of the crawler. This file, contained within the `modules`
directory, is simply "sourced" into the packager script such that the variables
defined in the module description are used by the crawler.

The `COURSE` and `LESSON` variables direct the crawler to the lesson to crawl.
Every module is a lesson, which is comprised of a set of levels. The crawler will
determine the level count by parsing the first level's metadata. The URL the
crawler hits first is related to these:

`http://localhost-studio.code.org:3000/s/${COURSE}/lessons/${LESSON}/levels/1`

The `URLS` list is a set of other pages to crawl and make available in the
resulting package. These are pulled in a similar way to the level pages. This
was originally used to ensure video transcripts were downloaded, but the
crawler now handles that automatically. This can similarly be used for other
things.

The `STATIC` list is a set of static files to ensure are also downloaded and made
available in the package. Many such assets are determined from the crawler as
well, but it doesn't hurt to add them here when you know for sure. A lot of the
time, api calls that return important JSON metadata are what goes here.

The `CURRICULUM_STATIC` is like `STATIC`, but the data comes from the curriculum
asset domain specifically. A surprising segment of our content comes from here
instead of the normal asset domain.

The `RESTRICTED` section contains a listing of any content that requires a
signed cookie to access. Obviously, this content likely should not be part of
the package unless it has been approved specifically for that purpose.

The `PATHS` section are directories to copy over from the `code-dot-org`
repository. Instead of bombarding the main site with requests for a set of files,
we can just quickly copy them from our local development directory when we know
we need them.

The `VIDEOS` section lists relative URLs for the videos to find from one of our
content domains. Our crawler does a good job of determining the videos used by
lessons automatically, but you can add others here manually.

The `after()` callback can be added to your module to specifically perform any
operation at the end of the crawl but before the packaging starts. This is useful
if any editing of files, renaming of files, etc needs to happen. One place this
is used is in Dance Party to overwrite the song listing and metadata, since the
one crawled is either the development or production one. These don't match, but
also we likely want a completely different (smaller, royalty-free) listing of
music anyway. This is where that can happen.
