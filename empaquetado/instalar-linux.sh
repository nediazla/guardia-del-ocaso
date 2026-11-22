#!/bin/sh
set -eu

case "$(uname -s):$(uname -m)" in
    Linux:x86_64) ;;
    *) printf '%s\n' 'Este instalador requiere Linux x86-64.' >&2; exit 1 ;;
esac

distro=$(
    if [ -r /etc/os-release ]; then
        . /etc/os-release
    elif [ -r /usr/lib/os-release ]; then
        . /usr/lib/os-release
    fi
    printf '%s\n' "${PRETTY_NAME:-${NAME:-Linux}}"
)
printf 'Distribución detectada: %s\n' "$distro"

case "$(getconf GNU_LIBC_VERSION 2>/dev/null || true)" in
    glibc\ *) ;;
    *) printf '%s\n' 'Esta compilación requiere un sistema Linux con glibc.' >&2; exit 1 ;;
esac

data_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}
case "$data_dir" in
    /*) ;;
    *) data_dir="$HOME/.local/share" ;;
esac

game_dir="$data_dir/guardia-del-ocaso"
applications="$data_dir/applications"
stage=$(mktemp -d)
cleanup() {
    for name in guardia-del-ocaso.x86_64 GODOT-LICENSE.txt GODOT-COPYRIGHT.txt; do
        if [ -f "$stage/$name" ]; then
            rm -- "$stage/$name"
        fi
    done
    rmdir -- "$stage"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

payload_line=$(awk '$0 == "__GUARDIA_PAYLOAD__" { print NR + 1; exit }' "$0")
test -n "$payload_line"
tail -n "+$payload_line" "$0" | tar -xzf - -C "$stage"
if ! "$stage/guardia-del-ocaso.x86_64" --headless --version; then
    printf '%s\n' 'El juego requiere glibc 2.28 o posterior y sus bibliotecas de sistema.' >&2
    exit 1
fi

install -d "$game_dir" "$applications"
install -m 755 "$stage/guardia-del-ocaso.x86_64" "$game_dir/"
install -m 644 "$stage/GODOT-LICENSE.txt" "$stage/GODOT-COPYRIGHT.txt" "$game_dir/"
executable="$game_dir/guardia-del-ocaso.x86_64"
escaped=$(printf '%s' "$executable" | sed 's/\\/\\\\\\\\/g; s/["`$]/\\\\&/g; s/%/%%/g')
cat > "$applications/guardia-del-ocaso.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Guardia del Ocaso
Comment=Campaña de tanques de 100 niveles
Exec="$escaped"
Icon=applications-games
Terminal=false
Categories=Game;ActionGame;
DESKTOP

printf 'Instalado en %s\nAbre Guardia del Ocaso desde el menú de aplicaciones.\n' "$game_dir"
exit 0
__GUARDIA_PAYLOAD__
