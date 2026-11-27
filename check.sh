#!/usr/bin/env bash
# Runs `bumpwise upgrade --changed-since` for the GitHub Action. Inputs come from action.yml as INPUT_* variables.
set -uo pipefail

version=${INPUT_VERSION:-1.1.4}
sha=${INPUT_SHA256:-}
base=${INPUT_BASE:-}
project=${INPUT_PROJECT:-.}
work=${RUNNER_TEMP:-/tmp}/bumpwise
mkdir -p "$work"

if [ -z "$base" ]; then
  if [ -z "${BASE_REF:-}" ]; then
    echo "::error::No base revision: set the 'base' input, or run on a pull_request event."
    exit 2
  fi
  base="origin/$BASE_REF"
fi
if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
  echo "::error::Revision '$base' is not in the clone. Use actions/checkout with fetch-depth: 0."
  exit 2
fi
if ! command -v java > /dev/null; then
  echo "::error::Java 17 or later is needed on the PATH (actions/setup-java)."
  exit 2
fi

jar="$work/bumpwise-$version.jar"
if [ ! -f "$jar" ]; then
  if ! curl -fsSL -A "bumpwise-action/1.1.0 curl" "https://gilware.com/bumpwise/cli/bumpwise-$version.jar" -o "$jar.part"; then
    echo "::error::Could not download Bumpwise CLI $version."
    exit 2
  fi
  mv "$jar.part" "$jar"
fi
if [ -n "$sha" ]; then
  if ! echo "$sha  $jar" | sha256sum -c --status; then
    rm -f "$jar"
    echo "::error::SHA-256 of bumpwise-$version.jar does not match."
    exit 2
  fi
else
  echo "::warning::No sha256 input: the downloaded jar is not verified."
fi

if [ -n "${INPUT_BUILD:-}" ]; then
  # Compile against the versions used before the pull request: swap in the base revision's build files, build,
  # then put the pull request's files back. The check compares those classes with the new versions.
  mapfile -t changed < <(git diff --name-only "$base" HEAD -- '*pom.xml' '*.gradle' '*.gradle.kts' '*.versions.toml')
  saved="$work/head-build-files"
  rm -rf "$saved"; mkdir -p "$saved"
  for f in "${changed[@]}"; do
    mkdir -p "$saved/$(dirname "$f")"
    cp "$f" "$saved/$f" 2> /dev/null || true
    git show "$base:$f" > "$f" 2> /dev/null || rm -f "$f"
  done
  echo "Building with the build files of $base: $INPUT_BUILD"
  bash -c "$INPUT_BUILD"
  built=$?
  for f in "${changed[@]}"; do
    if [ -f "$saved/$f" ]; then cp "$saved/$f" "$f"; else rm -f "$f"; fi
  done
  if [ $built -ne 0 ]; then
    echo "::error::The build with the base revision's build files failed (exit code $built)."
    exit 2
  fi
fi

report="$work/report.md"
java -jar "$jar" upgrade --project "$project" --changed-since "$base" --markdown > "$report"
code=$?
cat "$report"
cat "$report" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "exit-code=$code" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "${INPUT_COMMENT:-false}" = "true" ] && [ -n "${PR_NUMBER:-}" ]; then
  marker="<!-- bumpwise-upgrade-check -->"
  body="$work/comment.md"
  { echo "$marker"; cat "$report"; } > "$body"
  existing=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" --paginate \
    --jq ".[] | select(.body | startswith(\"$marker\")) | .id" 2> /dev/null | head -1)
  if [ -n "$existing" ]; then
    gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" -F "body=@$body" > /dev/null \
      || echo "::warning::Could not update the pull request comment."
  else
    gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" -F "body=@$body" > /dev/null \
      || echo "::warning::Could not post the pull request comment (needs pull-requests: write)."
  fi
fi

case $code in
  0) exit 0 ;;
  1) if [ "${INPUT_FAIL:-true}" = "true" ]; then exit 1; fi; exit 0 ;;
  *) echo "::warning::Bumpwise could not tell whether the upgrades are safe (exit code $code)."; exit 0 ;;
esac
