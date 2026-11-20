#!/usr/bin/env bash
# Moves patches/masonry.patch onto a newer Karakeep release.
#
# Usage: scripts/refresh-patch.sh [--push] [release-tag]
#   release-tag  Karakeep release to move to, e.g. v0.36.0
#                (default: the latest release, looked up with the GitHub CLI)
#   --push       Commit the refreshed patch and push the current branch
#
# The patch file is the only copy of the change. This script downloads
# Karakeep into .work/karakeep (ignored by git), rebuilds the change there
# from the patch, moves it onto the new release and exports it again.
# Set KARAKEEP_WORK_DIR to use a different folder.
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
work="${KARAKEEP_WORK_DIR:-$here/.work/karakeep}"
patch="$here/patches/masonry.patch"
base_file="$here/patches/BASE_TAG"
branch=masonry
old_base="$(cat "$base_file")"

if [[ -z "$new_base" ]]; then
  new_base="$(gh api repos/karakeep-app/karakeep/releases/latest --jq .tag_name)"
fi
echo "Patch is based on $old_base; target release is $new_base."

if [[ ! -d "$work/.git" ]]; then
  echo "Downloading Karakeep into $work..."
  mkdir -p "$(dirname "$work")"
  # Without file contents up front; git fetches the ones it needs
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/karakeep-app/karakeep.git "$work"
fi

cd "$work"
git config user.name > /dev/null || git config user.name "refresh-patch"
git config user.email > /dev/null || git config user.email "refresh-patch@localhost"

conflict_help() {
  cat >&2 << EOF

The masonry change conflicts with $new_base. To finish:
  1. Fix the conflicting files listed above, in $work
     (look for the <<<<<<< markers), then: git -C "$work" add <files>
  2. git -C "$work" rebase --continue
  3. Re-run this script with the same arguments (it picks up where it left off).
EOF
}

if [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; then
  echo "A rebase is still in progress in $work." >&2
  conflict_help
  exit 1
fi

git fetch --quiet --no-tags origin tag "$old_base"
if [[ "$new_base" != "$old_base" ]]; then
  git fetch --quiet --no-tags origin tag "$new_base"
fi
if ! git merge-base --is-ancestor "$old_base" "$new_base"; then
  echo "$new_base is not newer than $old_base; refusing to move the patch back." >&2
  exit 1
fi

# Only a conflict fix this script started, for this same patch and releases,
# is picked up again. Anything else is rebuilt from the saved patch, so a
# stale copy of the change can never be used.
marker=.git/masonry-refresh
job="$old_base $new_base $(git hash-object "$patch")"
if [[ -f "$marker" && "$(cat "$marker")" == "$job" ]] &&
  git merge-base --is-ancestor "$new_base" "$branch"; then
  echo "Using the conflicts you fixed in the previous run."
  git switch --quiet "$branch"
else
  git switch --quiet --discard-changes --force-create "$branch" "$old_base"
  git apply --index "$patch"
  git commit --quiet --no-verify -m "feat(web): pinterest-style masonry cards"
  if [[ "$new_base" != "$old_base" ]]; then
    echo "Moving the change onto $new_base..."
    echo "$job" > "$marker"
    if ! git rebase --quiet --onto "$new_base" "$old_base" "$branch"; then
      conflict_help
      exit 1
    fi
  fi
fi
rm -f "$marker"

git diff --no-color "$new_base" "$branch" -- apps/web > "$patch"
echo "$new_base" > "$base_file"
echo "Exported $(grep -c '^diff --git' "$patch") changed files to patches/masonry.patch (base $new_base)."

cd "$here"
if [[ -z "$(git status --porcelain -- patches)" ]]; then
  echo "The patch is unchanged."
  exit 0
fi

if $push; then
  current="$(git branch --show-current)"
  git add patches
  git commit --quiet -m "Refresh masonry patch for Karakeep $new_base"
  git push --quiet -u origin "$current"
  if [[ "$current" == "main" ]]; then
    echo "Pushed to main. The real image build has started: gh run watch"
  else
    echo "Pushed '$current'. Start a test build: gh workflow run build.yml --ref $current"
  fi
else
  echo "Review with 'git diff', then commit and push (or re-run with --push)."
fi
