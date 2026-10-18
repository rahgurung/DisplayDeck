#!/usr/bin/env python3
"""Writes the website's release data from GitHub Releases.

  docs/releases.json  download links and sizes for the site's Download buttons and Older versions list
  docs/appcast.xml    the Sparkle update feed, built from releases that carry an appcast.json asset
                      (written by the Release workflow with the DMG's EdDSA signature and build number)

Usage: GH_TOKEN=... python3 Packaging/site-data.py <owner/repo> <docs dir>
"""
import html
import json
import os
import re
import sys
import urllib.request
from datetime import datetime
from email.utils import format_datetime


def fetch_json(url, token=None):
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def markdown_to_html(text):
    """Enough Markdown for CHANGELOG sections: ### headings, - bullets, **bold**, *italics*, `code`."""
    def inline(line):
        line = html.escape(line, quote=False)
        line = re.sub(r"`([^`]+)`", r"<code>\1</code>", line)
        line = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", line)
        return re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", line)

    out, in_list = [], False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if line.startswith("#"):
            out.append(f"<h3>{inline(line.lstrip('#').strip())}</h3>")
        elif line:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def appcast_item(release, info):
    published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    notes = markdown_to_html(release.get("body") or "")
    return f"""    <item>
      <title>Version {html.escape(info["version"])}</title>
      <pubDate>{format_datetime(published)}</pubDate>
      <sparkle:version>{html.escape(str(info["build"]))}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(info["version"])}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(info["minimumSystemVersion"])}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{html.escape(release["html_url"])}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(info["url"])}" length="{int(info["length"])}" type="application/octet-stream" sparkle:edSignature="{html.escape(info["edSignature"])}"/>
    </item>"""


def main():
    repo, docs = sys.argv[1], sys.argv[2]
    token = os.environ.get("GH_TOKEN")
    releases = fetch_json(f"https://api.github.com/repos/{repo}/releases?per_page=100", token)

    site, items = [], []
    for release in releases:
        if release["draft"] or release["prerelease"]:
            continue
        assets = {asset["name"]: asset for asset in release["assets"]}
        dmg = next((asset for name, asset in assets.items() if name.endswith(".dmg")), None)
        if not dmg:
            continue
        site.append({
            "version": release["tag_name"].removeprefix("v"),
            "date": release["published_at"],
            "notes": release["html_url"],
            "dmg": {"url": dmg["browser_download_url"], "size": dmg["size"]},
        })
        if "appcast.json" in assets:
            info = fetch_json(assets["appcast.json"]["browser_download_url"])
            info["url"] = dmg["browser_download_url"]
            items.append(appcast_item(release, info))

    with open(os.path.join(docs, "releases.json"), "w") as f:
        json.dump(site, f, indent=1)

    feed = "\n".join(items)
    with open(os.path.join(docs, "appcast.xml"), "w") as f:
        f.write(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DisplayDeck</title>
    <link>https://displaydeck.rahulgurung.com/appcast.xml</link>
    <language>en</language>
{feed}
  </channel>
</rss>
""")
    print(f"releases.json: {len(site)} releases; appcast.xml: {len(items)} updates")


if __name__ == "__main__":
    main()
