#!/usr/bin/env python3
"""Upload immutable packages from a main CI run; Gitea signs what it serves."""

import os
from pathlib import Path
import time
import urllib.error
import urllib.request


REGISTRY = "https://git.subcult.tv/api/packages/subculture-collective/arch"


def exists(url):
    try:
        # Keep a pre-upload 404 out of the CDN cache for pacman's download URL.
        request = urllib.request.Request(
            f"{url}?ci-check={time.time_ns()}",
            headers={"User-Agent": "subarchy-ci/1"},
            method="HEAD",
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 200:
                raise RuntimeError(f"registry lookup returned HTTP {response.status}")
            return True
    except urllib.error.HTTPError as error:
        error.close()
        if error.code == 404:
            return False
        raise RuntimeError(f"registry lookup returned HTTP {error.code}") from None


def publish(package, channel, token):
    url = f"{REGISTRY}/{channel}"
    if exists(f"{url}/x86_64/{package.name}"):
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
            raise RuntimeError(f"upload returned HTTP {error.code} for {package.name}") from None
    print(f"published: {channel}/{package.name}")


def main():
    if os.environ.get("GITHUB_EVENT_NAME") != "push" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise SystemExit("package publishing requires a push to main")
    token = os.environ.get("SUBARCHY_PACKAGE_TOKEN", "")
    if not token:
        raise SystemExit("SUBARCHY_PACKAGE_TOKEN is missing")
    packages = sorted(Path("build/packages").glob("*.pkg.tar.zst"))
    if not packages:
        raise SystemExit("no packages to publish")
    for package in packages:
        for channel in ("stable", "edge"):
            publish(package, channel, token)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(str(error)) from None
