#!/usr/bin/env python3
"""Offline package() fixtures; also check notices in real staged roots/archives.

No application build, download, private audit cache or owner configuration needed.
"""
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {"pult": "packaging/pult", "yay": "packaging/aur/yay", "cliamp": "packaging/aur/cliamp"}
BUNDLE = "THIRD-PARTY-NOTICES.txt"
PROVENANCE = "THIRD-PARTY-NOTICES.provenance.json"
# Independent regression anchors from the reviewed upstream texts, not generated
# from the checked-in bundle. All other exact source hashes live in its mapping.
ANCHORS = {
    "pult": [
        "26844e4b53c5adec04e557fd7dfef281cc0205a7d355626b1c68b778b99e9e7b",  # Pelletier TOML
        "a125b6c2721809b6c2a8761771932611833008ed8697d752b3e35d36e4bbd83e",  # HuJSON
        "f6c2dd3a67b576eafb89b80200b8b1627230bf3821a0c14cb99a22ac19107d00",  # YAML NOTICE
        "ae1db56c23dae2c34ff88b79cab71dfaa970485ed5fcc956edd834d20d00c910",  # musl section
    ],
    "yay": [
        "3a64aa4539f34bcf8370feb989228e6bd610e8d0d2991626c86d81ddd779ca31",  # gotext MIT/BSD
        "e54301d602505bd5e95f380a8b0ea05db04738c0b43a4d025f59ce79632f70e2",  # modifications
    ],
    "cliamp": [
        "fc535686ab935d5776543a21c729f3081d53cd50b81ea07f6b1321c20e935ba3",  # xlab
        "eb4df27f95a096a23d88e567331a4bee5590d22185942a1b0456197e29d03e59",  # Lucent
        "a1ecb1a1e1d57c90ccb2455259db836c68942d83a885091bd4375a52e74bec9d",  # V8
        "693ff28ec216d5112ac1bbfe64ef539005867d1c7bd427b57d579683293b947f",  # gRPC NOTICE
    ],
}
ATTRIBUTIONS = {
    "pult": ["Thomas Pelletier", "Canonical Ltd", "Evan Shaw", "Rich Felker", "Yann Collet"],
    "yay": ["Leonel Quinteros", "Jonas Obrist", "DeineAgentur", "gotext maintainers"],
    "cliamp": ["Lucent Technologies", "V8 project authors", "gRPC authors", "Psiphon", "Maxim Kupriianov"],
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recipe_inputs(directory):
    # Source the real recipe, preserving Bash arrays and expansion rules.
    out = subprocess.check_output([
        "bash", "-euc",
        r'source "$1/PKGBUILD"; printf "%s\0" "$pkgver" "$pkgrel"; '
        r'printf "%s\0" "${source[@]}"; printf "\0"; printf "%s\0" "${sha256sums[@]}"',
        "notices", str(directory),
    ])
    parts = out.decode().split("\0")
    split = parts.index("", 2)
    return parts[0], parts[1], parts[2:split], parts[split + 1:-1]


def check_sources(app):
    directory = ROOT / PACKAGES[app]
    version, release, sources, hashes = recipe_inputs(directory)
    assert release == "2", (app, release)
    assert len(sources) == len(hashes), app
    manifest = json.loads((directory / PROVENANCE).read_text())
    bundle = (directory / BUNDLE).read_bytes()
    assert version == manifest["source_version"], app
    assert sources[-2:] == [BUNDLE, PROVENANCE], sources
    for name, expected in zip(sources[-2:], hashes[-2:]):
        assert digest((directory / name).read_bytes()) == expected, name
    assert hashes[0] == manifest["application_source"]["sha256"], app
    assert sources[0].split("::", 1)[1] == manifest["application_source"]["url"], app
    assert digest(bundle) == manifest["bundle"]["sha256"], app
    assert len(bundle) == manifest["bundle"]["bytes"], app
    seen = set()
    for entry in manifest["entries"]:
        data = bundle[entry["offset"]:entry["offset"] + entry["bytes"]]
        assert digest(data) == entry["sha256"], (app, entry["module"], entry["path"])
        reference = entry["module"] + "@" + entry["version"] + ": " + entry["path"]
        assert reference.encode() in bundle, reference
        assert entry["url"].startswith("https://"), entry
        if entry["module"] != "Go toolchain/runtime":
            assert entry["module_h1"].startswith("h1:"), entry
        seen.add(entry["sha256"])
    assert set(ANCHORS.get(app, [])) <= seen, app
    for author in ATTRIBUTIONS[app]:
        assert author.encode() in bundle, (app, author)
    assert b"Copyright 2009 The Go Authors." in bundle, app
    if app == "cliamp":
        xlab = next(e for e in manifest["entries"] if e["module"] == "github.com/xlab/vorbis-go")
        evidence = xlab["later_license_evidence"]
        assert evidence["license_commit"] == "7a1a42804d4d9f8eb7466be0b953c18069c6c271"
        assert evidence["changed_paths"] == ["LICENSE", "go.mod", "go.sum"]
        assert evidence["runtime_source_changed"] is False
    return manifest


def check_staged(app, root, own_licenses=None):
    manifest = check_sources(app)
    directory = root / "usr/share/licenses" / app
    for name in [BUNDLE, PROVENANCE]:
        installed = directory / name
        mode = installed.lstat().st_mode
        assert stat.S_ISREG(mode), installed
        assert stat.S_IMODE(mode) == 0o644, (installed, oct(mode))
        assert installed.read_bytes() == (ROOT / PACKAGES[app] / name).read_bytes(), installed
    expected = own_licenses if own_licenses is not None else {
        e["installed_file"]: e["sha256"] for e in manifest["application_licenses"]
    }
    for name, checksum in expected.items():
        installed = directory / name
        mode = installed.lstat().st_mode
        assert stat.S_ISREG(mode) and stat.S_IMODE(mode) == 0o644, installed
        assert digest(installed.read_bytes()) == checksum, installed


def stage(app, work):
    # Only this package folder is present, like aur/build.sh's /src mount.
    start = work / "package"
    shutil.copytree(ROOT / PACKAGES[app], start)
    src = work / "src"
    src.mkdir()
    for name in [BUNDLE, PROVENANCE]:
        shutil.copyfile(start / name, src / name)
    version, _, _, _ = recipe_inputs(start)
    source_name = "subculture-collective-pult-7a703f1" if app == "pult" else app + "-" + version
    upstream = src / source_name
    upstream.mkdir()
    # Only build outputs and upstream files consumed by package(). A sentinel
    # licence proves package() copies its own upstream input without rewriting it.
    fixtures = [app, "LICENSE"]
    if app == "pult":
        fixtures += ["LICENSES/MIT.txt", "LICENSES/HuJSON-BSD-3-Clause.txt", "README.md"]
    elif app == "cliamp":
        fixtures += ["cliamp.desktop", "Cliamp.png"]
    for name in fixtures:
        dest = upstream / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("upstream fixture: " + app + "/" + name + "\n")
    if app == "yay":
        # The upstream make install also builds/translates; those are outside this
        # offline fixture. Keep the actual recipe and all install commands real.
        (upstream / "Makefile").write_text(
            'install:\n\tinstall -Dm755 yay "$(DESTDIR)$(PREFIX)/bin/yay"\n'
        )
    pkg = work / "pkg"
    pkg.mkdir()
    subprocess.run([
        "bash", "-euc",
        'startdir=$1; srcdir=$2; pkgdir=$3; source "$startdir/PKGBUILD"; cd "$srcdir"; package',
        "notices", str(start), str(src), str(pkg),
    ], check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads((start / PROVENANCE).read_text())
    own = {e["installed_file"]: digest((upstream / e["source_path"]).read_bytes())
           for e in manifest["application_licenses"]}
    return pkg, own


class NoticePackages(unittest.TestCase):
    def test_real_package_functions_and_archive_roundtrip(self):
        for app in PACKAGES:
            with self.subTest(app=app), tempfile.TemporaryDirectory() as temp:
                work = Path(temp)
                pkg, own = stage(app, work)
                check_staged(app, pkg, own)
                # Package permissions and bytes must survive an archive, not just
                # appear in the source folder. No binary build is claimed here.
                archive = work / "staged.tar"
                with tarfile.open(archive, "w") as tar:
                    tar.add(pkg / "usr", arcname="usr")
                with tarfile.open(archive) as tar:
                    for name in [BUNDLE, PROVENANCE, *own]:
                        path = "usr/share/licenses/" + app + "/" + name
                        info = tar.getmember(path)
                        assert info.isfile() and info.mode == 0o644, path
                        assert tar.extractfile(info).read() == (pkg / path).read_bytes(), path

    def test_omission_changed_bytes_unreadable_and_symlink_rejected(self):
        for app in PACKAGES:
            with self.subTest(app=app), tempfile.TemporaryDirectory() as temp:
                pkg, own = stage(app, Path(temp))
                for name in [BUNDLE, PROVENANCE, *own]:
                    path = pkg / "usr/share/licenses" / app / name
                    original = path.read_bytes()
                    path.unlink()
                    with self.assertRaises((AssertionError, FileNotFoundError)):
                        check_staged(app, pkg, own)
                    path.write_bytes(original + b"changed")
                    with self.assertRaises(AssertionError):
                        check_staged(app, pkg, own)
                    path.write_bytes(original)
                    path.chmod(0o600)
                    with self.assertRaises(AssertionError):
                        check_staged(app, pkg, own)
                    path.unlink()
                    path.symlink_to(ROOT / PACKAGES[app] / BUNDLE)
                    with self.assertRaises(AssertionError):
                        check_staged(app, pkg, own)
                    path.unlink()
                    path.write_bytes(original)
                    path.chmod(0o644)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] in ["--staged", "--archive"]:
        app, path = sys.argv[2], Path(sys.argv[3]).resolve()
        if sys.argv[1] == "--staged":
            check_staged(app, path)
        else:
            with tempfile.TemporaryDirectory() as temp:
                subprocess.run(["bsdtar", "-xf", str(path), "-C", temp,
                                "usr/share/licenses/" + app], check=True)
                check_staged(app, Path(temp))
        print(app + ": exact notices, provenance and upstream licences pass")
    else:
        unittest.main()
