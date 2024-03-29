# Module Builder

This builds static versions of certain sections of the code.org site.

## Other Documentation:

* [`LOCALIZING.md`](LOCALIZING.md): Comments on localizing offline modules.
* [`modules/README.md`](modules/README.md): What a "module description" looks like.

## Dependencies

This is entirely written as a bash script. This is precisely so that it does
not require a lot of maintenance. So it just requires `bash`, `sed`,
`grep`, `cut`, and `wget`. All but `wget` are commonly pre-installed into a
Unix-ish enviroment such as OS X and Linux.

Other dependencies it might use are downloaded as it needs it. This includes
`ffmpeg` (video transcoding to compress videos) and `jq` (JSON parser to help
find assets.) It should properly work on both ARM and X86 machines as tested
on Linux.

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

## End-to-End Guide

### Basic Steps

The crawler will produce a zip file containing a static version of the code.org
website that is compatible with both Kolibri and RACHEL. Basic steps:

* Have a built and ready code-dot-org development environment.
* Pull down the offline-crawler repository such that the “offline-crawler” is in
the same directory as “code-dot-org” (say, your home directory.)
* Go into the “modules” directory and review the modules we have.
* Run the crawler for, say, the minecraft hour of code:

```
../package.sh minecraft
```

**Note**: By default, this will pull down ALL locales and translations. It takes
quite a while. To pull down just a few (we do this for Express modules since those
are larger):

```
LOCALES="en_US fr_FR es_MX" ../package.sh minecraft
```

This will produce a zip file in “dist” for Kolibri/RACHEL:

```
ls ../dist/minecraft/minecraft.zip
```

If this is a full lesson, the “teacher” view containing the lesson plan as the
initial page of the module is also built:

```
ls ../dist/minecraft/minecraft_teacher.zip
```

**Note**:
Some large assets are downloaded outside of the `build` path so they are effectively
cached and shared among all builds. These include videos, and restricted
music data.

**Note**:
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

### To, then, upload to Kolibri:

* Review your access to the Kolibri Studio account in 1Password’s “Shared Engineering” group. (Ask Infra or Platform for access.)
* Log on to Kolibri Studio as our Engineering account.
* Navigate to the “code.org” channel. Create the appropriate folder for your content or find the existing module.
* Create or edit the module. Upload the zip file and it will automatically create the right module. When replacing content, just re-upload: edit the module and click on the existing zip file link which will unintuitively let you choose a new file.
* Thumbnails are nice to have. Those are images that are around 480 by 272 pixels. Existing Thumbnails are located in Google Drive including a useful SVG template.
* Don’t forget to press “Save”

### To publish the code.org Kolibri channel:

* On Kolibri Studio, navigate to the code.org channel.
* Review that the top-right of the Kolibri website suggests there are publishable changes.
* In that same top-right corner, press the Publish button. Click through any confirmations.
* Downstream users will be notified whenever possible of these changes and can synchronize when their device has an Internet connection.
* To provide folks with the channel, they need the channel token. When navigating the code.org channel, find that at the top-right navigation menu under “Get Token.”

## Module Description File

The modules are themselves described as bash scripts containing variables that
direct the behavior of the crawler. This file, contained within the `modules`
directory, is simply "sourced" into the packager script such that the variables
defined in the module description are used by the crawler.

This is described in greater detail in [`modules/README.md`](modules/README.md).

## Localization

The crawler already pulls down different localizations and provides a means
to switch them. By default, it will pull down all locales for a module when
building the offline module. To just build a subset, provide them within the
`LOCALES` environment variable:

```
cd modules
LOCALES="en_US fr_FR es_MX" ../package.sh minecraft
```

The process of pulling a locale essentially multiplies the amount of time it
takes to crawl a module by the number of locales. It is the greatest factor
in the time it takes to complete. It is absolutely recommended to just crawl
a common of locales when testing the crawl of a particular module.

For more information, including comments on conventions on publishing localized
modules and issues dealing with constraints such as file size,
see [`LOCALIZING.md`](LOCALIZING.md).

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
the `shims/shim.js` file is pushed to the top of each base JavaScript file for our
apps that shim them ourselves. Without local storage APIs, progress cannot be
saved directly in the browser itself. (See information about the shims and the
mock APIs in [`shims/README.md`](shims).

At any rate, the packages saved in `dist` are zip files. Kolibri HTML5 apps are
essentially metadata wrapped around a provided zip file containing at least an
`index.html` file. Our `index.html` file redirects to the first level of the
wrapped course.

Kolibri offers some API access to "HTML5 apps" as noted in the above link, yet
it unclear how an arbitrary application makes use of it.

Uploading to Kolibri is done via [Kolibri Studio](https://studio.learningequality.org/).
If you are a Code.org engineer, you can access and edit our official modules via our
shared login. Currently, the Code.org channel is private and shared only via the channel
token.

## Known Issues

There are a number of issues that are in two categories. First, problems that
are inherent to offline, such as a dependency on external service. (Offline
Compatibility) Second, problems that are due to the crawling process not being
refined enough, but it could possibly be addressed. (Crawler Bugs)

### Offline Incompatibility

* Internet Simulator prevents Unit 2 of CSP from being reasonable. It is entirely backend-driven.
* Some ability to upload custom sprites, sounds, etc, are unavailable since they make direct use of S3.

### Crawler Bugs

* Extras page is crawled but sometimes does not show up when the lesson is completed fully.
* Lesson plans might link to levels that exist elsewhere (and linked via their `/levels/{id}` path directly). These are not crawled.
