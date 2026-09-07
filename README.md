# Gleamveil modpack

The mod list for `gleamveil.duckdns.org`, in [packwiz](https://packwiz.infra.link/)
format. Friends import one instance zip, once; after that every launch syncs
their mods to whatever is in this repo.

Minecraft **1.21.7**, Fabric loader **0.16.14**, 24 mods, all from Modrinth.

## For friends

1. Install [Prism Launcher](https://prismlauncher.org/) and log in.
2. Get `Gleamveil.zip` from Bruno.
3. Prism → **Add Instance** → **Import from zip** → pick the file.
4. Press Play.

That's it. On every launch the instance checks this repo and downloads,
updates, or removes mods so you match the server. There is no "update" step to
remember and no way to end up on the wrong version.

Don't add or remove mods by hand — the sync reverts them next launch. Ask for
anything you want added to the pack instead.

## For Bruno — changing the pack

Everything below runs from this repo with `packwiz` on PATH
(`go install github.com/packwiz/packwiz@latest`, lands in `%USERPROFILE%\go\bin`).

```powershell
packwiz modrinth add sodium         # add a mod (search by name or slug)
packwiz remove sodium               # remove one
packwiz update --all                # bump everything to newest compatible
packwiz update sodium               # bump just one
packwiz list                        # what's in the pack
packwiz pin sodium                  # freeze a mod at its current version
```

Then publish:

```powershell
packwiz refresh
git add -A
git commit -m "add sodium"
git push
```

Friends get it on their next launch. Nothing to re-send, no new zip.

### Client vs server

Each mod's `side` field decides where it installs — `client`, `server`, or
`both`. Currently 9 are client-only (Sodium, Iris, Litematica, MiniHUD, MaLiLib,
Tweakeroo, Mod Menu, Continuity, Borderless Fullscreen) and 15 are `both`.

That means the server can install from this same pack, so the two can't drift:

```bash
packwiz-installer-bootstrap.jar -g -s server https://<user>.github.io/gleamveil-pack/pack.toml
```

Run that in the server directory as part of the start script and the server's
mods follow the same source of truth as everyone's clients.

### Rebuilding the friend instance zip

Only needed if the Minecraft or Fabric version changes, or the pack URL moves:

```powershell
.\tools\make-friend-instance.ps1 -PackUrl https://<user>.github.io/gleamveil-pack/pack.toml
```

Day-to-day mod changes don't need a new zip.

### Bumping Minecraft or Fabric

`packwiz migrate minecraft <version>` and `packwiz migrate loader` update
`pack.toml`. After that, `packwiz update --all`, rebuild the friend zip with the
new versions, and re-send it — this is the one case friends must re-import.

## Hosting

Served by GitHub Pages from the default branch. Only requirement is that
`pack.toml`, `index.toml`, and `mods/*.pw.toml` are reachable over plain HTTPS.

## Layout

```
pack.toml            pack metadata; points at index.toml by hash
index.toml           lists every file in the pack, by hash
mods/*.pw.toml       one per mod: filename, side, download URL, Modrinth id
tools/               friend-instance builder + packwiz-installer bootstrap jar
```

Each file references the next by hash, so a partial or tampered download fails
loudly instead of installing something wrong.
