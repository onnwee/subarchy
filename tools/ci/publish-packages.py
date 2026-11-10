#!/usr/bin/env python3
"""Upload immutable packages from a main CI run; Gitea signs what it serves."""

import io
import os
from pathlib import Path
import sys
import tarfile
import time
import urllib.error
import urllib.request


REGISTRY = "https://git.subcult.tv/api/packages/subculture-collective/arch"
CHANNELS = ("stable", "edge")


def entry(package):
    """A package file's database entry: its name without architecture and suffix."""
    return package.name.removesuffix(".pkg.tar.zst").rsplit("-", 1)[0]


def published(channel):
    """The name-version entries in a channel's database, which is what pacman
    resolves against. A lookup by file name is not enough: the registry
    answers a request for nvidia-580xx-utils-... with
    lib32-nvidia-580xx-utils-..., whose name ends the same way."""
    # The query keeps a stale copy out of the CDN's answer.
    request = urllib.request.Request(
        f"{REGISTRY}/{channel}/x86_64/subarchy.db?ci-check={time.time_ns()}",
        headers={"User-Agent": "subarchy-ci/1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        error.close()
        if error.code == 404:
            return set()  # no database before the channel's first upload
        raise RuntimeError(f"registry lookup returned HTTP {error.code}") from None
    with tarfile.open(fileobj=io.BytesIO(data)) as database:
        return {name.removesuffix("/desc") for name in database.getnames() if name.endswith("/desc")}


def collisions(names):
    """Pairs of package file names where one contains the other. The registry
    finds a file by substring, so with both present it answers 404 for the
    shorter name, and with only the longer one it serves that file instead."""
    return [(a, b) for a in names for b in names if a != b and a in b]


def publish(package, channel, token, listed):
    url = f"{REGISTRY}/{channel}"
    if entry(package) in listed:
        print(f"already published: {channel}/{package.name}")
        return
    # Stream the file, with credentials only in the request header. Never
    # print request objects, response bodies, environment values or the token.
    with package.open("rb") as data:
        request = urllib.request.Request(
            url,
            data=data,
            headers={
                "Authorization": f"token {token}",
                "Content-Type": "application/octet-stream",
                "Content-Length": str(package.stat().st_size),
                "User-Agent": "subarchy-ci/1",
            },
            method="PUT",
        )
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                if response.status != 201:
                    raise RuntimeError(f"upload returned HTTP {response.status}")
        except urllib.error.HTTPError as error:
            error.close()
            if error.code == 413:
                raise RuntimeError(
                    f"{package.name} is over the 100 MB the public route accepts; "
                    "upload it through the origin (docs/package-publishing.md)"
                ) from None
            raise RuntimeError(f"upload returned HTTP {error.code} for {package.name}") from None
    print(f"published: {channel}/{package.name}")


def main():
    if os.environ.get("GITHUB_EVENT_NAME") != "push" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise SystemExit("package publishing requires a push to main")
    token = os.environ.get("SUBARCHY_PACKAGE_TOKEN", "")
    if not token:
        raise SystemExit("SUBARCHY_PACKAGE_TOKEN is missing")
    listed = {channel: published(channel) for channel in CHANNELS}
    packages = sorted(Path("build/packages").glob("*.pkg.tar.zst"))
    if not packages:
        raise SystemExit("no packages to publish")
    for package in packages:
        for channel in CHANNELS:
            publish(package, channel, token, listed[channel])


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["--published"]:
            # Read-only, for the builder: "<channel> <name-version>" per line.
            for channel in CHANNELS:
                for name in sorted(published(channel)):
                    print(channel, name)
        elif sys.argv[1:2] == ["--check-names"]:
            # For the builder, before it builds: file names the registry
            # could not serve side by side.
            clashes = collisions(sys.argv[2:])
            for short, long in clashes:
                print(f"{short} is part of the name {long}; give one a different pkgrel", file=sys.stderr)
            if clashes:
                raise SystemExit("package file names collide in the registry (docs/package-publishing.md)")
        else:
            main()
    except (RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(str(error)) from None
