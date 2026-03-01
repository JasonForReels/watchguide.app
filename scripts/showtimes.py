#!/usr/bin/env python3
"""
Ster-Kinekor showtimes agent (scrape-first).

Interactive flow:
1) Ask for location (e.g. "Eastgate")
2) Show available dates
3) Ask which date
4) Show available times by movie

Non-interactive examples:
  python3 scripts/showtimes.py --location eastgate
  python3 scripts/showtimes.py --location "Eastgate" --date 2026-03-01
  python3 scripts/showtimes.py --location eastgate --date 2026-03-01 --json
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List


STER_BASE_URL = "https://www.sterkinekor.com/program"
USER_AGENT = "Mozilla/5.0 (WatchGuide-Showtimes/1.1)"


@dataclass
class Location:
    slug: str
    title: str
    region: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ster-Kinekor showtimes agent.")
    parser.add_argument("--location", help="Cinema name or slug, e.g. Eastgate or eastgate")
    parser.add_argument("--date", help="Date in YYYY-MM-DD")
    parser.add_argument("--lookahead", type=int, default=10, help="How many future days to probe for available dates")
    parser.add_argument("--json", action="store_true", help="Print JSON output")
    parser.add_argument("--non-interactive", action="store_true", help="Fail instead of prompting for missing inputs")
    return parser.parse_args()


def http_get_text(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.read().decode(charset, errors="ignore")


def http_post_json(url: str, payload: Dict[str, Any], timeout: int = 20) -> str:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json",
            "Referer": f"{STER_BASE_URL}?location=eastgate",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.read().decode(charset, errors="ignore")


def decode_embedded_blocks(page_html: str) -> List[Dict[str, Any]]:
    blocks: List[Dict[str, Any]] = []
    for encoded in re.findall(r'JSON\.parse\(decodeURIComponent\("(.*?)"\)\);', page_html, re.S):
        try:
            blocks.append(json.loads(urllib.parse.unquote(encoded)))
        except Exception:
            continue
    return blocks


def fetch_all_locations() -> List[Location]:
    page_html = http_get_text(f"{STER_BASE_URL}?location=eastgate")
    blocks = decode_embedded_blocks(page_html)

    result: List[Location] = []
    for block in blocks:
        if block.get("_blockName") != "HeaderClassic":
            continue
        grouped = block.get("groupedLocations") or {}
        for region, locations in grouped.items():
            for loc in locations:
                slug = str(loc.get("name") or "").strip()
                title = str(loc.get("title") or slug).strip()
                if slug:
                    result.append(Location(slug=slug, title=title, region=region))
        break

    unique: Dict[str, Location] = {}
    for loc in result:
        unique[loc.slug.lower()] = loc
    return sorted(unique.values(), key=lambda l: l.title.lower())


def fetch_program_html(location_slug: str, target_date: dt.date) -> str:
    query = urllib.parse.urlencode({"location": location_slug, "date": target_date.isoformat()})
    return http_get_text(f"{STER_BASE_URL}?{query}")


def parse_movie_showtimes(page_html: str) -> List[Dict[str, Any]]:
    card_starts = [m.start() for m in re.finditer(r"movie-card-with-show-times py-0 all-content-has-been-loaded", page_html)]
    movies: List[Dict[str, Any]] = []

    for idx, start in enumerate(card_starts):
        end = card_starts[idx + 1] if idx + 1 < len(card_starts) else len(page_html)
        segment = page_html[start:end]

        title_match = re.search(r'<a[^>]*class="movieDetailsCard__title[^>]*>(.*?)</a>', segment, re.I | re.S)
        if not title_match:
            continue

        title = html.unescape(re.sub(r"\s+", " ", title_match.group(1)).strip())
        raw_show_datetimes = re.findall(r"sendGA\('[^']*',\s*'([^']+GMT\+\d{4}[^']*)'", segment)

        times: List[str] = []
        parsed_date: str | None = None
        for raw_val in raw_show_datetimes:
            try:
                cleaned = raw_val.split(" (", 1)[0]
                parsed = dt.datetime.strptime(cleaned, "%a %b %d %Y %H:%M:%S GMT%z")
                parsed_date = parsed.date().isoformat()
                times.append(parsed.strftime("%I:%M %p").lstrip("0"))
            except Exception:
                continue

        if times:
            movies.append(
                {
                    "title": title,
                    "date": parsed_date,
                    "times": sorted(set(times), key=lambda t: dt.datetime.strptime(t, "%I:%M %p")),
                }
            )
    return movies


def find_location_matches(user_text: str, locations: List[Location]) -> List[Location]:
    key = user_text.strip().lower()
    if not key:
        return []

    exact = [l for l in locations if l.slug.lower() == key or l.title.lower() == key]
    if exact:
        return exact

    partial = [l for l in locations if key in l.slug.lower() or key in l.title.lower()]
    if partial:
        return partial

    # Simple token containment fallback.
    tokens = [t for t in re.split(r"\W+", key) if t]
    token_hits = []
    for loc in locations:
        text = f"{loc.slug} {loc.title}".lower()
        score = sum(1 for t in tokens if t in text)
        if score > 0:
            token_hits.append((score, loc))
    token_hits.sort(key=lambda x: (-x[0], x[1].title.lower()))
    return [x[1] for x in token_hits[:8]]


def select_location_interactive(locations: List[Location], initial_input: str | None = None) -> Location:
    prompt = initial_input
    while True:
        if not prompt:
            prompt = input("Enter your Ster-Kinekor location (e.g. Eastgate): ").strip()
        matches = find_location_matches(prompt, locations)
        if not matches:
            print("No matching location found. Try again.")
            prompt = None
            continue
        if len(matches) == 1:
            return matches[0]

        print("\nMultiple matches found:")
        for i, loc in enumerate(matches[:10], start=1):
            print(f"{i}. {loc.title} ({loc.slug}) - {loc.region}")
        choice = input("Choose location number: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= min(10, len(matches)):
            return matches[int(choice) - 1]
        print("Invalid choice. Try again.")
        prompt = None


def fetch_available_dates(location_slug: str, lookahead_days: int) -> List[Dict[str, Any]]:
    today = dt.date.today()
    out: List[Dict[str, Any]] = []

    for offset in range(max(1, lookahead_days)):
        target = today + dt.timedelta(days=offset)
        page_html = fetch_program_html(location_slug, target)
        movies = parse_movie_showtimes(page_html)
        session_count = sum(len(m["times"]) for m in movies)
        if session_count > 0:
            out.append({"date": target.isoformat(), "movie_count": len(movies), "session_count": session_count})
    return out


def choose_date_interactive(date_options: List[Dict[str, Any]]) -> str:
    print("\nAvailable dates:")
    for i, d in enumerate(date_options, start=1):
        parsed = dt.date.fromisoformat(d["date"])
        label = parsed.strftime("%a, %d %b %Y")
        print(f"{i}. {label} ({d['session_count']} sessions, {d['movie_count']} movies)")

    while True:
        choice = input("Which date would you like to go? Enter number: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(date_options):
            return date_options[int(choice) - 1]["date"]
        print("Invalid choice. Try again.")


def print_result_human(location: Location, selected_date: str, movies: List[Dict[str, Any]]) -> None:
    print(f"\nLocation: {location.title} ({location.slug})")
    print(f"Date: {selected_date}")
    print(f"Movies: {len(movies)}")

    if not movies:
        print("No showtimes found.")
        return

    for movie in movies:
        print(f"\n{movie['title']}")
        print("  " + ", ".join(movie["times"]))


def run_sterkinekor_agent(args: argparse.Namespace) -> int:
    all_locations = fetch_all_locations()
    if not all_locations:
        print("Could not load Ster-Kinekor locations.", file=sys.stderr)
        return 1

    if args.location:
        matches = find_location_matches(args.location, all_locations)
        if not matches:
            print(f"No Ster-Kinekor location match for: {args.location}", file=sys.stderr)
            return 2 if args.non_interactive else 1
        location = matches[0] if len(matches) == 1 else (select_location_interactive(all_locations, args.location) if not args.non_interactive else matches[0])
    else:
        if args.non_interactive:
            print("--location is required when --non-interactive is used.", file=sys.stderr)
            return 2
        location = select_location_interactive(all_locations)

    if args.date:
        try:
            selected_date = dt.date.fromisoformat(args.date).isoformat()
        except ValueError:
            print("Error: --date must be YYYY-MM-DD", file=sys.stderr)
            return 2
    else:
        date_options = fetch_available_dates(location.slug, lookahead_days=max(1, args.lookahead))
        if not date_options:
            print("No available dates found in the selected lookahead window.", file=sys.stderr)
            return 1
        if args.non_interactive:
            selected_date = date_options[0]["date"]
        else:
            selected_date = choose_date_interactive(date_options)

    movies = parse_movie_showtimes(fetch_program_html(location.slug, dt.date.fromisoformat(selected_date)))
    result = {
        "provider": "sterkinekor_scrape",
        "location": {"slug": location.slug, "title": location.title, "region": location.region},
        "date": selected_date,
        "movie_count": len(movies),
        "movies": movies,
        "as_of_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=True))
    else:
        print_result_human(location, selected_date, movies)
    return 0


def main() -> int:
    args = parse_args()
    try:
        return run_sterkinekor_agent(args)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore") if hasattr(exc, "read") else str(exc)
        print(f"HTTP error: {exc.code} {body[:300]}", file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        print(f"Network error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nCancelled.")
        return 130
    except Exception as exc:
        print(f"Unexpected error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
