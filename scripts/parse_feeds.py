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


def fetch_feed(url: str, timeout: int, max_retries: int) -> feedparser.FeedParserDict:
    """Retrieve RSS feed from URL and parse into XML."""
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
    """Get URL slug from input URL."""
    ## Extract domain from URL
    domain = re.sub(r"^https?://", "", url.lower())
    domain = re.sub(r"/.*$", "", domain)

    ## Extract slug from URL
    slug = re.sub(r"[^a-z0-9]+", "-", domain)
    slug = slug.strip("-")

    return slug or "feed"


def canonical_homepage(url: str) -> str:
    """Get domain root/home page from URL."""
    link = re.sub(r"/[^/]*\\.xml$", "/", url)
    link = re.sub(r"/[^/]*$", "/", link)
    link = re.sub(r"^https?://", "https://", link)

    return link


def generate_opml_generic(feeds: list[dict], timeout: int, max_retries: int) -> str:
    """Generate OPML data from list of feeds."""
    root = ET.Element("opml")
    root.attrib["version"] = "2.0"

    head = ET.SubElement(root, "head")
    ET.SubElement(head, "title").text = "My RSS Feeds"
    ET.SubElement(head, "dateCreated").text = time.strftime("%Y-%m-%d %H:%M:%S")

    body = ET.SubElement(root, "body")

    folders: dict[str, list[dict]] = {}

    for f in feeds:
        fp = f.get("folder_path", []) or []

        folder = fp[0] if fp else "Uncategorized"
        folders.setdefault(folder, []).append(f)

    for folder_name, folder_feeds in sorted(folders.items()):
        folder_outline = ET.SubElement(body, "outline")
        folder_outline.attrib["text"] = folder_name
        folder_outline.attrib["title"] = folder_name

        for f in folder_feeds:
            url = f["url"]

            feed_obj = fetch_feed(url, timeout, max_retries)
            feed_data = feed_obj.get("feed", {})

            name = (
                f.get("overrides", {}).get("name")
                or feed_data.get("title")
                or slugify(url)
            )

            site_url = (
                f.get("overrides", {}).get("site_url")
                or feed_data.get("link")
                or canonical_homepage(url)
            )

            o = ET.SubElement(folder_outline, "outline")
            o.attrib["text"] = name
            o.attrib["title"] = name
            o.attrib["type"] = "rss"
            o.attrib["xmlUrl"] = url
            o.attrib["htmlUrl"] = site_url

    return ET.tostring(root, pretty_print=True, encoding="unicode")


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with open(INPUT, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    feeds = data.get("feeds", [])
    generic_opml = generate_opml_generic(feeds)

    opml_path = OUTPUT_DIR / OUTPUT_OPML_FILE

    with opml_path.open("w", encoding="utf-8") as fh:
        fh.write(generic_opml)

    print(f"Generic OPML written to {opml_path}")


if __name__ == "__main__":
    main()
