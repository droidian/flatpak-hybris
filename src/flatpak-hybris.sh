#!/bin/bash

FLATPAK="${FLATPAK_REAL:-/usr/bin/flatpak.real}"

error() {
	echo "E: $*" >&2
	exit 1
}

[ -x "$FLATPAK" ] || error "Unable to execute the real Flatpak binary: $FLATPAK"

# Get triplet
case "$(dpkg --print-architecture)" in
	"amd64")
		TRIPLET="x86_64-linux-gnu"
		;;
	"i386")
		TRIPLET="i386-linux-gnu"
		;;
	"arm64")
		TRIPLET="aarch64-linux-gnu"
		;;
	"armhf")
		TRIPLET="arm-linux-gnueabihf"
		;;
	*)
		error "Unable to obtain triplet"
		;;
esac

# Get libdir
if [ "$(getconf LONG_BIT)" = 32 ]; then
	LIBDIR="lib"
else
	LIBDIR="lib64"
fi

[ -z "${HYBRIS_LD_LIBRARY_PATH:-}" ] && \
	HYBRIS_LD_LIBRARY_PATH="/system/${LIBDIR}:/vendor/${LIBDIR}:/odm/${LIBDIR}"

# Select the hybris extension consistently for both diagnostics and app
# launches, while allowing an explicit administrator override.
export FLATPAK_GL_DRIVERS="${FLATPAK_GL_DRIVERS:-hybris}"

args=("$@")
command_index=-1
for index in "${!args[@]}"; do
	case "${args[$index]}" in
		-*) ;;
		*) command_index=$index; break ;;
	esac
done

if (( command_index >= 0 )) && [ "${args[$command_index]}" = "run" ]; then
	run_args=("${args[@]:command_index + 1}")
	runtime=""

	# Ask Flatpak which non-option token is an installed ref instead of
	# duplicating the evolving `flatpak run` option parser. This handles both
	# --option=value and --option value without modifying argv.
	for candidate in "${run_args[@]}"; do
		case "$candidate" in
			-*) continue ;;
		esac
		candidate_runtime=$("$FLATPAK" info "$candidate" --show-runtime 2>/dev/null || true)
		if [ -n "$candidate_runtime" ]; then
			runtime="$candidate_runtime"
			break
		fi
	done

	# 2025-03-20: blacklist ngl/gl renderer on GNOME 48 runtime on Adreno
	# Do only 48 for now, let's evaluate in future
	gsk_renderer="${GSK_RENDERER:-}"
	if [ "${FLATPAK_HYBRIS_SKIP_BLACKLIST:-0}" != "1" ] && \
	   [[ "$runtime" =~ ^org\.gnome\.Platform/.*/48$ ]] && \
	   command -v eglinfo >/dev/null 2>&1 && \
	   eglinfo -a gles -B -p wayland 2>/dev/null | grep -q Adreno; then
		gsk_renderer="cairo"
	fi

	before_run=("${args[@]:0:command_index + 1}")
	after_run=("${args[@]:command_index + 1}")
	exec "$FLATPAK" \
		"${before_run[@]}" \
		--filesystem=/system:ro \
		--filesystem=/vendor:ro \
		--filesystem=/odm:ro \
		--filesystem=/apex:ro \
		--filesystem=/android:ro \
		--device=all \
		--env="HYBRIS_EGLPLATFORM_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris" \
		--env="HYBRIS_LINKER_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris/linker" \
		--env="HYBRIS_LD_LIBRARY_PATH=${HYBRIS_LD_LIBRARY_PATH}" \
		--env="LD_LIBRARY_PATH=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris-egl:/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}" \
		--env="LD_PRELOAD=${LD_PRELOAD:-}" \
		--env="GSK_RENDERER=${gsk_renderer}" \
		"${after_run[@]}"
fi

exec "$FLATPAK" "${args[@]}"
