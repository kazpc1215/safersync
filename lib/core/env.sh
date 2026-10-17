#!/usr/bin/env bash
#
# lib/core/env.sh - 共通ヘルパ（ログ・表示・書式・パス）
#
#   bin/safersync から source される。単体では実行しない。
#
# shellcheck shell=bash
# グローバル変数は複数の lib/ 間で共有して使うため、単体では「未使用」に見える。
# shellcheck disable=SC2034

# ---------------------------------------------------------------------------
# ログの場所。macOS は ~/Library/Logs、XDG 環境変数があればそれを優先する。
# ---------------------------------------------------------------------------
if [ -n "${SAFERSYNC_LOG_DIR:-}" ]; then
  LOG_DIR="$SAFERSYNC_LOG_DIR"
elif [ -n "${XDG_STATE_HOME:-}" ]; then
  LOG_DIR="$XDG_STATE_HOME/safersync"
elif [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  LOG_DIR="$HOME/Library/Logs/safersync"
else
  LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/safersync"
fi
LOG_FILE="$LOG_DIR/safersync.log"

# 外付けボリュームの基点。macOS は /Volumes。
# それ以外の環境では --mount-root か $SAFERSYNC_MOUNT_ROOT で変更する。
MOUNT_ROOT="${SAFERSYNC_MOUNT_ROOT:-/Volumes}"

# ---------------------------------------------------------------------------
# 表示ヘルパ
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

info() { printf '%s %s\n' "${C_BLUE}==>${C_RESET}" "$*"; }
ok()   { printf '%s %s\n' "${C_GREEN}✓${C_RESET}" "$*"; }
warn() { printf '%s %s\n' "${C_YELLOW}!${C_RESET}" "$*" >&2; }
err()  { printf '%s %s\n' "${C_RED}✗${C_RESET}" "$*" >&2; }
die()  { err "$*"; exit 1; }

log_msg() {
  mkdir -p "$LOG_DIR" 2>/dev/null && \
    printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
  return 0
}

fmt_bytes() {
  awk -v b="${1:-0}" 'BEGIN{
    split("B KB MB GB TB", u, " ");
    i=1; while (b>=1024 && i<5) { b/=1024; i++ }
    printf "%.1f %s", b, u[i]
  }'
}

# 秒数を「1時間2分」「2分3秒」「4秒」の形にする
fmt_duration() {
  local s="${1:-0}" h m
  h=$(( s / 3600 )); m=$(( (s % 3600) / 60 )); s=$(( s % 60 ))
  if   [ "$h" -gt 0 ]; then printf '%d時間%d分' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%d分%d秒' "$m" "$s"
  else                      printf '%d秒' "$s"
  fi
}

# 末尾の "/" を取り除く（"/" だけは残す）。
#   "SRC/" と "SRC" を同じ意味にそろえ、書き方の違いによる事故を防ぐ。
strip_trailing_slashes() {
  local p="$1"
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

# 相対パスを、実行時のカレントディレクトリ基準の絶対パスに変換し、
# 末尾の "/" をそろえる（どのフォルダから起動しても同じ意味になる。存在しなくてもよい）
abspath() {
  local p
  case "$1" in
    /*)  p="$1" ;;
    ./*) p="$PWD/${1#./}" ;;
    *)   p="$PWD/$1" ;;
  esac
  strip_trailing_slashes "$p"
}

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }
