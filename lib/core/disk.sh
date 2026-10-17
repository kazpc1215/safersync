#!/usr/bin/env bash
#
# lib/core/disk.sh - ボリューム検知・空き容量・マウント判定・走査
#
#   bin/safersync から source される。単体では実行しない。
#
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# コピー先の確認（未マウントの外付けボリュームへ書き込む事故を防ぐ）
# ---------------------------------------------------------------------------

# パスそのものがマウントポイントかどうか
is_mount_point() {   # $1=path
  [ -d "$1" ] || return 1
  mount 2>/dev/null | grep -Fq " on $1 "
}

# パス（存在しなければ最も近い既存の祖先）から上にたどり、
# 最初に見つかる実マウントポイントを返す。見つからなければ "/"。
mount_point_of() {   # $1=path
  local p="$1"
  while [ ! -e "$p" ] && [ "$p" != "/" ]; do p="$(dirname "$p")"; done
  while : ; do
    if is_mount_point "$p"; then printf '%s' "$p"; return 0; fi
    [ "$p" = "/" ] && break
    p="$(dirname "$p")"
  done
  printf '/'
}

# コピー先が $MOUNT_ROOT の下にあるのに、そのボリュームが実マウントされて
# いなければ、開始前に中止する（終了コード 2）。
# 基点の外（~/ や /tmp など）を指定したときは判定しない。
# コピー先が基点の下にあるとき、実マウントされていれば 0（対象外なら常に 0）
dest_is_mounted() {   # $1=dst
  [ "$MOUNT_ROOT" = "/" ] && return 0
  case "$1" in
    "$MOUNT_ROOT"/*) ;;
    *) return 0 ;;
  esac

  local mp; mp="$(mount_point_of "$1")"
  case "$mp" in
    "$MOUNT_ROOT"/*) return 0 ;;
  esac
  return 1
}

require_mounted_dest() {   # $1=dst
  dest_is_mounted "$1" && return 0

  err "コピー先のボリュームがマウントされていません: $1"
  err "外付け媒体を接続してから再実行してください。"
  err "現在の ${MOUNT_ROOT}: $(ls "$MOUNT_ROOT" 2>/dev/null | tr '\n' ' ')"
  exit 2
}

# 指定パス（存在しなければ最も近い既存の祖先）の空き容量をバイトで返す
free_bytes() {   # $1=path
  local p="$1"
  while [ ! -e "$p" ] && [ "$p" != "/" ]; do p="$(dirname "$p")"; done
  df -k "$p" 2>/dev/null | awk 'NR==2{printf "%d", $4 * 1024}'
}

# ファイルサイズの取得方法は BSD/macOS（stat -f '%z'）と GNU（stat -c '%s'）で違う。
# 起動時に判定して STAT_SIZE に入れておく。
if stat -c '%s' "$0" >/dev/null 2>&1; then
  STAT_SIZE=( -c '%s' )      # GNU coreutils
else
  STAT_SIZE=( -f '%z' )      # BSD / macOS
fi

# 除外パターンを除いた「ファイル数 合計バイト数」を返す
scan_dir() {   # $1=dir
  find "$1" \( "${FIND_EXCL[@]}" \) -prune -o -type f -print0 2>/dev/null \
    | xargs -0 stat "${STAT_SIZE[@]}" 2>/dev/null \
    | awk '{c++; s+=$1} END {printf "%d %d", c+0, s+0}'
}
