#!/usr/bin/env bash
# Moves the masonry change in your karakeepin fork onto a newer Karakeep
# release and re-exports patches/masonry.patch from it.
#
# Usage: scripts/refresh-patch.sh [--push] [release-tag]
#   release-tag  Karakeep release to move to, e.g. v0.34.0
#                (default: the latest release, looked up with the GitHub CLI)
#   --push       Commit and push the refreshed patch, which starts a build
#
# The fork is expected next to this repo (../karakeepin); set KARAKEEPIN_DIR
# to use a different location.
set -euo pipefail

push=false
new_base=""
for arg in "$@"; do
  case "$arg" in
    --push) push=true ;;
    -h | --help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) new_base="$arg" ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fork="${KARAKEEPIN_DIR:-$here/../karakeepin}"
patch="$here/patches/masonry.patch"
base_file="$here/patches/BASE_TAG"
branch=masonry
old_base="$(cat "$base_file")"

if [[ -z "$new_base" ]]; then
  new_base="$(gh api repos/karakeep-app/karakeep/releases/latest --jq .tag_name)"
fi
echo "Patch is based on $old_base; target release is $new_base."

cd "$fork"
if ! git remote get-url upstream > /dev/null 2>&1; then
  git remote add upstream https://github.com/karakeep-app/karakeep.git
fi
git fetch --quiet --no-tags upstream tag "$old_base"
if [[ "$new_base" != "$old_base" ]]; then
  git fetch --quiet --no-tags upstream tag "$new_base"
fi
if ! git merge-base --is-ancestor "$old_base" "$new_base"; then
  echo "$new_base is not newer than $old_base; refusing to move the patch back." >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "refs/heads/$branch" > /dev/null; then
  # No local branch (e.g. a fresh clone): rebuild it from the saved patch
  echo "Recreating the '$branch' branch from the saved patch..."
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Your fork has uncommitted changes; commit or stash them first." >&2
    exit 1
  fi
  git switch --quiet -c "$branch" "$old_base"
  git apply --index "$patch"
  git commit --quiet --no-verify -m "feat(web): pinterest-style masonry cards"
fi

if git merge-base --is-ancestor "$new_base" "$branch"; then
  echo "'$branch' already contains $new_base; skipping the rebase."
else
  echo "Rebasing '$branch' onto $new_base..."
  if ! git rebase --autostash --onto "$new_base" "$old_base" "$branch"; then
    cat >&2 << EOF

The masonry change conflicts with $new_base. To finish:
  1. cd "$fork"
  2. Fix the conflicting files listed above, then: git add <files>
  3. git rebase --continue
  4. Re-run this script with the same arguments (it will skip the rebase).
EOF
    exit 1
  fi
fi

git diff --no-color "$new_base" "$branch" -- apps/web > "$patch"
echo "$new_base" > "$base_file"
echo "Exported $(grep -c '^diff --git' "$patch") changed files to patches/masonry.patch (base $new_base)."

cd "$here"
if [[ -z "$(git status --porcelain -- patches)" ]]; then
  echo "The patch is unchanged."
  exit 0
fi

if $push; then
  git add patches
  git commit --quiet -m "Refresh masonry patch for Karakeep $new_base"
  git push --quiet
  echo "Pushed. A new image build has started: gh run watch"
else
  echo "Review with 'git diff', then commit and push to start a build (or re-run with --push)."
fi
