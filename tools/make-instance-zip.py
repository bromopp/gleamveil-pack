#!/usr/bin/env python3
"""
Build a Prism/MultiMC instance zip straight from pack.toml.

Why this exists
---------------
Players import a Prism instance zip, and the zip - not the import dialog -
decides which Minecraft and loader versions the new instance gets. Exporting
that zip by hand from a working instance means it silently goes stale the
moment the pack moves to a new Minecraft version: every new player then lands
on the old version, packwiz-installer offers to update it, and accepting that
update trips PrismLauncher#2540 (components other than Minecraft and the loader
are not re-resolved on a version change), leaving LWJGL behind and crashing the
game before the window opens.

Generating the zip from pack.toml removes the staleness by construction: there
is no second copy of the version numbers to forget to update.

The LWJGL trick
---------------
This deliberately writes NO org.lwjgl3 component. In a MultiMC-format pack,
LWJGL is a *dependency* of net.minecraft, and the launcher resolves it from its
own metadata when the instance is created. Pinning it is what causes the
problem; omitting it makes the launcher pick the right one every time, for
whatever Minecraft version the pack currently targets.

packwiz itself cannot do this yet - see packwiz/packwiz#76, still open.

Usage:
    python3 tools/make-instance-zip.py [--pack pack.toml] [--out build/]
"""
import argparse
import json
import os
import re
import shutil
import sys
import urllib.request
import zipfile

BOOTSTRAP_URL = ("https://github.com/packwiz/packwiz-installer-bootstrap/"
                 "releases/latest/download/packwiz-installer-bootstrap.jar")

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None


def _parse_pack_minimally(text):
    """Fallback for Python < 3.11, which has no tomllib.

    Deliberately not a TOML parser. pack.toml's shape is fixed by packwiz:
    top-level `name`/`version` strings and a flat `[versions]` table. Reading
    exactly those four keys with regexes keeps this script runnable on any
    Python 3, which matters because it has to work on a CI runner, on the
    Proxmox host, and on a laptop - all with different Pythons.
    """
    def top(key):
        m = re.search(r'^\s*%s\s*=\s*"([^"]*)"' % key, text, re.M)
        return m.group(1) if m else None

    versions_block = ""
    m = re.search(r'^\[versions\]\s*$(.*?)(?=^\[|\Z)', text, re.M | re.S)
    if m:
        versions_block = m.group(1)

    def ver(key):
        m = re.search(r'^\s*%s\s*=\s*"([^"]*)"' % key, versions_block, re.M)
        return m.group(1) if m else None

    return {
        "name": top("name"),
        "version": top("version"),
        "versions": {"minecraft": ver("minecraft"), "fabric": ver("fabric")},
    }


def read_pack(path):
    if tomllib is not None:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    else:
        with open(path, encoding="utf-8") as f:
            data = _parse_pack_minimally(f.read())
    versions = data.get("versions") or {}
    mc = versions.get("minecraft")
    fabric = versions.get("fabric")
    if not mc:
        sys.exit(f"No [versions].minecraft in {path}")
    if not fabric:
        sys.exit(f"No [versions].fabric in {path} - this script assumes Fabric.")
    return {
        "name": data.get("name") or "Modpack",
        "version": data.get("version") or "0.0.0",
        "minecraft": mc,
        "fabric": fabric,
    }


def mmc_pack(mc, fabric):
    """Minimal component list. See module docstring for why LWJGL is absent."""
    return {
        "formatVersion": 1,
        "components": [
            {"uid": "net.minecraft", "version": mc, "important": True},
            {"uid": "net.fabricmc.fabric-loader", "version": fabric},
        ],
    }


def instance_cfg(name, pack_url):
    # OverrideCommands=true is required, or Prism ignores PreLaunchCommand
    # entirely and the instance silently never syncs its mods.
    return "\n".join([
        "InstanceType=OneSix",
        f"name={name}",
        "OverrideCommands=true",
        f'PreLaunchCommand="$INST_JAVA" -jar packwiz-installer-bootstrap.jar {pack_url}',
        "",
    ])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="pack.toml")
    ap.add_argument("--out", default="build")
    ap.add_argument("--pack-url", default=os.environ.get("PACK_URL", ""),
                    help="Raw URL of pack.toml that clients sync from.")
    ap.add_argument("--bootstrap", default="",
                    help="Path to an existing packwiz-installer-bootstrap.jar "
                         "(downloaded if omitted).")
    args = ap.parse_args()

    if not args.pack_url:
        sys.exit("Need --pack-url (or PACK_URL) - the raw pack.toml URL clients sync from.")

    pack = read_pack(args.pack)
    print(f"{pack['name']} {pack['version']}: Minecraft {pack['minecraft']}, "
          f"Fabric {pack['fabric']}")

    staging = os.path.join(args.out, "instance")
    shutil.rmtree(staging, ignore_errors=True)
    os.makedirs(os.path.join(staging, ".minecraft"), exist_ok=True)

    with open(os.path.join(staging, "mmc-pack.json"), "w") as f:
        json.dump(mmc_pack(pack["minecraft"], pack["fabric"]), f, indent=4)
    with open(os.path.join(staging, "instance.cfg"), "w") as f:
        f.write(instance_cfg(pack["name"], args.pack_url))

    jar = os.path.join(staging, ".minecraft", "packwiz-installer-bootstrap.jar")
    if args.bootstrap:
        shutil.copyfile(args.bootstrap, jar)
        print(f"Bootstrap copied from {args.bootstrap}")
    else:
        print(f"Downloading {BOOTSTRAP_URL}")
        urllib.request.urlretrieve(BOOTSTRAP_URL, jar)
    if os.path.getsize(jar) < 1000:
        sys.exit("Bootstrap jar looks wrong (too small) - aborting.")

    # Zip name goes in a URL players paste into Prism, so keep it boring.
    safe = re.sub(r"[^A-Za-z0-9._-]", "", pack["name"].replace(" ", "")) or "Modpack"
    zip_path = os.path.join(args.out, f"{safe}.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(staging):
            for name in files:
                full = os.path.join(root, name)
                z.write(full, os.path.relpath(full, staging))

    print(f"\nWrote {zip_path}")
    print("Contents:")
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            print(f"  {n}")
    print("\nNo org.lwjgl3 component: the launcher resolves it for "
          f"Minecraft {pack['minecraft']} on import.")


if __name__ == "__main__":
    main()
