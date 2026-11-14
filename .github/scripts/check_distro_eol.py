#!/usr/bin/env python3
"""Compare the distro-smoke matrix in ci.yml with endoflife.date.

Writes a Markdown report to the path given as argv[2] when the matrix needs
attention (an entry is past end of life, or a supported release is missing) and
leaves the file absent otherwise. Always exits 0 unless the API is unreachable.
"""
import datetime
import json
import re
import sys
import urllib.request

# image repository -> (endoflife.date product, label)
PRODUCTS = {
    "debian": "debian",
    "ubuntu": "ubuntu",
    "fedora": "fedora",
    "rockylinux": "rocky-linux",
    "rockylinux/rockylinux": "rocky-linux",
    "opensuse/leap": "opensuse",
    "alpine": "alpine",
}
# Rolling releases (archlinux:base, opensuse/tumbleweed) are not in PRODUCTS.


def fetch(product):
    url = f"https://endoflife.date/api/{product}.json"
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.load(resp)


def main(ci_path, report_path):
    today = datetime.date.today().isoformat()
    text = open(ci_path, encoding="utf-8").read()
    used = {}  # product -> {cycle: image}
    for image in re.findall(r"^\s*- image:\s*(\S+)", text, re.M):
        repo, _, tag = image.partition(":")
        if repo in PRODUCTS:
            used.setdefault(PRODUCTS[repo], {})[tag] = image

    drop, add = [], []
    for product, cycles in sorted(used.items()):
        releases = {str(r["cycle"]): r for r in fetch(product)}
        for cycle, image in sorted(cycles.items()):
            rel = releases.get(cycle)
            if rel is None:
                drop.append(f"- `{image}`: `{cycle}` is not listed on endoflife.date for {product}; check the tag")
                continue
            eol = rel.get("eol")
            if eol is True or (isinstance(eol, str) and eol <= today):
                drop.append(f"- `{image}`: end of life ({eol}); remove it from the matrix and the README if named there")
        for cycle, rel in releases.items():
            eol = rel.get("eol")
            if eol is True or (isinstance(eol, str) and eol <= today):
                continue
            released = rel.get("releaseDate")
            if cycle not in cycles and isinstance(released, str) and released <= today:
                add.append(f"- {product} `{cycle}` (released {released}, supported until {eol}) has no matrix entry")

    if not drop and not add:
        print("Matrix is current.")
        return
    lines = [f"Checked against https://endoflife.date on {today}.", ""]
    if drop:
        lines += ["### Drop (end of life)", *drop, ""]
    if add:
        lines += ["### Add (supported, not tested)", *add, ""]
    lines += ["Edit the `distro-smoke` matrix in `.github/workflows/ci.yml` and its EOL comments, then update the "
              "README and CHANGELOG. This issue is kept up to date by `distro-eol.yml` and closes itself once the "
              "matrix is current."]
    open(report_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
