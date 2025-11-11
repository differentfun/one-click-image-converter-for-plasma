#!/usr/bin/env bash
set -euo pipefail

SERVICE_MENU_NAME="one-click-image-converter.desktop"
PLASMA5_DIR="$HOME/.local/share/kservices5/ServiceMenus"
PLASMA6_DIR="$HOME/.local/share/kio/servicemenus"
RUNNER_PATH="$HOME/.local/bin/one-click-image-converter"
TARGET_DIR=""
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install-service-menu.sh [options]

Options:
  --force          Overwrite an existing service menu with the same name.
  --plasma5        Install into the Plasma 5 service menu directory.
  --plasma6        Install into the Plasma 6 service menu directory.
  --target-dir DIR Install into DIR instead of the default path.
  -h, --help       Show this help message.

The script writes a KDE service menu that adds “Convert to PNG/JPEG” actions
to the Dolphin context menu for image files.
EOF
}

detect_plasma_major_version() {
  if command -v plasmashell >/dev/null 2>&1; then
    local version_line
    version_line="$(plasmashell --version 2>/dev/null | head -n1 || true)"
    if [[ "$version_line" =~ ([0-9]+)\. ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return
    fi
  fi
  printf '\n'
}

ensure_shell_access_allowed() {
  local read_cmd=""
  local write_cmd=""
  if command -v kreadconfig6 >/dev/null 2>&1; then
    read_cmd="kreadconfig6"
  elif command -v kreadconfig5 >/dev/null 2>&1; then
    read_cmd="kreadconfig5"
  fi

  if command -v kwriteconfig6 >/dev/null 2>&1; then
    write_cmd="kwriteconfig6"
  elif command -v kwriteconfig5 >/dev/null 2>&1; then
    write_cmd="kwriteconfig5"
  fi

  if [[ -z "$write_cmd" ]]; then
    echo "Warning: kwriteconfig5/6 not found; cannot automatically enable shell access." >&2
    return
  fi

  local current_value=""
  if [[ -n "$read_cmd" ]]; then
    current_value="$("$read_cmd" --group "KDE Action Restrictions" --key shell_access 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ "$current_value" != "true" ]]; then
    "$write_cmd" --group "KDE Action Restrictions" --key shell_access true
    echo "Enabled shell_access in ~/.config/kdeglobals so Dolphin can run custom service menus."
  fi
}

install_runner() {
  mkdir -p "$(dirname "$RUNNER_PATH")"
  cat <<'EOF' > "$RUNNER_PATH"
#!/usr/bin/env bash
set -euo pipefail

find_converter() {
  if command -v magick >/dev/null 2>&1; then
    command -v magick
    return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    command -v convert
    return 0
  fi
  echo "Error: ImageMagick (magick/convert) not found in PATH." >&2
  exit 1
}

converter_cmd="$(find_converter)"

format="${1:-}"
if [[ -z "$format" ]]; then
  echo "Usage: $0 <png|jpeg> <file...>" >&2
  exit 1
fi
shift

case "$format" in
  png|PNG)
    target_ext="png"
    extra_args=()
    ;;
  jpg|jpeg|JPG|JPEG)
    target_ext="jpg"
    extra_args=(-quality 92)
    ;;
  webp|WEBP)
    target_ext="webp"
    extra_args=(-quality 90)
    ;;
  *)
    echo "Unknown format '$format'." >&2
    exit 1
    ;;
esac

for file in "$@"; do
  [[ -e "$file" ]] || continue
  base="${file%.*}"
  out="${base}.${target_ext}"
  if [[ -e "$out" ]]; then
    idx=1
    while [[ -e "${base} (${idx}).${target_ext}" ]]; do
      ((idx++))
    done
    out="${base} (${idx}).${target_ext}"
  fi

  "$converter_cmd" "$file" "${extra_args[@]}" "$out"
done
EOF
  chmod 0755 "$RUNNER_PATH"
}

restart_dolphin() {
  if ! command -v dolphin >/dev/null 2>&1; then
    echo "Dolphin executable not found; skipping restart."
    return
  fi

  local quit_cmd=""
  if command -v kquitapp6 >/dev/null 2>&1; then
    quit_cmd="kquitapp6"
  elif command -v kquitapp5 >/dev/null 2>&1; then
    quit_cmd="kquitapp5"
  elif command -v kquitapp >/dev/null 2>&1; then
    quit_cmd="kquitapp"
  fi

  local was_running=0
  if pgrep -x dolphin >/dev/null 2>&1; then
    was_running=1
    if [[ -n "$quit_cmd" ]]; then
      "$quit_cmd" dolphin >/dev/null 2>&1 || true
    else
      pkill -x dolphin >/dev/null 2>&1 || true
    fi
    sleep 1
  fi

  nohup dolphin >/dev/null 2>&1 &

  if [[ $was_running -eq 1 ]]; then
    echo "Dolphin restarted to reload service menus."
  else
    echo "Dolphin launched to load the new service menu."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --plasma5)
      TARGET_DIR="$PLASMA5_DIR"
      shift
      ;;
    --plasma6)
      TARGET_DIR="$PLASMA6_DIR"
      shift
      ;;
    --target-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --target-dir requires a path." >&2
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  plasma_major="$(detect_plasma_major_version)"
  if [[ -n "$plasma_major" ]] && (( plasma_major >= 6 )); then
    TARGET_DIR="$PLASMA6_DIR"
  elif [[ -d "$PLASMA6_DIR" ]]; then
    TARGET_DIR="$PLASMA6_DIR"
  else
    TARGET_DIR="$PLASMA5_DIR"
  fi
fi

mkdir -p "$TARGET_DIR"
install_runner
ensure_shell_access_allowed

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "Warning: ImageMagick (magick/convert) not found. Install it with 'sudo apt install imagemagick'." >&2
fi

if command -v magick >/dev/null 2>&1; then
  converter_cmd="$(command -v magick)"
elif command -v convert >/dev/null 2>&1; then
  converter_cmd="$(command -v convert)"
else
  converter_cmd="magick"
fi

target_file="$TARGET_DIR/$SERVICE_MENU_NAME"

if [[ -e "$target_file" && $FORCE -ne 1 ]]; then
  echo "Refusing to overwrite existing $target_file (use --force)." >&2
  exit 1
fi

cat <<EOF > "$target_file"
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=image/*;image/bmp;image/gif;image/jpeg;image/jpg;image/png;image/tiff;image/webp;image/avif;image/heic;image/heif;image/svg+xml;image/x-icon;image/vnd.microsoft.icon;image/x-tga;image/x-portable-anymap;image/x-portable-pixmap;image/x-portable-graymap;image/x-xbitmap;image/x-xpixmap;
Icon=applications-graphics
Actions=ConvertToPNG;ConvertToJPEG;ConvertToWebP
X-KDE-Submenu=One-click Conversion
X-KDE-StartupNotify=false
X-KDE-AuthorizeAction=shell_access

[Desktop Action ConvertToPNG]
Name=Convert to PNG
Icon=image-png
Exec=$RUNNER_PATH png %F

[Desktop Action ConvertToJPEG]
Name=Convert to JPEG
Icon=image-jpeg
Exec=$RUNNER_PATH jpeg %F

[Desktop Action ConvertToWebP]
Name=Convert to WebP
Icon=image-x-generic
Exec=$RUNNER_PATH webp %F
EOF

chmod 0755 "$target_file"

cat <<EOF
Installed one-click image converter menu at:
  $target_file

The actions should appear in Dolphin immediately after the automatic restart.
Conversion command: $converter_cmd
EOF

restart_dolphin
