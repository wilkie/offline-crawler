# Module Builder

This builds static versions of certain sections of the code.org site.

## Dependencies

This is entirely written as a bash script. This is precisely so that it does
not require a lot of maintenance. So it just requires `bash`, `sed`,
`grep`, `cut`, and `wget`. All but `wget` are commonly pre-installed into a
Unix enviroment such as OS X and Linux.

## Basic Usage

```
./package mc_1
```

Produces `dist/mc/mc_1.zip`

The module names correspond to the course key and the lesson number.

More specific instructions follow.

## Packager

Our [previous app packager](https://github.com/code-dot-org/static-app)
produced Electron based applications by crawling the
site and then creating such an app that started a node web server and redirected
the Electron app internally to that served content. This was their solution for
allowing absolute links to assets in the static version of the site. (e.g.
`href="/s/mc/lessons/1/levels/1.html"` instead of
`s/mc/lessons/1/levels/1.html"`)

We cannot do that for many offline deployment options. Kolibri, for instance,
requires relative paths and the static content to be servable off of a subpath.
That is, it might serve our `index.html` from `/apps/code.org/mc/index.html`
which means our static assets must be relative paths so they work no matter
what kind of subpath the Kolibri environment chooses. Our main site can safely
assume absolute paths work since we closely control that environment.

This packager, then, uses `wget`'s oft-unmentioned capability to crawl a
website, download all assets required to render that website, and rewrite its
links to properly refer to the downloaded assets _relatively_. Since the page
is dynamically rendered to some degree, this crawler misses some important
assets that aren't requested until the JavaScript runs. These are specified in
the packager script so that they are downloaded after this first pass.

Many assets are discoverable from the HTML, CSS, and JavaScript assets crawled
during the first pass. Using some heroic efforts by both grep and sed, we can
gather a list of associated assets and pull those in somewhat conservatively
into the package. Other assets can be, as mentioned, added in manually.

Finally, the packager adds the JavaScript shims that turn off some features that
crash the app in some sandboxed environments (see the Kolibri section below) and
adds style shims to hide some elements of the UI that are not relevant on an
offline experience (e.g. sign up button).

Just run:

```
./package.sh mc_1
```

It produces (for minecraft lesson 1):

```
./dist/mc/mc_1.zip
```

It can produce other things by editing `COURSE` and `LESSON` environment variables.
We generalize this by building out separate shell scripts for each module that
define specific resources each need. See `./modules/mc_1.sh` and such for examples
and the general boilerplate.

Adding a module via this directory will add that ability to build it. That is,
adding, say `./modules/foo_1.sh` and setting the `COURSE` and `LESSON` accordingly
will allow building that module via:

```
./package.sh foo_1
```

And seeing, if successful, the zip in `./dist/foo/foo_1.zip` and the contents of
those zip packages in: `./build/foo_1/`.

Some large assets are downloaded outside of the `build` path so they are effectively
cached and shared among all builds. These include videos, and restricted
music data.

## Module Description File

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

## Kolibri / Endless OS Modules

Kolibri applications are static websites that are served in sandbox iframe
environments. These iframes typically have `allow-scripts` as their _only_
enabled capability, but there are some environments that do have
`allow-same-origin`. (I will note that both `allow-scripts` and
`allow-same-origin` is a strange choice since it does not really sandbox
in any meaningful way... and I suspect that it should not be relied on being
this way long-term... but might be this way on, say, an Endless Key
environment, though.)

Without `allow-same-origin`, local storage APIs are unavailable. Kolibri
[documents this](https://kolibri-dev.readthedocs.io/en/develop/frontend_architecture/HTML5_API.html)
as a limitation and notes they "shim" such APIs. That does not seem to be true
in all environments and it is unclear which our apps will appear in. Therefore,
the `shim.js` file is pushed to the top of each base JavaScript file for our
apps that shim them ourselves. Without local storage APIs, progress cannot be
saved directly in the browser itself.

At any rate, the packages saved in `dist` are zip files. Kolibri HTML5 apps are
essentially metadata wrapped around a provided zip file containing at least an
`index.html` file. Our `index.html` file redirects to the first level of the
wrapped course.

Kolibri offers some API access to "HTML5 apps" as noted in the above link, yet
it unclear how an arbitrary application makes use of it.
