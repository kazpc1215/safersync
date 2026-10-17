#!/usr/bin/env bash
#
# lib/tui/views/step_dst.sh - Step 2: コピー先の選択
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# コピー先の候補フォルダを TUI_FOLDERS / TUI_FOLDER_LABELS に作る
tui_dest_candidates() {   # $1=volume
  local vol="$1" d base
  TUI_FOLDERS=()
  TUI_FOLDER_LABELS=()
  for d in "$vol"/*/; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"
    case "$base" in .*) continue;; esac
    TUI_FOLDERS+=( "${d%/}" )
    TUI_FOLDER_LABELS+=( "$base" )
  done
  TUI_FOLDERS+=( "__NEW__" )
  TUI_FOLDER_LABELS+=( "新しいフォルダを作成する..." )
  TUI_FOLDERS+=( "$vol" )
  TUI_FOLDER_LABELS+=( "「$(basename "$vol")」の直下" )
  TUI_FOLDERS+=( "__MANUAL__" )
  TUI_FOLDER_LABELS+=( "パスを手動で入力する..." )
}

# Step 2 本体。TUI_DST を設定する。0=決定 1=戻る
tui_view_dest() {
  local src_mp; src_mp="$(mount_point_of "$TUI_SRC")"

  TUI_TITLE="$PROG v$VERSION  [2/4] コピー先の選択"
  TUI_HEADER="保存先（外付けHDDなど）を選んでください
コピー元と同じボリュームは選べません"
  TUI_FOOTER="[↑/↓] 移動   [Enter] 選択   [Esc] 戻る"

  TUI_VOLS=()
  TUI_VOL_LABELS=()
  local v
  for v in "/" "$MOUNT_ROOT"/*; do
    [ -d "$v" ] || continue
    [ -L "$v" ] && continue
    [ "$(mount_point_of "$v")" = "$src_mp" ] && continue
    TUI_VOLS+=( "$v" )
    TUI_VOL_LABELS+=( "$(tui_volume_label "$v" "")" )
  done
  TUI_ITEMS=( "${TUI_VOL_LABELS[@]}" )
  [ "${#TUI_ITEMS[@]}" -gt 0 ] || { tui_message "保存先にできるボリュームがありません"; return 1; }
  tui_menu || return 1
  local vol="${TUI_VOLS[$TUI_SELECTED]}"

  tui_dest_candidates "$vol"
  TUI_HEADER="保存先ボリューム: $vol"
  TUI_ITEMS=( "${TUI_FOLDER_LABELS[@]}" )
  tui_menu || return 1
  local pick="${TUI_FOLDERS[$TUI_SELECTED]}"

  case "$pick" in
    __NEW__)
      TUI_HEADER="保存先: $vol"
      TUI_PROMPT_LABEL="新しいフォルダ名を入力してください"
      TUI_FOOTER="[Enter] 決定   [Esc] 戻る"
      tui_prompt || return 1
      pick="$vol/${TUI_INPUT}" ;;
    __MANUAL__)
      TUI_HEADER=""
      TUI_PROMPT_LABEL="コピー先のパスを入力してください（例: /Volumes/HDD/GoPro）"
      TUI_FOOTER="[Enter] 決定   [Esc] 戻る"
      tui_prompt || return 1
      pick="$(expand_tilde "${TUI_INPUT}")" ;;
  esac

  [ -n "$pick" ] || return 1
  TUI_DST="$(abspath "$pick")"

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
