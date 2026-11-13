#!/usr/bin/env python3
"""Prüft alle Feeds aus assets/feeds.json und schreibt einen Bericht.

Pro Feed: erreichbar? gültiges RSS/Atom? Anzahl und Alter der Artikel, Treffer
der Paywall-Regeln (Stufe 1) und eine Stichprobe von Artikelseiten (Stufe 2
wie in der App, dazu die Zahl der Werbe-Marker im HTML). Für fehlerhafte
Feeds wird die Homepage der Quelle nach Feed-Verweisen durchsucht.

Aufruf:  python3 tool/check_feeds.py [feeds.json] [bericht.md]
Braucht nur die Python-Standardbibliothek.
"""
import concurrent.futures as cf
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

UA = ("Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36")
SAMPLE = 6          # Artikelseiten pro Feed in der Stichprobe
MIN_TEXT = 500      # wie kMinFreeTextLength in der App
AD_MARKERS = ["googletag", "adsbygoogle", "doubleclick.net",
              "googlesyndication", "taboola", "outbrain", "adslot",
              "data-ad-", 'class="ad-', 'id="ad-']


def fetch(url, limit=3_000_000, timeout=15):
    """Gibt (Status, Bytes, End-URL) zurück; Status 0 bei Netzwerkfehler."""
    safe = urllib.parse.quote(url, safe=":/?&=%#~+,;@!$'()*[]")
    req = urllib.request.Request(safe, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml,"
                  "application/rss+xml,*/*",
        "Accept-Language": "de-CH,de;q=0.9,en;q=0.6",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(limit), r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, b"", url
    except Exception as e:  # Zeitüberschreitung, DNS, TLS …
        return 0, str(e).encode(), url


def local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def child_text(el, *names):
    for c in el:
        if local(c.tag) in names and (c.text or "").strip():
            return c.text.strip()
    return ""


def parse_date(s):
    s = (s or "").strip()
    if not s:
        return None
    try:
        d = parsedate_to_datetime(s)
    except Exception:
        try:
            d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except Exception:
            return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d


def parse_feed(data):
    """Liste von Artikeln (title, link, summary, date). Wirft bei Nicht-XML."""
    root = ET.fromstring(data.lstrip())
    items = []
    for el in root.iter():
        if local(el.tag) not in ("item", "entry"):
            continue
        link = ""
        for c in el:
            if local(c.tag) != "link":
                continue
            href = c.get("href")
            if href:
                if c.get("rel") in (None, "alternate") or not link:
                    link = href
            elif (c.text or "").strip():
                link = c.text.strip()
        items.append({
            "title": child_text(el, "title"),
            "link": link,
            "summary": child_text(el, "description", "summary"),
            "date": parse_date(child_text(
                el, "pubDate", "published", "updated", "date")),
        })
    return items


def matches_rules(item, rules):
    link = item["link"].lower()
    title = item["title"].lstrip().lower()
    text = title + " " + re.sub(r"<[^>]+>", " ", item["summary"]).lower()
    return (any(p and p.lower() in link for p in rules["urlContains"])
            or any(p and title.startswith(p.lower())
                   for p in rules["titlePrefixes"])
            or any(p and p.lower() in text for p in rules["textContains"]))


def check_article(url, html_patterns):
    """Urteil wie die Tiefenprüfung der App, dazu Zahl der Werbe-Marker."""
    status, data, _ = fetch(url, limit=700_000, timeout=12)
    if status == 402:
        return "paywall", 0
    if status != 200 or not data:
        return "unklar", 0
    body = data.decode("utf-8", "replace")
    low = body.lower()
    ads = sum(low.count(m) for m in AD_MARKERS)
    if any(p and p.lower() in low for p in html_patterns):
        return "paywall", ads
    flags = [m.lower() for m in re.findall(
        r'"isaccessibleforfree"\s*:\s*"?(false|true)', body, re.I)]
    if "false" in flags:
        return "paywall", ads
    if "true" in flags:
        return "frei", ads
    length = 0
    for p in re.findall(r"<p[^>]*>(.*?)</p>", body, re.S | re.I):
        length += len(re.sub(r"<[^>]+>", "", p).strip())
    return ("frei" if length >= MIN_TEXT else "unklar"), ads


def discover(homepage):
    """Feed-Verweise (<link rel="alternate" …>) auf einer Webseite."""
    status, data, final = fetch(homepage, limit=600_000)
    if status != 200:
        return []
    found = []
    for tag in re.findall(r"<link\b[^>]*>", data.decode("utf-8", "replace"),
                          re.I):
        attrs = dict((k.lower(), v) for k, v in
                     re.findall(r'([\w-]+)\s*=\s*["\']([^"\']*)["\']', tag))
        kind = attrs.get("type", "").lower()
        if "alternate" in attrs.get("rel", "").lower() and (
                "rss" in kind or "atom" in kind) and attrs.get("href"):
            url = urllib.parse.urljoin(final, attrs["href"])
            if url not in found:
                found.append(url)
    return found[:6]


def merged_rules(generic, source):
    keys = ("urlContains", "titlePrefixes", "textContains", "htmlContains")
    return {k: list(generic.get(k, [])) + list(source.get(k, []))
            for k in keys}


def check_feed(job):
    source, feed, generic = job
    rules = merged_rules(generic, source.get("paywall") or {})
    row = {"source": source["name"], "country": source.get("country", ""),
           "cat": ",".join(feed.get("categories", [])), "url": feed["url"],
           "ok": False, "note": "", "items": 0, "age": "", "rule": 0,
           "sample": "", "ads": "", "homepage": source.get("homepage", "")}
    status, data, _ = fetch(feed["url"])
    if status != 200:
        row["note"] = ("nicht erreichbar" if status == 0
                       else "HTTP %d" % status)
        return row
    try:
        items = [i for i in parse_feed(data) if i["link"] and i["title"]]
    except Exception:
        row["note"] = "kein RSS/Atom"
        return row
    if not items:
        row["note"] = "keine Artikel"
        return row
    row["ok"] = True
    row["items"] = len(items)
    dates = [i["date"] for i in items if i["date"]]
    if dates:
        hours = (datetime.now(timezone.utc) - max(dates)).total_seconds() / 3600
        row["age"] = ("%d h" % hours) if hours < 72 else ("%d T." % (hours / 24))
        if hours > 24 * 14:
            row["note"] = "veraltet"
    row["rule"] = sum(1 for i in items if matches_rules(i, rules))
    open_items = [i for i in items if not matches_rules(i, rules)][:SAMPLE]
    verdicts = [check_article(i["link"], rules["htmlContains"])
                for i in open_items]
    if verdicts:
        count = {v: sum(1 for x, _ in verdicts if x == v)
                 for v in ("frei", "paywall", "unklar")}
        row["sample"] = "%d/%d/%d" % (
            count["frei"], count["paywall"], count["unklar"])
        row["ads"] = str(round(sum(a for _, a in verdicts) / len(verdicts)))
    return row


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/feeds.json"
    out = sys.argv[2] if len(sys.argv) > 2 else "feeds_report.md"
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    generic = catalog.get("generic") or {}
    jobs = [(s, feed, generic)
            for s in catalog["sources"] for feed in s["feeds"]]
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        rows = list(pool.map(check_feed, jobs))

    bad = [r for r in rows if not r["ok"]]
    lines = [
        "# Feed-Prüfung",
        "",
        "feeds.json Version %s · %d Feeds · %d in Ordnung · %d fehlerhaft" % (
            catalog.get("version"), len(rows), len(rows) - len(bad), len(bad)),
        "",
        "Stichprobe = frei/Paywall/unklar von bis zu %d Artikelseiten. "
        "Werbe-Marker = durchschnittliche Zahl der Werbe-Kennzeichen im HTML "
        "dieser Seiten." % SAMPLE,
        "",
        "| Quelle | Land | Thema | Status | Artikel | Neuester | "
        "Regel-Treffer | Stichprobe | Werbe-Marker | Adresse |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        status = "ok" if r["ok"] and not r["note"] else (
            "ok (%s)" % r["note"] if r["ok"] else "FEHLER: " + r["note"])
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["source"], r["country"], r["cat"], status, r["items"] or "",
            r["age"], r["rule"] if r["ok"] else "", r["sample"], r["ads"],
            r["url"]))

    if bad:
        lines += ["", "## Fehlerhafte Feeds – Verweise auf der Homepage", ""]
        cache = {}
        for r in bad:
            home = r["homepage"]
            if home and home not in cache:
                cache[home] = discover(home)
            found = cache.get(home, [])
            lines.append("- **%s** (%s): %s" % (
                r["source"], r["url"],
                ", ".join(found) if found else "nichts gefunden"))

    report = "\n".join(lines) + "\n"
    with open(out, "w", encoding="utf-8") as f:
        f.write(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(report)
    print(report)


if __name__ == "__main__":
    main()
