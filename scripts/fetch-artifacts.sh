#!/usr/bin/env bash
# Downloads the latest release assets (installer + latest.yml / latest-mac.yml)
# from a GitHub release into ./public, which Render serves as a static site.
#
# Required env vars (set in render.yaml / Render dashboard):
#   GITHUB_REPO   - "owner/repo" that holds the release artifacts
#   GITHUB_TOKEN  - optional, only needed for a PRIVATE release repo
#
# Runs as the Render build command. On each deploy it pulls whatever is in the
# latest GitHub release, so release -> deploy -> update is fully scriptable.

set -euo pipefail

REPO="${GITHUB_REPO:-}"
if [[ -z "$REPO" ]]; then
  echo "error: GITHUB_REPO is not set (format: owner/repo)" >&2
  exit 1
fi

mkdir -p public

AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

echo "Fetching latest release from ${REPO} ..."
RELEASE_JSON="$(curl -fsSL "${AUTH[@]+"${AUTH[@]}"}" "https://api.github.com/repos/${REPO}/releases/latest")"

ASSETS="$(
  printf '%s\n' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
)"

if [[ -z "$ASSETS" ]]; then
  echo "error: the latest release has no assets to download" >&2
  exit 1
fi

while IFS= read -r url; do
  [[ -n "$url" ]] || continue
  name="$(basename "$url")"
  echo "Downloading ${name} ..."
  # --location-trusted keeps the auth header across GitHub's CDN redirect
  # (required for private release repos)
  curl -fsSL --location-trusted "${AUTH[@]+"${AUTH[@]}"}" -o "public/${name}" "$url"
done <<< "$ASSETS"

# GitHub stores uploaded assets with spaces replaced by dots
# (e.g. "AceOffice.Setup.0.4.0.exe"). latest.yml's "path:" keeps the real
# spaced filename that the app will request, so rename the installer to match.
INSTALLER_PATH="$(grep -E '^path:' public/latest.yml | sed 's/^path:[[:space:]]*//; s/^"//; s/"$//' || true)"
if [[ -n "$INSTALLER_PATH" ]]; then
  for f in public/*.exe; do
    [[ -e "$f" ]] || continue
    if [[ "$(basename "$f")" != "$INSTALLER_PATH" ]]; then
      echo "Renaming $(basename "$f") -> ${INSTALLER_PATH}"
      mv -f "$f" "public/${INSTALLER_PATH}"
    fi
    break
  done
  # Stable download URL for the website: always serves the newest installer
  # so the "Download" button never needs editing after a release.
  echo "Copying ${INSTALLER_PATH} -> AceOffice-Setup-latest.exe"
  cp -f "public/${INSTALLER_PATH}" "public/AceOffice-Setup-latest.exe"
fi

echo "Serving:"
ls -lh public/
