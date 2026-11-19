#!/usr/bin/env bash
# Fetch the sentry-godot addon (crash reports, game/autoload/crash.gd) into the git-ignored addons/sentry.
# Pinned version and checksum; desktop and Android binaries only. Quiet: errors and one summary line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2.5.1"
ASSET="sentry-godot-2.5.1%2Bd30e663.zip"
SHA256="b639df4d50c4f00f6e57f26fc126640fa4a29a74050970cbfc0ecc85e5d0b460"
URL="https://github.com/getsentry/sentry-godot/releases/download/${VERSION}/${ASSET}"
CACHE="${HOME}/.cache/sentry-godot/sentry-godot-${VERSION}.zip"
DEST="${ROOT}/addons/sentry"
STAMP="${DEST}/.version"

fail() {
	echo "fetch_sentry: $1" >&2
	exit 1
}

if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${VERSION}" ]]; then
	echo "fetch_sentry: ok ${VERSION} (already present)"
	exit 0
fi
command -v curl >/dev/null 2>&1 || fail "curl not found on PATH"
command -v unzip >/dev/null 2>&1 || fail "unzip not found on PATH"

mkdir -p "$(dirname "${CACHE}")"
if [[ ! -f "${CACHE}" ]] || ! echo "${SHA256}  ${CACHE}" | sha256sum -c - >/dev/null 2>&1; then
	curl -fsSL -o "${CACHE}" "${URL}" || fail "download failed: ${URL}"
fi
echo "${SHA256}  ${CACHE}" | sha256sum -c - >/dev/null 2>&1 || fail "checksum mismatch for ${CACHE}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
unzip -q "${CACHE}" -d "${TMP}" || fail "unzip failed"
[[ -f "${TMP}/addons/sentry/sentry.gdextension" ]] || fail "addon not found in the zip"
# The game ships on desktop (and a debug APK); iOS, web and the C# layer are not used.
rm -rf "${TMP}/addons/sentry/bin/ios" "${TMP}/addons/sentry/bin/web" "${TMP}/addons/sentry/web" "${TMP}/addons/sentry/dotnet"
rm -rf "${DEST}"
mkdir -p "${ROOT}/addons"
mv "${TMP}/addons/sentry" "${DEST}"
echo "${VERSION}" >"${STAMP}"
echo "fetch_sentry: ok ${VERSION}"
