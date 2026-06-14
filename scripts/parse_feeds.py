"""Generate OPML file from an input YML file.

This script reads a feeds.yml file, which is a list of RSS feed URLs. The script fetches
each feed to extract metadata (title, link, description), and writes an OPML
file to an output file. The OPML is in a generic format, and should be suitable for
importing into Miniflux, FreshRSS, Tiny Tiny RSS, Inoreader, etc.

Usage:
    python generate_opml.py

Input:
    feeds.yml: YAML file with minimal feed entries:
        version: 1

        feeds:
          - url: https://example.com/feed.xml
            folder_path: [Tech]
            enabled: true
            overrides:
              name: "Custom Name"
              site_url: "https://example.com"

Output:
    output/feeds.opml: Enriched OPML file with feed metadata and foldering.
"""

import re
import time
import niquests as requests
import feedparser
from lxml import etree as ET
from pathlib import Path
import yaml

INPUT = "feeds.yml"
OUTPUT_DIR = Path("output")
OUTPUT_OPML_FILE = Path("feeds.opml")

REQUEST_TIMEOUT = 10
MAX_RETRIES = 3


def fetch_feed(
    url: str, timeout: int = REQUEST_TIMEOUT, max_retries: int = MAX_RETRIES
) -> feedparser.FeedParserDict:
    """Retrieve and parse an RSS/Atom feed from a URL.

    Fetches the feed using niquests with retry logic and exponential backoff,
    then parses the response with feedparser into a structured dict.

    Params:
        url (str): The feed URL to fetch (RSS, Atom, or JSON Feed).
        timeout (int): Request timeout in seconds (default: 10).
        max_retries (int): Maximum number of retry attempts (default: 3).

    Returns:
        (feedparser.FeedParserDict): Parsed feed data containing feed metadata
        and entries.

    Raises:
        Exception: Raises the last exception after all retries are exhausted.
    """
    ## Request RSS feed with retries
    for attempt in range(max_retries):
        try:
            resp = requests.get(url, timeout=timeout)
            resp.raise_for_status()

            ## Parse response into data dict
            return feedparser.parse(resp.content)

        except Exception:
            if attempt < max_retries - 1:
                time.sleep(1.5 * (attempt + 1))
            else:
                raise


def slugify(url: str) -> str:
    """Generate a URL-safe slug from a feed URL.

    Extracts the domain from the URL, converts to lowercase, removes non-alphanumeric
    characters, and returns a slug suitable for use as an ID.

    Params:
        url (str): The feed URL to slugify.

    Returns:
        str: A URL-safe slug (e.g., "example-com" from "https://example.com/feed.xml").
             Returns "feed" if the slug is empty.
    """
    ## Extract domain from URL
    domain = re.sub(r"^https?://", "", url.lower())
    domain = re.sub(r"/.*$", "", domain)

    ## Extract slug from URL
    slug = re.sub(r"[^a-z0-9]+", "-", domain)
    slug = slug.strip("-")

    return slug or "feed"


def canonical_homepage(url: str) -> str:
    """Extract the canonical homepage URL from a feed URL.

    Converts a feed URL (e.g., https://example.com/feed.xml) into its likely
    homepage URL (e.g., https://example.com/) by removing path components
    and ensuring https:// prefix.

    Params:
        url (str): The feed URL to convert.

    Returns:
        str: The canonical homepage URL with https:// prefix.
    """
    link = re.sub(r"/[^/]*\\.xml$", "/", url)
    link = re.sub(r"/[^/]*$", "/", link)
    link = re.sub(r"^https?://", "https://", link)

    return link


def generate_opml_generic(
    feeds: list[dict], timeout: int = REQUEST_TIMEOUT, max_retries: int = MAX_RETRIES
) -> str:
    """Generate a generic OPML 2.0 document from a list of feeds.

    Groups feeds by folder_path, fetches metadata for each feed (title, link),
    applies overrides if present, and builds an OPML document with hierarchical
    foldering. The output is pretty-printed XML suitable for import into OPML-
    compatible RSS readers.

    Params:
        feeds (list[dict]): List of feed dicts with optional fields:
            - url (str): Feed URL.
            - folder_path (list[str]): List of folder/category names.
            - overrides (list): Optional dict with custom name/site_url.
        timeout (int): Request timeout passed to fetch_feed (default: 10).
        max_retries (int): Retry count passed to fetch_feed (default: 3).

    Returns:
        str: Pretty-printed OPML 2.0 XML document as a string.

    Example OPML structure:
        <opml version="2.0">
          <head>
            <title>My RSS Feeds</title>
            <dateCreated>2026-06-14 15:43:29</dateCreated>
          </head>
          <body>
            <outline text="Tech" title="Tech">
              <outline text="Feed Name" title="Feed Name" type="rss"
                       xmlUrl="https://example.com/feed.xml" htmlUrl="https://example.com"/>
            </outline>
          </body>
        </opml>
    """
    root = ET.Element("opml")
    root.attrib["version"] = "2.0"

    head = ET.SubElement(root, "head")
    ET.SubElement(head, "title").text = "My RSS Feeds"
    ET.SubElement(head, "dateCreated").text = time.strftime("%Y-%m-%d %H:%M:%S")

    body = ET.SubElement(root, "body")

    folders: dict[str, list[dict]] = {}

    ## Group feeds by their first folder_path entry
    for f in feeds:
        fp = f.get("folder_path", []) or []
        folder = fp[0] if fp else "Uncategorized"
        folders.setdefault(folder, []).append(f)

    ## Build OPML outline tree with folders as parent outlines
    for folder_name, folder_feeds in sorted(folders.items()):
        folder_outline = ET.SubElement(body, "outline")
        folder_outline.attrib["text"] = folder_name
        folder_outline.attrib["title"] = folder_name

        for f in folder_feeds:
            url = f["url"]

            ## Fetch feed metadata
            feed_obj = fetch_feed(url, timeout, max_retries)
            feed_data = feed_obj.get("feed", {})

            ## Resolve feed name (override > fetched title > slugified URL)
            name = (
                f.get("overrides", {}).get("name")
                or feed_data.get("title")
                or slugify(url)
            )

            ## Resolve site URL (override > fetched link > canonical homepage)
            site_url = (
                f.get("overrides", {}).get("site_url")
                or feed_data.get("link")
                or canonical_homepage(url)
            )

            ## Create feed outline element with required OPML attributes
            o = ET.SubElement(folder_outline, "outline")
            o.attrib["text"] = name
            o.attrib["title"] = name
            o.attrib["type"] = "rss"
            o.attrib["xmlUrl"] = url
            o.attrib["htmlUrl"] = site_url

    ## Return pretty-printed OPML XML string
    return ET.tostring(root, pretty_print=True, encoding="unicode")


def main():
    """Main entry point: load feeds.yml and write OPML to output/feeds.opml.

    Reads the feeds.yml configuration file, generates a generic OPML document
    with enriched feed metadata, and writes it to output/feeds.opml. Creates
    the output directory if it doesn't exist.
    """
    ## Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    ## Load feeds.yml
    with open(INPUT, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    ## Extract feeds list and generate OPML
    feeds = data.get("feeds", [])
    generic_opml = generate_opml_generic(feeds)

    ## Write OPML to output/feeds.opml
    opml_path = OUTPUT_DIR / OUTPUT_OPML_FILE

    with opml_path.open("w", encoding="utf-8") as fh:
        fh.write(generic_opml)

    print(f"Generic OPML written to {opml_path}")


if __name__ == "__main__":
    main()
