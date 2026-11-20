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

`patches/masonry.patch` is the only copy of the change. Nothing else (such as
a fork of Karakeep) needs to be kept up to date.

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

The image is public (it follows this repo's visibility), so the server can
pull it without logging in. If a pull ever asks for credentials, check the
package's visibility under Package settings.

## Updating

Re-pull the image the same way you would for the official one (in CasaOS,
the app's update/rebuild action; with Compose, `docker compose pull && docker compose up -d`).
The `release` tag moves to each new build, usually within a day of an
official release.

## When a build fails

GitHub emails you when a scheduled run fails. The usual cause is an official
release that changed the same lines as the patch; your server keeps running
the last good image in the meantime.

The easiest fix is to ask Claude, in any session on this repository: "The
build is failing for Karakeep vX.Y.Z, please rework the patch on a branch and
give me a test build." Or by hand, on a branch of this repo:

```sh
git switch -c refresh                # work on a branch, not main
scripts/refresh-patch.sh             # moves the change onto the latest release
# If it reports a conflict: fix the files it names (in .work/karakeep),
# `git add` them, `git rebase --continue` there, then run the script again.
git diff                             # review the new patch
scripts/refresh-patch.sh --push      # commits and pushes the branch
gh workflow run build.yml --ref refresh   # test build, see below
```

The script needs `git` and the GitHub CLI (`gh`). It downloads Karakeep into
`.work/karakeep` (ignored by git) and rebuilds the change there from the saved
patch each time, so it works the same on any computer or session.

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

## Testing a patch before it goes live

Commit the new patch on a branch other than `main` and run the workflow on
that branch:

```sh
gh workflow run build.yml --ref my-branch
```

A build from any branch other than `main` is only tagged `test` and
`<version>-test` (e.g. `0.35.0-test`), never `release` or a plain version, so
servers using those tags are left alone. Point a server at
`ghcr.io/pebble66/karakeep-masonry:test` to try it, then merge the branch into
`main`, which builds and publishes the real tags.

## Changing the masonry look

The easiest way is to ask Claude to change the patch and give you a test
build (see above). By hand:

1. Run `scripts/refresh-patch.sh` once. `.work/karakeep` then holds Karakeep
   with the change applied, on a branch called `masonry`.
2. Edit the files under `apps/web/components/dashboard/bookmarks/` there, and
   commit them on `masonry` (`git commit --amend` keeps it as one commit).
3. Export the patch from it, on a branch of this repo:
   `git -C .work/karakeep diff --no-color "$(cat patches/BASE_TAG)" masonry -- apps/web > patches/masonry.patch`
4. Commit, push the branch and start a test build.
