#!/usr/bin/env bash
set -euo pipefail

# Expand globs to empty instead of literal patterns.
shopt -s nullglob

required_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: ${name}" >&2
    exit 2
  fi
}

required_env GITLAB_URL
required_env GITLAB_PROJECT_ID
required_env GITLAB_TOKEN
required_env GITLAB_PACKAGE_NAME
required_env GITLAB_PACKAGE_VERSION

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <file> [file...]" >&2
  exit 2
fi

api_base="${GITLAB_URL%/}/api/v4"

upload_one() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Not a file: $file" >&2
    exit 2
  fi

  local fname
  fname="$(basename "$file")"

  local url
  url="${api_base}/projects/${GITLAB_PROJECT_ID}/packages/generic/${GITLAB_PACKAGE_NAME}/${GITLAB_PACKAGE_VERSION}/${fname}"

  echo "Uploading: ${file} -> ${url}" >&2
  curl -fsS \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --upload-file "$file" \
    "$url" >/dev/null
}

for f in "$@"; do
  upload_one "$f"
done
