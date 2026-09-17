# karakeep-masonry

[Karakeep](https://github.com/karakeep-app/karakeep) with Pinterest-style
masonry cards, built automatically from each official release.

In the **Masonry** layout, image cards show the whole image at its natural
shape instead of a fixed-size box with empty space below it:

- Images keep their natural height, capped at twice the card width (taller
  images are cropped at the bottom).
- Title, tags and notes only appear (and only take space) when enabled in
  View Options. The source site and date are not shown on image cards.
- Expand and ⋯ sit on the image: shown on hover with a mouse, always visible
  on touch screens.
- Notes and other cards without an image keep the normal card look.
- The Grid, List and Compact layouts are unchanged.

## How it works

```
karakeep-app/karakeep          this repo (GitHub Actions)                  your server
publishes a release  ───────►  daily check finds it
                               applies patches/masonry.patch
                               type-checks, builds the Docker image
                               publishes it to GHCR  ───────────────────►  pull the new image
```

- `patches/masonry.patch`: the change, as a diff against the release in
  `patches/BASE_TAG`.
- `.github/workflows/build.yml`: runs daily, whenever the patch changes, and
  on demand. It builds the same `aio` image as the official
  `ghcr.io/karakeep-app/karakeep` (linux/amd64 only) and publishes:
  - `ghcr.io/pebble66/karakeep-masonry:<version>`, e.g. `0.33.2`
  - `ghcr.io/pebble66/karakeep-masonry:release`, always the newest release
- `scripts/refresh-patch.sh`: moves the change onto a newer release when the
  patch stops applying.

The code change itself is edited on the `masonry` branch of
[Pebble66/karakeepin](https://github.com/Pebble66/karakeepin).

## Switching a server to this image

1. **Back up Karakeep's data folder** (the volume mounted at `/data`; on
   CasaOS usually under `/DATA/AppData/karakeep`). Upgrades can change the
   database, so the backup is your way back to an older version.
2. **Upgrade to the official image first** at the same version this repo
   builds (check the latest successful run), and make sure everything works.
   Read the release notes on the way; for example, 0.33.2 recommends
   switching the Chrome container to `ghcr.io/karakeep-app/karakeep-chrome:release`.
3. **Change the Karakeep container's image** from
   `ghcr.io/karakeep-app/karakeep` to `ghcr.io/pebble66/karakeep-masonry`,
   keeping the tag `release`. In CasaOS, this is the image field in the
   Karakeep app's settings. Leave the volumes, environment, Chrome and
   Meilisearch as they are.

The package must be public for the server to pull it without logging in
(one-time: Package settings → Change visibility → Public).

## Updating

Re-pull the image the same way you would for the official one (in CasaOS,
the app's update/rebuild action; with Compose, `docker compose pull && docker compose up -d`).
The `release` tag moves to each new build, usually within a day of an
official release.

## When a build fails

GitHub emails you when a scheduled run fails. The usual cause is an official
release that changed the same lines as the patch; your server keeps running
the last good image in the meantime. To fix it, with the fork checked out
next to this repo (`../karakeepin`):

```sh
scripts/refresh-patch.sh           # moves the change onto the latest release
# If it reports a conflict: fix the files, `git add` them,
# `git rebase --continue` in the fork, then run the script again.
git diff                           # review the new patch
scripts/refresh-patch.sh --push    # or commit and push yourself
```

Pushing a changed patch starts a build. The script needs `git` and the
GitHub CLI (`gh`). If the fork has no local `masonry` branch (for example,
a fresh clone), the script recreates it from the saved patch.

If an urgent official release (such as a security fix) arrives before the
patch is fixed, point the server at the official image of that version;
your data is unaffected and only the layout changes back.

## Rolling back

Switch the image back to `ghcr.io/karakeep-app/karakeep` with the **same
version** tag (e.g. `0.33.2`). This image only changes the web interface, so
the data stays compatible. Going back to an older version needs the backup
from before the upgrade.

## Building manually

```sh
gh workflow run build.yml                        # check for a new release now
gh workflow run build.yml -f tag=v0.33.2 -f force=true   # rebuild a version
gh run watch
```

## Changing the masonry look

1. In the fork, check out `masonry` and edit the files under
   `apps/web/components/dashboard/bookmarks/`.
2. Run the web app locally (Node 24.18.1 and pnpm; see the fork's
   development docs) and check the result.
3. Commit on `masonry`, then run `scripts/refresh-patch.sh --push` here to
   export and publish the new patch.
