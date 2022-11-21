# Module Builder

This builds static versions of certain sections of the code.org site.

## Packager

Our previous app packager produced Electron based applications by crawling the
site and then creating such an app that started a node web server and redirected
the Electron app internally to that served content. This was their solution for
allowing absolute links to assets in the static version of the site. (e.g.
`href="/s/mc/lessons/1/levels/1.html"` instead of
`s/mc/lessons/1/levels/1.html"`)

We cannot do that for many offline deployment options. Kolibri, for instance,
requires relative paths and the static content to be servable off of a subpath.
That is, it might serve our `index.html` from `/apps/code.org/mc/index.html`
which means our static assets must be relative paths so they work no matter
what kind of subpath the kolibri environment chooses. Our main site can safely
assume absolute paths work since we closely control that environment.

This packager, then, uses `wget`'s oft-unmentioned capability to crawl a
website, download all assets required to render that website, and rewrite its
links to properly refer to the downloaded assets _relatively_. Since the page
is dynamically rendered to some degree, this crawler misses some important
assets that aren't requested until the JavaScript runs. These are specified in
the packager script so that they are downloaded after this first pass.

Finally, the packager adds the JavaScript shims that turn off some features that
crash the app in some sandboxed environments (see the Kolibri section below) and
adds style shims to hide some elements of the UI that are not relevant on an
offline experience (e.g. sign up button).

Just run:

```
./package.sh
```

It produces (for minecraft lesson 1):

```
./dist/mc/1/mc_1.zip
```

It can produce other things by editing `COURSE` and `LESSON` environment variables.

## Kolibri / Endless OS Modules

Kolibri applications are static websites that are served in sandbox iframe
environments. These iframes typically have `allow-scripts` as their _only_
enabled capability, but there are some environments that do have
`allow-same-origin`.

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
