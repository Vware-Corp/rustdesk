#!/usr/bin/env bash
set -euo pipefail

required_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: ${name}" >&2
    exit 2
  fi
}

required_env GITLAB_URL
required_env GITLAB_PROJECT_ID
required_env GITLAB_PROJECT_PATH
required_env GITLAB_TOKEN
required_env GITLAB_PACKAGE_NAME
required_env GITLAB_PACKAGE_VERSION
required_env TAG_NAME
required_env GITHUB_SHA

api_base="${GITLAB_URL%/}/api/v4"

curl_json() {
  local method="$1"
  local url="$2"
  shift 2
  curl -fsS \
    -X "$method" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@" \
    "$url"
}

curl_get() {
  local url="$1"
  curl -fsS -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$url"
}

release_name="${GITLAB_RELEASE_NAME:-RustDesk ${TAG_NAME}}"

github_run_url=""
if [ -n "${GITHUB_RUN_ID:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  github_run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

release_description="$(cat <<EOF
Automated build published from GitHub Actions.

- GitHub run: ${github_run_url:-N/A}
- Commit: ${GITHUB_SHA}
- Package: ${GITLAB_PACKAGE_NAME} / ${GITLAB_PACKAGE_VERSION}
EOF
)"

# Create or update release. Provide `ref` so GitLab can create the tag if missing.
create_payload="$(release_name="$release_name" release_description="$release_description" python3 - <<PY
import json, os
print(json.dumps({
  "name": os.environ["release_name"],
  "tag_name": os.environ["TAG_NAME"],
  "ref": os.environ["GITHUB_SHA"],
  "description": os.environ["release_description"],
}))
PY
)"

set +e
create_out="$(curl -sS -w "\n%{http_code}" -X POST \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$create_payload" \
  "${api_base}/projects/${GITLAB_PROJECT_ID}/releases")"
create_rc=$?
set -e

create_body="${create_out%$'\n'*}"
create_code="${create_out##*$'\n'}"

if [ $create_rc -ne 0 ]; then
  echo "$create_body" >&2
  exit 1
fi

if [ "$create_code" = "409" ]; then
  # Update existing release (and refresh description/name).
  update_payload="$(release_name="$release_name" release_description="$release_description" python3 - <<PY
import json, os
print(json.dumps({
  "name": os.environ["release_name"],
  "description": os.environ["release_description"],
}))
PY
)"
  curl_json PUT "${api_base}/projects/${GITLAB_PROJECT_ID}/releases/${TAG_NAME}" --data "$update_payload" >/dev/null
elif [ "$create_code" != "201" ] && [ "$create_code" != "200" ]; then
  echo "Failed to create release (HTTP $create_code):" >&2
  echo "$create_body" >&2
  exit 1
fi

# Delete existing asset links (keeps release clean on reruns).
release_json="$(curl_get "${api_base}/projects/${GITLAB_PROJECT_ID}/releases/${TAG_NAME}")"
api_base="$api_base" release_json="$release_json" python3 - <<PY
import json, os, subprocess
api = os.environ["api_base"]
pid = os.environ["GITLAB_PROJECT_ID"]
tag = os.environ["TAG_NAME"]
token = os.environ["GITLAB_TOKEN"]
release = json.loads(os.environ["release_json"])
links = (((release.get("assets") or {}).get("links")) or [])
for l in links:
  lid = l.get("id")
  if lid is None:
    continue
  url = f"{api}/projects/{pid}/releases/{tag}/assets/links/{lid}"
  subprocess.check_call([
    "curl","-fsS","-X","DELETE",
    "-H",f"PRIVATE-TOKEN: {token}",
    url
  ])
PY

# Find the package id for our (name, version).
packages_json="$(curl_get "${api_base}/projects/${GITLAB_PROJECT_ID}/packages?package_name=${GITLAB_PACKAGE_NAME}&package_type=generic&per_page=100")"
package_id="$(packages_json="$packages_json" python3 - <<PY
import json, os, sys
pkgs = json.loads(os.environ["packages_json"])
target_ver = os.environ["GITLAB_PACKAGE_VERSION"]
matches = [p for p in pkgs if str(p.get("version")) == target_ver]
if not matches:
  print("", end="")
  sys.exit(0)
matches.sort(key=lambda p: (p.get("created_at") or ""), reverse=True)
print(matches[0].get("id") or "", end="")
PY
)"

if [ -z "$package_id" ]; then
  echo "No GitLab package found for ${GITLAB_PACKAGE_NAME}/${GITLAB_PACKAGE_VERSION}. Did uploads run?" >&2
  exit 1
fi

package_files_json="$(curl_get "${api_base}/projects/${GITLAB_PROJECT_ID}/packages/${package_id}/package_files?per_page=100")"
api_base="$api_base" package_files_json="$package_files_json" python3 - <<PY
import json, os, subprocess
files = json.loads(os.environ["package_files_json"])
base = os.environ["GITLAB_URL"].rstrip("/")
proj_path = os.environ["GITLAB_PROJECT_PATH"].strip("/")
pkg = os.environ["GITLAB_PACKAGE_NAME"]
ver = os.environ["GITLAB_PACKAGE_VERSION"]
api = os.environ["api_base"]
pid = os.environ["GITLAB_PROJECT_ID"]
tag = os.environ["TAG_NAME"]
token = os.environ["GITLAB_TOKEN"]

def add_link(name: str, url: str):
  payload = json.dumps({"name": name, "url": url})
  endpoint = f"{api}/projects/{pid}/releases/{tag}/assets/links"
  subprocess.check_call([
    "curl","-fsS","-X","POST",
    "-H",f"PRIVATE-TOKEN: {token}",
    "-H","Content-Type: application/json",
    "--data", payload,
    endpoint,
  ])

for f in files:
  fname = f.get("file_name")
  if not fname:
    continue
  url = f"{base}/{proj_path}/-/packages/generic/{pkg}/{ver}/{fname}"
  add_link(fname, url)
PY
