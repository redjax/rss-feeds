"""Generate OPML file from feed YAML inputs.

This script reads one or more YAML files containing RSS feed definitions. It can
accept a single feeds.yml file, a directory of feed YAML files, or a glob pattern.
The script fetches each feed to extract metadata (title, link, description), and
writes an OPML file to an output file. The OPML is in a generic format, and
should be suitable for importing into Miniflux, FreshRSS, Tiny Tiny RSS,
Inoreader, etc.

Usage:
    python generate_opml.py

Input:
    feeds.yml, a directory, or a glob pattern:
        version: 1

        feeds:
          - url: [https://example.com/feed.xml](https://example.com/feed.xml)
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
import niquests
from niquests.exceptions import HTTPError, RequestException
import feedparser
from lxml import etree as ET
from glob import glob
from pathlib import Path
import yaml
import argparse
import typing as t
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import hashlib

USER_AGENT: dict = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
}


def parse_args():
    """Parse command-line arguments using argparse."""

    parser = argparse.ArgumentParser(
        description="Generate an OPML file from a feeds.yml configuration file."
    )

    parser.add_argument(
        "--input",
        type=str,
        default=".raw/feeds.yml",
        help="Path to the input feeds.yml file or directory (default: .raw/feeds.yml)",
    )

    parser.add_argument(
        "--output-dir",
        type=str,
        default=".",
        help="Directory to write the output OPML file (default: .)",
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
        input_path (Path): Path to the input feeds.yml file or directory.
        output_dir (Path): Directory to write OPML output files.
        output_filename (str): Name of the output OPML file.
        timeout (int): Request timeout in seconds.
        max_retries (int): Maximum number of retry attempts for failed requests.
        opml_title (str): Title for the OPML <head> section.
    """

    def __init__(
        self,
        input_path: str = ".raw/feeds.yml",
        output_dir: str = ".",
        output_filename: str = "feeds.opml",
        timeout: int = 10,
        max_retries: int = 3,
        opml_title: str = "My RSS Feeds",
    ):
        """Initialize the OPMLGenerator with configuration.

        Params:
            input_path (str): Path to the input feeds.yml file or directory (default: ".raw/feeds.yml").
            output_dir (str): Directory to write OPML output files (default: ".").
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

        ## cache system
        self.cache_dir = Path(".cache")
        self.cache_file = self.cache_dir / "feeds.cache.json"
        self.cache_ttl = 60 * 60 * 24 * 7  # 7 days
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _cache_key(self, url: str) -> str:
        return hashlib.sha256(url.encode()).hexdigest()

    def load_cache(self) -> dict:
        if not self.cache_file.exists():
            return {}
        try:
            return json.loads(self.cache_file.read_text())
        except Exception:
            return {}

    def _json_safe(self, obj: t.Any) -> t.Any:
        """Recursively convert an object into a JSON-serializable form.

        Params:
            obj (Any): The object to sanitize for JSON serialization. This may be
                a dict, list, primitive value, or a non-serializable object such as
                a feedparser exception.

        Returns:
            Any: A JSON-safe version of the object, with unsupported values
            converted to strings or removed as needed.
        """

        if isinstance(obj, dict):
            out = {}

            for k, v in obj.items():
                if k == "bozo_exception":
                    continue
                out[k] = self._json_safe(v)

            return out

        if isinstance(obj, list):
            return [self._json_safe(v) for v in obj]

        if isinstance(obj, (str, int, float, bool)) or obj is None:
            return obj

        return str(obj)

    def save_cache(self, cache: dict):
        safe_cache = self._json_safe(cache)
        self.cache_file.write_text(json.dumps(safe_cache, indent=2))

    def fetch_feed(self, url: str) -> feedparser.FeedParserDict | None:
        """Retrieve and parse an RSS/Atom feed from a URL.

        Fetches the feed using niquests with retry logic and exponential backoff,
        then parses the response with feedparser into a structured dict.

        Params:
            url (str): The feed URL to fetch (RSS, Atom, or JSON Feed).
        """

        for attempt in range(1, self.max_retries + 1):
            try:
                resp = niquests.get(
                    url,
                    timeout=self.timeout,
                    headers=USER_AGENT,
                    allow_redirects=True,
                )

                status = resp.status_code

                ## Permanent failures
                if status in (401, 403, 404, 410):
                    print(
                        f"[WARN] {url} returned HTTP {status}; using fallback metadata"
                    )
                    return None

                resp.raise_for_status()

                parsed = feedparser.parse(resp.content)

                if getattr(parsed, "bozo", False):
                    print(
                        f"[WARN] Feed parse issue for {url}: {getattr(parsed, 'bozo_exception', '')}"
                    )

                return parsed

            except HTTPError as exc:
                status = getattr(exc.response, "status_code", None)

                ## Retry only transient server failures
                if status and status >= 500:
                    wait = 2**attempt

                    print(
                        f"[WARN] HTTP {status} for {url}; retrying in {wait}s ({attempt}/{self.max_retries})"
                    )

                    time.sleep(wait)
                    continue

                print(f"[WARN] Failed to fetch {url}: {exc}")
                return None

            except RequestException as exc:
                wait = 2**attempt

                if attempt < self.max_retries:
                    print(
                        f"[WARN] Request failed for {url}: {exc}; retrying in {wait}s ({attempt}/{self.max_retries})"
                    )

                    time.sleep(wait)
                    continue

                print(f"[WARN] Giving up on {url}: {exc}")
                return None

            except Exception as exc:
                print(f"[WARN] Unexpected error for {url}: {exc}")
                return None

        return None

    def fetch_feed_cached(self, url: str, cache: dict):
        key = self._cache_key(url)
        now = time.time()

        if key in cache:
            entry = cache[key]
            if now - entry.get("ts", 0) < self.cache_ttl:
                return entry.get("data")

        data = self.fetch_feed(url)

        cache[key] = {
            "ts": now,
            "data": self._json_safe(data) if data is not None else None,
        }

        return data

    def fetch_all_feeds(self, feeds: list[dict]) -> dict[str, dict]:
        cache = self.load_cache()
        results = {}

        urls = [f["url"] for f in feeds if isinstance(f, dict) and f.get("url")]

        def worker(url):
            return url, self.fetch_feed_cached(url, cache)

        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(worker, url) for url in urls]

            for fut in as_completed(futures):
                url, data = fut.result()
                results[url] = data

        self.save_cache(cache)
        return results

    def slugify(self, url: str) -> str:
        domain = re.sub(r"^https?://", "", url.lower())
        domain = re.sub(r"/.*$", "", domain)

        slug = re.sub(r"[^a-z0-9]+", "-", domain)
        slug = slug.strip("-")

        return slug or "feed"

    def canonical_homepage(self, url: str) -> str:
        link = re.sub(r"/[^/]*\.xml$", "/", url)
        link = re.sub(r"/[^/]*$", "/", link)
        link = re.sub(r"^https?://", "https://", link)

        return link

    def normalize_folder_path(self, fp: list) -> tuple[str, ...]:
        """Normalize folder path, ensure strings, strip whitespace, remove empties."""
        if not fp:
            return ("Uncategorized",)

        cleaned = []
        for part in fp:
            if part is None:
                continue

            part = str(part).strip()

            if part:
                cleaned.append(part)

        return tuple(cleaned or ["Uncategorized"])

    # -----------------------------
    # OPML generation
    # -----------------------------

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

        ## Deduplicate on URL and folder paths
        seen: set[tuple[str, frozenset[str]]] = set()
        cleaned_feeds: list[dict] = []

        for f in feeds:
            if not isinstance(f, dict):
                continue

            url = f.get("url")
            if not url:
                continue

            fp = self.normalize_folder_path(f.get("folder_path"))

            key = (url, frozenset(fp))
            if key in seen:
                continue

            seen.add(key)

            ## Store normalized folder path
            f = dict(f)
            f["_folder_path"] = fp
            cleaned_feeds.append(f)

        ## Build folder tree structure
        tree: dict = {}

        def insert(path: tuple[str, ...], feed: dict):
            node = tree
            for part in path:
                node = node.setdefault(part, {})
            node.setdefault("_feeds", []).append(feed)

        for f in cleaned_feeds:
            insert(f["_folder_path"], f)

        feed_map = self.fetch_all_feeds(feeds)

        def build_outline(parent_xml, subtree: dict):
            for key in sorted(k for k in subtree.keys() if k != "_feeds"):
                folder_xml = ET.SubElement(parent_xml, "outline")
                folder_xml.attrib["text"] = key
                folder_xml.attrib["title"] = key
                build_outline(folder_xml, subtree[key])

            for f in subtree.get("_feeds", []):
                url = f["url"]

                feed_obj = feed_map.get(url) or {}
                feed_data = (feed_obj or {}).get("feed", {})

                name = (
                    f.get("overrides", {}).get("name")
                    or feed_data.get("title")
                    or self.slugify(url)
                )

                site_url = (
                    f.get("overrides", {}).get("site_url")
                    or feed_data.get("link")
                    or self.canonical_homepage(url)
                )

                o = ET.SubElement(parent_xml, "outline")
                o.attrib["text"] = name
                o.attrib["title"] = name
                o.attrib["type"] = "rss"
                o.attrib["xmlUrl"] = url
                o.attrib["htmlUrl"] = site_url

        build_outline(body, tree)

        return ET.tostring(root, pretty_print=True, encoding="unicode")

    def _feed_source_files(self) -> list[Path]:
        raw = str(self.input_path)

        if any(ch in raw for ch in "*?[]"):
            files = [Path(p) for p in glob(raw)]

            if not files:
                raise FileNotFoundError(f"No files matched pattern: {raw}")

        elif self.input_path.is_dir():
            files = list(self.input_path.rglob("*.yml")) + list(
                self.input_path.rglob("*.yaml")
            )

        elif self.input_path.is_file():
            files = [self.input_path]

        else:
            raise FileNotFoundError(f"Input path does not exist: {self.input_path}")

        files = sorted({p.resolve() for p in files if p.is_file()})

        return [Path(p) for p in files]

    def load_feeds(self) -> list[dict]:
        feeds: list[dict] = []

        for source in self._feed_source_files():
            with source.open("r", encoding="utf-8") as fh:
                data = yaml.safe_load(fh) or {}

            feeds.extend(data.get("feeds", []))

        return feeds

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
        feeds = sorted(
            feeds,
            key=lambda f: (
                tuple(f.get("folder_path") or []),
                f.get("url", ""),
                f.get("overrides", {}).get("name", ""),
            ),
        )
        opml = self.generate_opml_generic(feeds)
        path = self.write_opml(opml)

        print(f"Generic OPML written to {path}")
        return path


def return_generator(
    input_path: str,
    output_dir: str,
    output_filename: str,
    timeout: int,
    max_retries: int,
    opml_title: str,
) -> OPMLGenerator:
    return OPMLGenerator(
        input_path=input_path,
        output_dir=output_dir,
        output_filename=output_filename,
        timeout=timeout,
        max_retries=max_retries,
        opml_title=opml_title,
    )


def main():
    args = parse_args()

    print("Building OPMLGenerator class")
    generator = return_generator(
        input_path=args.input,
        output_dir=args.output_dir,
        output_filename=args.output_file,
        timeout=args.timeout,
        max_retries=args.retries,
        opml_title=args.title,
    )

    print("Generating OPML file")
    generator.run()


if __name__ == "__main__":
    main()
