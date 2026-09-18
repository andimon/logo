#!/usr/bin/env bash
#
# Export a TikZ logo to PDF, SVG and square PNGs.
# Run with --help for usage.

set -euo pipefail

# Settings: environment variables override the built-in defaults.
readonly DEFAULT_SRC="${LOGO_SRC:-andimon_logo.tex}"
readonly DEFAULT_OUT="${LOGO_OUT:-dist}"
readonly LATEX="${LOGO_LATEX:-pdflatex}"
# No colon: an empty LOGO_PNG_SIZES means "skip PNGs".
read -r -a PNG_SIZES <<<"${LOGO_PNG_SIZES-16 32 64 128 256 512 1024}"
readonly PNG_SIZES
readonly REQUIRED_CMDS=("$LATEX" pdftocairo)

usage() {
  cat <<EOF
Usage: ${0##*/} [SOURCE[.tex]] [OUTPUT_DIR]

Precedence: arguments > environment > defaults.

Environment (current value):
  LOGO_SRC        source file        ($DEFAULT_SRC)
  LOGO_OUT        output folder      ($DEFAULT_OUT)
  LOGO_LATEX      LaTeX engine       ($LATEX)
  LOGO_PNG_SIZES  PNG sizes in px    (${PNG_SIZES[*]:-none})
EOF
}

# Holds the temp build folder; global so the EXIT trap can see it.
build_dir=""

cleanup() {
  if [[ -n $build_dir ]]; then
    rm -rf "$build_dir"
  fi
}

die() {
  echo "error: $*" >&2
  exit 1
}

check_deps() {
  local cmd
  for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null || die "'$cmd' not found"
  done
}

validate_sizes() {
  local size
  for size in "${PNG_SIZES[@]}"; do
    [[ $size =~ ^[1-9][0-9]*$ ]] || die "invalid PNG size '$size' in LOGO_PNG_SIZES"
  done
}

# Compile SRC into DEST_DIR, running from the source's folder
# so relative \input and image paths resolve.
build_pdf() {
  local src=$1 dest_dir=$2
  local log="$dest_dir/build.log"

  (
    cd "$(dirname "$src")"
    "$LATEX" -interaction=nonstopmode -halt-on-error -file-line-error \
             -no-shell-escape -output-directory="$dest_dir" \
             "$(basename "$src")"
  ) >"$log" || { cat "$log" >&2; die "LaTeX build failed"; }
}

# Copy PDF to OUT_DIR and render SVG and PNGs from it, all named NAME.*
export_formats() {
  local pdf=$1 out_dir=$2 name=$3
  local base="$out_dir/$name" size

  mkdir -p "$out_dir"
  echo "Exporting to $out_dir/:"

  cp "$pdf" "$base.pdf"
  echo "  $name.pdf"

  pdftocairo -svg "$pdf" "$base.svg"
  echo "  $name.svg"

  for size in "${PNG_SIZES[@]}"; do
    pdftocairo -png -singlefile -scale-to "$size" "$pdf" "${base}_$size"
    echo "  ${name}_$size.png"
  done
}

main() {
  case ${1:-} in
    -h | --help) usage; exit 0 ;;
  esac
  (( $# <= 2 )) || { usage >&2; exit 2; }

  local src="${1:-$DEFAULT_SRC}"
  local out="${2:-$DEFAULT_OUT}"
  src="${src%.tex}.tex"
  local name
  name="$(basename "$src" .tex)"

  check_deps
  validate_sizes
  [[ -f $src ]] || die "'$src' not found"

  trap cleanup EXIT
  build_dir="$(mktemp -d)"

  build_pdf "$src" "$build_dir"
  export_formats "$build_dir/$name.pdf" "$out" "$name"
}

main "$@"
