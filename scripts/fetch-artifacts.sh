#!/usr/bin/env bash
# Downloads the latest release assets (installer + latest.yml / latest-mac.yml)
# from a GitHub release into ./public, which Vercel/Render serves as a static
# site. Runs as the build command, so release -> deploy -> update is scriptable.
#
# Env vars:
#   GITHUB_REPO   - "owner/repo" that holds the release artifacts (defaults to
#                   this updater repo, which is also where releases live)
#   GITHUB_TOKEN  - optional, only needed for a PRIVATE release repo
#
# Uses the public releases/latest/download endpoint instead of the GitHub API,
# so builds don't fail on a missing GITHUB_REPO or the anonymous API rate limit.

set -euo pipefail

REPO="${GITHUB_REPO:-Linuxthecoder/aceoffice-update-server}"
BASE="https://github.com/${REPO}/releases/latest/download"

mkdir -p public

AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

# GitHub stores uploaded assets with spaces replaced by dots
# (e.g. "AceOffice.Setup.0.4.0.exe"). latest.yml's "path:" keeps the real
# spaced filename that the app will request, so download to that name.
download_asset() {
  local name="$1"
  local dotted="${name// /.}"
  local encoded="${name// /%20}"
  echo "Downloading ${name} ..."
  if curl -fsSL --location-trusted "${AUTH[@]+"${AUTH[@]}"}" \
    -o "public/${name}" "${BASE}/${dotted}"; then
    return 0
  fi
  curl -fsSL --location-trusted "${AUTH[@]+"${AUTH[@]}"}" \
    -o "public/${name}" "${BASE}/${encoded}"
}

FOUND=0
for yml in latest.yml latest-mac.yml; do
  echo "Fetching ${yml} from ${REPO} ..."
  if curl -fsSL --location-trusted "${AUTH[@]+"${AUTH[@]}"}" \
    -o "public/${yml}" "${BASE}/${yml}" 2>/dev/null; then
    FOUND=1
    INSTALLER_PATH="$(grep -E '^path:' "public/${yml}" | head -n1 \
      | sed 's/^path:[[:space:]]*//; s/^"//; s/"$//' || true)"
    if [[ -n "$INSTALLER_PATH" ]]; then
      download_asset "$INSTALLER_PATH"
    fi

    # Stable download URL for the website: always serves the newest Windows
    # installer so the "Download" button never needs editing after a release.
    if [[ "$yml" == "latest.yml" && -n "$INSTALLER_PATH" ]]; then
      echo "Copying ${INSTALLER_PATH} -> AceOffice-Setup-latest.exe"
      cp -f "public/${INSTALLER_PATH}" "public/AceOffice-Setup-latest.exe"
    fi
  else
    rm -f "public/${yml}"
  fi
done

if [[ "$FOUND" -eq 0 ]]; then
  echo "error: the latest release has no latest.yml or latest-mac.yml" >&2
  exit 1
fi

echo "Serving:"
ls -lh public/
