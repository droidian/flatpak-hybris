#!/bin/bash

FLATPAK="/usr/bin/flatpak.real"

error() {
	echo "E: $@" >&2
	exit 1
}

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
if [ $(getconf LONG_BIT) == 32 ]; then
	LIBDIR="lib"
else
	LIBDIR="lib64"
fi

[ -z "${HYBRIS_LD_LIBRARY_PATH}" ] && \
	HYBRIS_LD_LIBRARY_PATH="/system/${LIBDIR}:/vendor/${LIBDIR}:/odm/${LIBDIR}"

if [[ "$@" =~ 'run ' ]]; then
	# Flatpak should be ran, ensure we attach our own arguments
	shift

	# Ensure we use the hybris extension
	export FLATPAK_GL_DRIVERS="hybris"

	# 2025-03-20: blacklist ngl/gl renderer on GNOME 48 runtime on Adreno
	# Do only 48 for now, let's evaluate in future
	if [ "${FLATPAK_HYBRIS_SKIP_BLACKLIST}" != "1" ]; then
		app=$(echo " $@ " | grep -oP ' [^- ].+? ')
		runtime="$(flatpak info ${app} --show-runtime)"
		if [[ "${runtime}" =~ org.gnome.Platform/.*?/48 ]] && eglinfo -a gles -B -p wayland | grep -q Adreno; then
			GSK_RENDERER="cairo"
		fi
	fi

	exec ${FLATPAK} \
		--filesystem=/system:ro \
		--filesystem=/vendor:ro \
		--filesystem=/odm:ro \
		--filesystem=/apex:ro \
		--filesystem=/android:ro \
		--device=all \
		--env=HYBRIS_EGLPLATFORM_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris \
		--env=HYBRIS_LINKER_DIR=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris/linker \
		--env=HYBRIS_LD_LIBRARY_PATH=${HYBRIS_LD_LIBRARY_PATH} \
		--env=LD_LIBRARY_PATH=/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR}/libhybris-egl:/usr/lib/${TRIPLET}/GL/hybris/${LIBDIR} \
		--env=LD_PRELOAD="${LD_PRELOAD}" \
		--env=GSK_RENDERER="${GSK_RENDERER}" \
		run $@
else
	# Pass-through to the real executable
	exec ${FLATPAK} $@
fi
