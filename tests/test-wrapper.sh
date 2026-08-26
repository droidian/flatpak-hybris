#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper="$root/src/flatpak-hybris.sh"
tmp=$(mktemp -d)
mock="$tmp/flatpak.real"

cleanup() {
	rm -rf -- "$tmp"
}
trap cleanup EXIT HUP INT TERM

cat > "$mock" <<'EOF'
#!/bin/sh
if [ "${1:-}" = info ]; then
	case "${2:-}" in
		com.example.App) echo 'org.gnome.Platform/aarch64/47'; exit 0 ;;
	esac
	exit 1
fi
printf 'driver=<%s>\n' "${FLATPAK_GL_DRIVERS:-}"
index=0
for argument in "$@"; do
	printf 'arg[%s]=<%s>\n' "$index" "$argument"
	index=$((index + 1))
done
EOF
chmod 0755 "$mock"

query_output=$(env -u FLATPAK_GL_DRIVERS \
	FLATPAK_REAL="$mock" "$wrapper" --gl-drivers)
grep -Fq 'driver=<hybris>' <<< "$query_output"
grep -Fq 'arg[0]=<--gl-drivers>' <<< "$query_output"

override_output=$(FLATPAK_GL_DRIVERS=default \
	FLATPAK_REAL="$mock" "$wrapper" --gl-drivers)
grep -Fq 'driver=<default>' <<< "$override_output"

search_output=$(env -u FLATPAK_GL_DRIVERS \
	FLATPAK_REAL="$mock" "$wrapper" search run)
grep -Fq 'arg[0]=<search>' <<< "$search_output"
grep -Fq 'arg[1]=<run>' <<< "$search_output"
if grep -Fq -- '--filesystem=/system:ro' <<< "$search_output"; then
	echo "A non-run command was incorrectly modified." >&2
	exit 1
fi

run_output=$(env -u FLATPAK_GL_DRIVERS \
	FLATPAK_HYBRIS_SKIP_BLACKLIST=1 FLATPAK_REAL="$mock" \
	"$wrapper" -v run --command echo com.example.App 'argument with spaces')
grep -Fq 'driver=<hybris>' <<< "$run_output"
grep -Fq 'arg[0]=<-v>' <<< "$run_output"
grep -Fq 'arg[1]=<run>' <<< "$run_output"
grep -Fq -- '<--filesystem=/system:ro>' <<< "$run_output"
grep -Fq -- '<--device=all>' <<< "$run_output"
grep -Fq '<--command>' <<< "$run_output"
grep -Fq '<echo>' <<< "$run_output"
grep -Fq '<com.example.App>' <<< "$run_output"
grep -Fq '<argument with spaces>' <<< "$run_output"

app_count=$(grep -Fc '<com.example.App>' <<< "$run_output")
if [ "$app_count" -ne 1 ]; then
	echo "Application reference was duplicated or dropped." >&2
	exit 1
fi

echo "flatpak-hybris wrapper tests passed"
