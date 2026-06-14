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
import argparse


def parse_args():
    """Parse command-line arguments using argparse."""

    parser = argparse.ArgumentParser(
        description="Generate an OPML file from a feeds.yml configuration file."
    )

    parser.add_argument(
        "--input",
        type=str,
        default="feeds.yml",
        help="Path to the input feeds.yml file (default: feeds.yml)",
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default="output",
        help="Directory to write the output OPML file (default: output)",
    )

    parser.add_argument(
        "--output-file",
        type=str,
        default="feeds.opml",
        help="Name of the output OPML file (default: feeds.opml)",
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=10,
        help="Request timeout in seconds (default: 10)",
    )

    parser.add_argument(
        "--retries",
        type=int,
        default=3,
        help="Maximum number of retry attempts for failed requests (default: 3)",
    )

    parser.add_argument(
        "--title",
        type=str,
        default="My RSS Feeds",
        help="Title for the OPML <head> section (default: My RSS Feeds)",
    )

    return parser.parse_args()


class OPMLGenerator:
    """Controller class for generating OPML from feeds.yml.

    This class encapsulates all logic for fetching RSS/Atom feeds, extracting
    metadata, and generating OPML 2.0 documents. It supports custom configuration
    for timeouts, retries, input/output paths, and OPML metadata.

    Attributes:
        input_path (Path): Path to the input feeds.yml file.
        output_dir (Path): Directory to write OPML output files.
        output_filename (str): Name of the output OPML file.
        timeout (int): Request timeout in seconds.
        max_retries (int): Maximum number of retry attempts for failed requests.
        opml_title (str): Title for the OPML <head> section.
    """

    def __init__(
        self,
        input_path: str = "feeds.yml",
        output_dir: str = "output",
        output_filename: str = "feeds.opml",
        timeout: int = 10,
        max_retries: int = 3,
        opml_title: str = "My RSS Feeds",
    ):
        """Initialize the OPMLGenerator with configuration.

        Params:
            input_path (str): Path to the input feeds.yml file (default: "feeds.yml").
            output_dir (str): Directory to write OPML output files (default: "output").
            output_filename (str): Name of the output OPML file (default: "feeds.opml").
            timeout (int): Request timeout in seconds (default: 10).
            max_retries (int): Maximum retry attempts for failed requests (default: 3).
            opml_title (str): Title for the OPML <head> section (default: "My RSS Feeds").
        """
        self.input_path = Path(input_path)
        self.output_dir = Path(output_dir)
        self.output_filename = output_filename
        self.timeout = timeout
        self.max_retries = max_retries
        self.opml_title = opml_title

    def fetch_feed(self, url: str) -> feedparser.FeedParserDict:
        """Retrieve and parse an RSS/Atom feed from a URL.

        Fetches the feed using niquests with retry logic and exponential backoff,
        then parses the response with feedparser into a structured dict.

        Args:
            url (str): The feed URL to fetch (RSS, Atom, or JSON Feed).

        Returns:
            feedparser.FeedParserDict: Parsed feed data containing feed metadata
            and entries.

        Raises:
            Exception: Raises the last exception after all retries are exhausted.
        """
        for attempt in range(self.max_retries):
            try:
                resp = requests.get(url, timeout=self.timeout)
                resp.raise_for_status()

                return feedparser.parse(resp.content)

            except Exception:
                if attempt < self.max_retries - 1:
                    time.sleep(1.5 * (attempt + 1))
                else:
                    raise

    def slugify(self, url: str) -> str:
        """Generate a URL-safe slug from a feed URL.

        Extracts the domain from the URL, converts to lowercase, removes non-alphanumeric
        characters, and returns a slug suitable for use as an ID.

        Params:
            url (str): The feed URL to slugify.

        Returns:
            str: A URL-safe slug (e.g., "example-com" from "https://example.com/feed.xml").
                 Returns "feed" if the slug is empty.
        """
        domain = re.sub(r"^https?://", "", url.lower())
        domain = re.sub(r"/.*$", "", domain)

        slug = re.sub(r"[^a-z0-9]+", "-", domain)
        slug = slug.strip("-")

        return slug or "feed"

    def canonical_homepage(self, url: str) -> str:
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

    def generate_opml_generic(self, feeds: list[dict]) -> str:
        """Generate a generic OPML 2.0 document from a list of feeds.

        Groups feeds by folder_path, fetches metadata for each feed (title, link),
        applies overrides if present, and builds an OPML document with hierarchical
        foldering. The output is pretty-printed XML suitable for import into OPML-
        compatible RSS readers.

        Params:
            feeds (list[dict]): List of feed dicts with optional fields:
                - url (str): Feed URL.
                - folder_path (list[str]): List of folder/category names.
                - overrides (dict): Optional dict with custom name/site_url.

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
        ET.SubElement(head, "title").text = self.opml_title
        ET.SubElement(head, "dateCreated").text = time.strftime("%Y-%m-%d %H:%M:%S")

        body = ET.SubElement(root, "body")

        folders: dict[str, list[dict]] = {}

        # Group feeds by their first folder_path entry
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
                feed_obj = self.fetch_feed(url)
                feed_data = feed_obj.get("feed", {})

                ## Resolve feed name (override > fetched title > slugified URL)
                name = (
                    f.get("overrides", {}).get("name")
                    or feed_data.get("title")
                    or self.slugify(url)
                )

                ## Resolve site URL (override > fetched link > canonical homepage)
                site_url = (
                    f.get("overrides", {}).get("site_url")
                    or feed_data.get("link")
                    or self.canonical_homepage(url)
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

    def load_feeds(self) -> list[dict]:
        """Load feeds from the input YAML file.

        Reads the feeds.yml configuration file and extracts the feeds list.

        Returns:
            list[dict]: List of feed dictionaries from the YAML file.

        Raises:
            FileNotFoundError: If the input file doesn't exist.
            yaml.YAMLError: If the YAML file is malformed.
        """
        with open(self.input_path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)

        return data.get("feeds", [])

    def write_opml(self, opml_content: str) -> Path:
        """Write OPML content to the output file.

        Creates the output directory if it doesn't exist and writes the OPML
        content to the output file.

        Params:
            opml_content (str): The OPML XML content to write.

        Returns:
            Path: The path to the written OPML file.
        """
        self.output_dir.mkdir(parents=True, exist_ok=True)
        opml_path = self.output_dir / self.output_filename

        with opml_path.open("w", encoding="utf-8") as fh:
            fh.write(opml_content)

        return opml_path

    def run(self) -> Path:
        """Run the full OPML generation pipeline.

        Loads feeds from feeds.yml, generates OPML content, and writes it to
        the output file. This is the main entry point for using the class.

        Returns:
            Path: The path to the generated OPML file.

        Example:
            generator = OPMLGenerator()
            opml_path = generator.run()
            print(f"OPML written to {opml_path}")
        """
        feeds = self.load_feeds()
        generic_opml = self.generate_opml_generic(feeds)
        opml_path = self.write_opml(generic_opml)

        print(f"Generic OPML written to {opml_path}")

        return opml_path


def return_generator(
    input_path: str,
    output_dir: str,
    output_filename: str,
    timeout: int,
    max_retries: int,
    opml_title: str,
) -> OPMLGenerator:
    """Return an initialized OPMLGenerator class."""
    generator = OPMLGenerator(
        input_path=input_path,
        output_dir=output_dir,
        output_filename=output_filename,
        timeout=timeout,
        max_retries=max_retries,
        opml_title=opml_title,
    )

    return generator


def main():
    args = parse_args()

    try:
        generator: OPMLGenerator = return_generator(
            input_path=args.input,
            output_dir=args.output_dir,
            output_filename=args.output_file,
            timeout=args.timeout,
            max_retries=args.retries,
            opml_title=args.title,
        )

        generator.run()
    except Exception as exc:
        raise


if __name__ == "__main__":
    main()
