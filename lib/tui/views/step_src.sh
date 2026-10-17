#!/usr/bin/env bash
#
# lib/tui/views/step_src.sh - Step 1: コピー元の選択
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# ボリュームの表示名（名前 と 使用/空き容量）
tui_volume_label() {   # $1=path $2=note
  local p="$1" note="${2-}" name info
  name="$(basename "$p")"
  [ "$p" = "/" ] && name="Macintosh HD"
  info="$(df -h "$p" 2>/dev/null | awk 'NR==2{printf "空き %s / 使用 %s", $4, $3}')"
  printf '%s %s   %s' "$name" "$note" "$info"
}

# ボリューム一覧を TUI_VOLS / TUI_VOL_LABELS に作る
tui_volumes_load() {
  TUI_VOLS=()
  TUI_VOL_LABELS=()
  TUI_VOLS+=( "/" )
  TUI_VOL_LABELS+=( "$(tui_volume_label "/" "内蔵ディスク")" )
  local v
  for v in "$MOUNT_ROOT"/*; do
    [ -d "$v" ] || continue
    [ -L "$v" ] && continue          # /Volumes/Macintosh HD などのリンクは除外
    TUI_VOLS+=( "$v" )
    TUI_VOL_LABELS+=( "$(tui_volume_label "$v" "(外付け)")" )
  done
}

# コピー元の候補フォルダを TUI_FOLDERS / TUI_FOLDER_LABELS に作る
tui_source_candidates() {   # $1=volume
  local vol="$1" d base
  TUI_FOLDERS=()
  TUI_FOLDER_LABELS=()
  if [ -d "$vol/DCIM" ]; then
    for d in "$vol/DCIM"/*/; do
      [ -d "$d" ] || continue
      base="$(basename "$d")"
      TUI_FOLDERS+=( "${d%/}" )
      TUI_FOLDER_LABELS+=( "DCIM/${base}" )
    done
    TUI_FOLDERS+=( "$vol/DCIM" )
    TUI_FOLDER_LABELS+=( "DCIM (全体)" )
  else
    for d in "$vol"/*/; do
      [ -d "$d" ] || continue
      base="$(basename "$d")"
      case "$base" in .*) continue;; esac
      TUI_FOLDERS+=( "${d%/}" )
      TUI_FOLDER_LABELS+=( "$base" )
    done
  fi
  TUI_FOLDERS+=( "$vol" )
  TUI_FOLDER_LABELS+=( "「$(basename "$vol")」の直下全体" )
  TUI_FOLDERS+=( "__MANUAL__" )
  TUI_FOLDER_LABELS+=( "パスを手動で入力する..." )
}

# Step 1 本体。TUI_SRC を設定する。0=決定 1=中止
tui_view_source() {
  TUI_TITLE="$PROG v$VERSION  [1/4] コピー元の選択"
  TUI_HEADER="転送したいデータ（SDカードなど）を選んでください"
  TUI_FOOTER="[↑/↓] 移動   [Enter] 選択   [q] 終了"

  tui_volumes_load
  TUI_ITEMS=( "${TUI_VOL_LABELS[@]}" )
  tui_menu || return 1
  local vol="${TUI_VOLS[$TUI_SELECTED]}"

  tui_source_candidates "$vol"
  TUI_HEADER="ボリューム: $vol"
  TUI_ITEMS=( "${TUI_FOLDER_LABELS[@]}" )
  tui_menu || return 1
  local pick="${TUI_FOLDERS[$TUI_SELECTED]}"

  if [ "$pick" = "__MANUAL__" ]; then
    TUI_HEADER=""
    TUI_PROMPT_LABEL="コピー元のパスを入力してください（例: /Volumes/X/DCIM/100GOPRO）"
    TUI_FOOTER="[Enter] 決定   [Esc] 戻る"
    tui_prompt || return 1
    pick="$(expand_tilde "${TUI_INPUT}")"
  fi

  [ -n "$pick" ] || return 1
  TUI_SRC="$(abspath "$pick")"
  if [ ! -d "$TUI_SRC" ]; then
    tui_message "フォルダが見つかりません: $TUI_SRC"
    return 1
  fi
  return 0
}
