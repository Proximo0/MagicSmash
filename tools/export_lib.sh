#!/usr/bin/env bash
# Shared by tools/export_windows.sh and tools/export_linux.sh (source it, then call export_build).
# export_build <windows|linux> [--playtest]: export the desktop preset into build/<platform>[-playtest]/, write
# THIRD_PARTY_NOTICES.txt beside it, zip it to build/<slug>-<platform>[-playtest].zip. Quiet: errors (the last 20
# lines of the engine's output) and one summary line. docs/release_build.md.

PROJECT_NAME="Four of Wands"
PROJECT_SLUG="Four-of-Wands"  # no spaces: used for file names
GODOT_VERSION="4.7.2"
TEMPLATE_TAG="4.7.2-stable"
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
TPZ_URL="https://github.com/godotengine/godot/releases/download/${TEMPLATE_TAG}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
CACHE_DIR="${HOME}/.cache/godot-templates"
TPZ_PATH="${CACHE_DIR}/export_templates.tpz"

export_fail() {
	echo "export_${PLATFORM:-build} (${PROJECT_NAME}): $1" >&2
	exit 1
}

# export_tail <label> <log>: the last 20 lines of an engine log, then fail.
export_tail() {
	echo "--- last 20 lines of the engine output ---" >&2
	tail -n 20 "$2" >&2
	export_fail "$1"
}

export_build() {
	PLATFORM="$1"
	local playtest=""
	[[ "${2:-}" == "--playtest" ]] && playtest="-playtest"
	local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	local preset template ext
	case "${PLATFORM}${playtest}" in
		windows) preset="Windows Desktop" ;;
		windows-playtest) preset="Windows Desktop Playtest" ;;
		linux) preset="Linux" ;;
		linux-playtest) preset="Linux Playtest" ;;
		*) export_fail "unknown platform ${PLATFORM}" ;;
	esac
	if [[ "${PLATFORM}" == "windows" ]]; then template="windows_release_x86_64.exe"; ext=".exe"; else template="linux_release.x86_64"; ext=".x86_64"; fi
	local outdir="build/${PLATFORM}${playtest}"
	local bin="${outdir}/${PROJECT_SLUG}${ext}"
	local zip_out="build/${PROJECT_SLUG}-${PLATFORM}${playtest}.zip"

	for c in godot unzip zip curl; do command -v "$c" >/dev/null 2>&1 || export_fail "$c not found on PATH"; done

	if [[ ! -f "${TEMPLATE_DIR}/${template}" ]]; then
		mkdir -p "${TEMPLATE_DIR}" "${CACHE_DIR}"
		if [[ ! -f "${TPZ_PATH}" ]]; then
			curl -sSfL --retry 3 -o "${TPZ_PATH}.part" "${TPZ_URL}" || export_fail "template download failed (${TPZ_URL})"
			mv "${TPZ_PATH}.part" "${TPZ_PATH}"
		fi
		# The tpz is a zip with a templates/ folder. Extract only this platform's templates. The tpz stays cached.
		unzip -q -o -j "${TPZ_PATH}" "templates/${PLATFORM}_*" -d "${TEMPLATE_DIR}" >/dev/null 2>&1 || export_fail "template extract failed"
		unzip -q -o -j "${TPZ_PATH}" 'templates/version.txt' -d "${TEMPLATE_DIR}" >/dev/null 2>&1 || true
		[[ -f "${TEMPLATE_DIR}/${template}" ]] || export_fail "${template} missing after extract"
	fi

	cd "${root}"
	# The Windows file and product version in export_presets.cfg follow G.VERSION (x.y.z becomes x.y.z.0).
	local ver; ver="$(sed -n 's/^const VERSION := "\(.*\)"/\1/p' game/autoload/g.gd)"
	if [[ "${PLATFORM}" == "windows" ]] && ! grep -q "^application/file_version=\"${ver}.0\"" export_presets.cfg; then
		export_fail "export_presets.cfg file_version/product_version must be \"${ver}.0\" (G.VERSION in game/autoload/g.gd)"
	fi
	rm -rf "${outdir}"
	mkdir -p "${outdir}"
	local log; log="$(mktemp)"
	# Crash reports (docs/sentry.md): the addon is fetched, not in git. Without it the build still works, unreported.
	local sentry="yes"
	if ! tools/fetch_sentry.sh >/dev/null; then
		sentry="no"
		echo "export_${PLATFORM} (${PROJECT_NAME}): sentry addon missing, this build sends no crash reports" >&2
	fi
	if [[ "${sentry}" == "yes" ]] && ! godot --headless --path . --import >"${log}" 2>&1; then
		export_tail "godot import failed after fetching the sentry addon" "${log}"
	fi
	if ! godot --headless --path . --export-release "${preset}" "${bin}" >"${log}" 2>&1; then
		export_tail "godot export failed (preset ${preset})" "${log}"
	fi
	[[ -f "${bin}" ]] || export_tail "binary not produced at ${bin}" "${log}"
	if ! godot --headless --path . -s tools/tool.gd -- notices "${outdir}/THIRD_PARTY_NOTICES.txt" >"${log}" 2>&1; then
		export_tail "notices tool failed" "${log}"
	fi
	rm -f "${log}"
	# Mode launchers (test bypasses such as "unlock all") ship only with a playtest build.
	if [[ -n "${playtest}" && "${PLATFORM}" == "windows" ]]; then cp "${root}"/tools/windows/*.bat "${outdir}/" 2>/dev/null || true; fi
	# Online-service credentials (docs/online.md), when the owner has them: next to the binary, where the game looks
	# after res://config/. The git-ignored source files stay out of git.
	rm -f "${outdir}"/*credentials*
	for c in "${root}"/config/*credentials*; do
		if [[ -f "$c" ]]; then cp "$c" "${outdir}/"; fi
	done

	rm -f "${zip_out}"
	(cd build && zip -q -r "$(basename "${zip_out}")" "$(basename "${outdir}")") || export_fail "zip not produced"
	[[ -f "${zip_out}" ]] || export_fail "zip not produced"
	local kind="release"; [[ -n "${playtest}" ]] && kind="playtest"
	echo "export_${PLATFORM}: ok ${zip_out} dir=${outdir} sentry=${sentry} kind=${kind}"
}
