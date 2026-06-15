# RSS Feeds

Tracks my RSS feeds and exports them to .opml files. Parses [`feeds.yml`](./.raw/feeds.yml) into a standardized [`feeds.opml` file](./feeds.opml). This file should be compatible with most RSS readers, including FreshRSS, Miniflux, Inoreader, and other readers that can import from `.opml` files.

Each time the `feeds.yml` changes, the pipeline regenerates `feeds.opml` and creates a release. You can see the latest release on the [`releases` page](https://gitlab.com/redjax/rss-feeds/-/releases). Each tagged release includes a downloadable version of the `feeds.opml`.
