#!/usr/bin/env bash
#
# lib/tui/views/step_dst.sh - Step 2: コピー先の選択
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# コピー先に選べるボリューム一覧を TUI_VOLS / TUI_VOL_LABELS に作る。
#   CLI と挙動をそろえ、コピー元と同じボリュームも候補に含める。
#   （見分けがつくよう、コピー元と同じボリュームには印を付ける）
tui_dest_volumes() {   # $1=src
  local src_mp; src_mp="$(mount_point_of "$1")"
  local v note
  TUI_VOLS=()
  TUI_VOL_LABELS=()
  for v in "/" "$MOUNT_ROOT"/*; do
    [ -d "$v" ] || continue
    [ -L "$v" ] && continue
    note=""
    [ "$(mount_point_of "$v")" = "$src_mp" ] && note="(コピー元と同じボリューム)"
    TUI_VOLS+=( "$v" )
    TUI_VOL_LABELS+=( "$(tui_volume_label "$v" "$note")" )
  done
}

# Step 2 本体。TUI_DST を設定する。0=決定 1=戻る
tui_view_dest() {
  TUI_TITLE="$PROG v$VERSION  [2/4] コピー先の選択"
  TUI_HEADER="保存先（外付けHDDなど）を選んでください
コピー元と同じボリュームも選べます"
  TUI_FOOTER="[↑/↓] 移動   [Enter] 選択   [Esc] 戻る"

  tui_dest_volumes "$TUI_SRC"
  TUI_ITEMS=( "${TUI_VOL_LABELS[@]}" )
  [ "${#TUI_ITEMS[@]}" -gt 0 ] || { tui_message "保存先にできるボリュームがありません"; return 1; }
  tui_menu || return 1
  local vol="${TUI_VOLS[$TUI_SELECTED]}"

  # フォルダを階層移動して選ぶ。CLI と同じく、無いフォルダも作成して指定できる。
  TUI_BROWSE_DIR="$vol"
  TUI_BROWSE_ROOT="$vol"
  TUI_PICK_LABEL="コピー先"
  TUI_PICK_CREATE=1
  tui_pick_folder || return 1
  TUI_DST="$TUI_PICKED"

  if [ "$TUI_DST" = "$TUI_SRC" ]; then
    tui_message "コピー元とコピー先が同じです"
    return 1
  fi
  if [ -e "$TUI_DST" ] && [ ! -d "$TUI_DST" ]; then
    tui_message "コピー先がフォルダではありません: $TUI_DST"
    return 1
  fi
  return 0
}
