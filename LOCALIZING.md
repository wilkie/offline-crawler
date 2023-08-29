# How do I make translations available offline?

We do not currently have a dedicated strategy to localized modules on platforms like Kolibri.
The crawler will, by default, create a module with ALL locales and provide a means of switching
the locale within the module via the code.org website’s normal locale dropdown.

The crawler will pull down all translations on the production code.org website that are
visible in the locale dropdown.
It does this by swapping locales and performing multiple crawls of the site using each locale.
It then carefully merges all of those runs into a single module and updates the locale
dropdown inside the module to swap between them.

This process is the reason that crawls might take a fairly long time to perform (30 to 60
minutes for a lesson with many complicated levels.)
And module file sizes are an issue on Kolibri that allow only modules up to around 230MB.
Due to there being dubbed videos for some locales, modules with all localizations carry a heavy cost.
Considering the normal amount of multimedia content, the Dance Party module, for instance,
already has to be compressed down to fit that size constraint.
That module cannot take on multiple videos in a reasonable way.
It is, furthermore, understandable to be concerned with the sizes of modules when we respect
the idea that they must be downloaded on unreliable connections in practice.
So the constraint on Kolibri is unlikely to change.
Therefore, it is not actually possible to put all locales into a single module.

This is why the common convention we see on Kolibri is to publish a module per locale.
Essentially, duplicating the module for each locale. We could do the same with, perhaps,
sets of languages, if we devote more time and resources into our offline work.
Our channel could be organized into folders for each locale (or set of locales)
and then have the modules crawled per language and then updated there.
The crawler already handles a subset of locales by truncating the locale dropdown
in the web application to only those asked for during the crawl.

However, it is a giant undertaking to manually edit and maintain that metadata on Kolibri
Studio and it must be automated.
Code.org has nearly 100 locales and gigabytes of localization content.
Each duplicated module with, say, a lesson video means there’s now 100 videos... between 10 and
20 gigabytes of data.
There is no good mechanism to make having so much duplication of multimedia content efficient.
We would likely want to separate videos that are usually embedded into our lessons into separate modules,
for instance.
Otherwise, we would rely on Kolibri to provide adequate storage and bandwidth,
which may present a future problem.

