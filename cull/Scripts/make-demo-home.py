#!/usr/bin/env python3
"""Builds a stand-in home folder for trying Cull without touching your real one.

    python3 Scripts/make-demo-home.py /tmp/cull-demo            # about 12 GB of realistic clutter
    python3 Scripts/make-demo-home.py /tmp/cull-demo --scale 0.01   # the same shape, 1/100 the size

Then point Cull at it. CULL_DAYS_AHEAD makes Cull believe time has passed, so everything in the
folder is stale except what this script marks as freshly used:

    CULL_HOME=/tmp/cull-demo/home CULL_DAYS_AHEAD=400 swift run cull
    CULL_HOME=/tmp/cull-demo/home CULL_DAYS_AHEAD=400 open build/Cull.app   (use `open --env` on macOS)

Files hold real bytes: Cull measures what is allocated on disk, so sparse files would weigh nothing.
"""
import argparse
import os
import plistlib
import shutil
import sys
import time

MB = 1_000_000
CHUNK = bytes(1_000_000)
DAYS_AHEAD = 400


class Home:
    def __init__(self, root, scale):
        self.root = root
        self.scale = scale
        self.written = 0

    def path(self, relative):
        return os.path.join(self.root, relative)

    def file(self, relative, megabytes=0.004, exact=False):
        """Writes a file of roughly `megabytes` (scaled unless `exact`)."""
        full = self.path(relative)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        size = int(megabytes * MB * (1 if exact else self.scale))
        size = max(size, 1)
        with open(full, "wb") as handle:
            remaining = size
            while remaining > 0:
                piece = CHUNK[: min(len(CHUNK), remaining)]
                handle.write(piece)
                remaining -= len(piece)
        self.written += size
        return full

    def text(self, relative, contents=""):
        full = self.path(relative)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as handle:
            handle.write(contents)
        return full

    def plist(self, relative, value):
        full = self.path(relative)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as handle:
            plistlib.dump(value, handle)

    def fresh(self, relative, days_ago=1.0):
        """Marks something as used `days_ago` before the pretend "now"."""
        stamp = time.time() + (DAYS_AHEAD - days_ago) * 86_400
        os.utime(self.path(relative), (stamp, stamp))


def build(home):
    derived = "Library/Developer/Xcode/DerivedData"
    support = "Library/Application Support"

    # --- Safe -------------------------------------------------------------------------------
    home.file(".npm/_cacache/content-v2/sha512/aa/blob", 2_300)
    home.file(".npm/_logs/2026-debug-0.log", 6)
    home.file("Library/Caches/Homebrew/downloads/node--24.tar.gz", 1_400)
    home.file("Library/Caches/pip/http-v2/a/b/c/wheel", 640)
    home.file("Library/Caches/org.swift.swiftpm/repositories/swift-collections/objects/pack", 380)
    home.file("Library/Caches/Yarn/v6/npm-react/node_modules/react/index.js", 510)
    home.file("Library/Caches/CocoaPods/Pods/Release/Alamofire/x", 120)

    home.file("Library/Caches/com.spotify.client/Data/chunk", 1_900)
    home.file("Library/Caches/com.figma.Desktop/Cache/data", 420)
    home.file("Library/Caches/Google/Chrome/Default/Cache/Cache_Data/data_1", 760)
    home.file("Library/Caches/com.apple.Safari/WebKitCache/x", 50)      # macOS's own: never offered
    home.file("Library/Caches/com.apple.bird/session.db", 20)

    home.file(f"{support}/Slack/Cache/Cache_Data/data_1", 310)
    home.file(f"{support}/Slack/Service Worker/CacheStorage/abc/1", 540)
    home.file(f"{support}/Slack/Code Cache/js/index", 40)
    home.file(f"{support}/Slack/Local Storage/leveldb/000005.ldb", 3)   # not cache: stays
    home.file(f"{support}/Code/CachedData/abc/main.code", 290)
    home.file(f"{support}/Code/GPUCache/data_0", 12)
    home.file(f"{support}/Code/User/settings.json", 0.002)
    home.file(f"{support}/Google/Chrome/Default/Code Cache/js/x", 460)
    home.file(f"{support}/Google/Chrome/Default/History", 9)

    home.file("Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit/NetworkCache/x", 880)
    home.file("Library/Caches/com.apple.dt.Xcode/Downloads/x", 230)
    home.file("Library/Developer/CoreSimulator/Caches/dyld/x", 1_100)
    home.file("Library/Logs/DiagnosticReports/Xcode-2026-01-04.ips", 24)
    home.file("Library/Logs/CoreSimulator/ABCD/system.log", 75)

    # --- Rebuildable ------------------------------------------------------------------------
    for name, megabytes in [("Wayfinder", 3_100), ("Tuner", 2_400), ("Journal", 1_250), ("Flipbook", 610)]:
        folder = f"{derived}/{name}-{'abcdefghijklmnopqrstuvwxyzab'}"
        home.file(f"{folder}/Build/Products/Debug/{name}.app/{name}", megabytes)
        home.plist(f"{folder}/info.plist", {"WorkspacePath": home.path(f"Developer/{name}/{name}.xcodeproj")})
    active = f"{derived}/Archivist-bcdefghijklmnopqrstuvwxyzabc"
    home.file(f"{active}/Build/Products/Debug/Archivist.app/Archivist", 2_700)
    home.fresh(f"{active}/Build/Products/Debug/Archivist.app/Archivist", 0.5)
    home.file(f"{derived}/ModuleCache.noindex/3ABC/Foundation.pcm", 1_300)

    ios = "Library/Developer/Xcode/iOS DeviceSupport"
    home.file(f"{ios}/iPhone15,2 17.5 (21F90)/Symbols/dyld", 2_600)
    home.file(f"{ios}/iPhone17,1 18.5 (22F76)/Symbols/dyld", 2_900)
    home.file(f"{ios}/iPhone18,1 26.1 (23B85)/Symbols/dyld", 3_300)
    home.fresh(f"{ios}/iPhone15,2 17.5 (21F90)", 320)
    home.fresh(f"{ios}/iPhone17,1 18.5 (22F76)", 140)
    home.fresh(f"{ios}/iPhone18,1 26.1 (23B85)", 12)
    home.file("Library/Developer/Xcode/UserData/Previews/Simulator Devices/ABCD/data/x", 940)

    for project, megabytes in [("gallery-site", 870), ("neighborhood-site", 520), ("portfolio-next", 1_150)]:
        home.text(f"Developer/{project}/package.json", "{}")
        home.text(f"Developer/{project}/package-lock.json", "{}")
        home.text(f"Developer/{project}/src/App.tsx", "export default function App() { return null }\n")
        home.file(f"Developer/{project}/node_modules/react/index.js", megabytes)
    home.file("Developer/portfolio-next/.next/cache/webpack/client.pack", 380)
    # Being worked on right now: offered, not pre-selected.
    home.text("Developer/journal-web/package.json", "{}")
    home.text("Developer/journal-web/package-lock.json", "{}")
    home.text("Developer/journal-web/src/main.tsx", "")
    home.fresh("Developer/journal-web/src/main.tsx", 0.2)
    home.file("Developer/journal-web/node_modules/vite/index.js", 430)
    home.text("Developer/floorplan/pyproject.toml", "[project]\nname = \"floorplan\"\n")
    home.text("Developer/floorplan/uv.lock", "version = 1\n")
    home.text("Developer/floorplan/.venv/pyvenv.cfg", "home = /usr/bin\n")
    home.file("Developer/floorplan/.venv/lib/python3.13/site-packages/numpy/core.so", 690)
    home.file("Library/Caches/ms-playwright/chromium-1187/chrome-mac/Chromium", 480)

    # --- Your call --------------------------------------------------------------------------
    home.file(".Trash/Screen Recording 2026-02-11.mov", 1_700)
    home.file(".Trash/old-export.zip", 300)
    home.file("Downloads/Xcode_26.2.xip", 3_400)
    home.file("Downloads/ubuntu-24.04-desktop-arm64.iso", 2_800)
    home.file("Downloads/reference-photos/IMG_0042.heic", 640)
    home.file("Downloads/lease-agreement.pdf", 2)
    home.file("Downloads/just-downloaded.zip", 90)
    home.fresh("Downloads/just-downloaded.zip", 0.1)
    backup = f"{support}/MobileSync/Backup/00008140-000A1B2C3D4E5F6A"
    home.file(f"{backup}/Manifest.db", 4_200)
    home.plist(f"{backup}/Info.plist", {"Device Name": "iPhone", "Product Name": "iPhone 15 Pro"})
    home.file("Library/Developer/Xcode/Archives/2025-09-14/Archivist 9-14-25, 4.02 PM.xcarchive/dSYMs/x", 310)

    # --- Never offered ----------------------------------------------------------------------
    home.file("Documents/Sketchbook/maquette-notes.pdf", 12)
    home.file("Pictures/studio/bronze-01.heic", 30)
    home.file("Library/Messages/chat.db", 40)
    home.text(".ssh/config", "Host *\n")
    home.text(".zshrc", "")
    home.text("Developer/gallery-site/.env", "KEY=value\n")
    home.text("Developer/gallery-site/.git/HEAD", "ref: refs/heads/main\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", help="where to build it; a `home` folder is created inside")
    parser.add_argument("--scale", type=float, default=0.25, help="size multiplier (1.0 is about 48 GB, default 0.25)")
    parser.add_argument("--force", action="store_true", help="replace an existing demo folder")
    arguments = parser.parse_args()

    target = os.path.abspath(arguments.directory)
    marker = os.path.join(target, ".cull-demo")
    if os.path.exists(target):
        if not os.path.exists(marker):
            sys.exit(f"{target} exists and was not made by this script; refusing to touch it.")
        if not arguments.force:
            sys.exit(f"{target} already exists. Pass --force to rebuild it.")
        shutil.rmtree(target)

    os.makedirs(os.path.join(target, "home"))
    open(marker, "w").close()
    home = Home(os.path.join(target, "home"), arguments.scale)
    build(home)
    print(f"Wrote {home.written / 1e9:.2f} GB to {home.root}")
    print(f"Try it:  CULL_HOME='{home.root}' CULL_DAYS_AHEAD={DAYS_AHEAD} swift run cull")


if __name__ == "__main__":
    main()
