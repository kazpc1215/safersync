#!/usr/bin/env bash
#
# lib/tui/views/step_prev.sh - Step 4: 事前プレビュー（dry-run サマリ確認）
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# 差分スキャンを行い、結果を 1 行でファイルへ書き出す（背景実行用）
#   "転送ファイル数 転送バイト数 元ファイル数 元バイト数"
tui_plan_to_file() {   # $1=outfile
  plan_changes "$TUI_SRC" "$TUI_DST"
  local sres tf tb
  sres="$(scan_dir "$TUI_SRC")"
  tf="${sres%% *}"; tb="${sres##* }"
  printf '%s %s %s %s\n' "$PLAN_FILES" "$PLAN_BYTES" "${tf:-0}" "${tb:-0}" > "$1"
}

# Step 4 本体。0=開始 1=設定へ戻る 2=中止
tui_view_preview() {
  tui_apply_options

  TUI_TITLE="$PROG v$VERSION  [4/4] 転送内容の最終確認"
  TUI_HEADER="差分を調べています…"
  TUI_FOOTER=""
  local base; base="$(mktemp "${TMPDIR:-/tmp}/safersync.plan.XXXXXX" 2>/dev/null)"
  if [ -n "$base" ]; then
    tui_busy "差分をスキャンしています..." tui_plan_to_file "$base"
  fi

  local nfiles=0 nbytes=0 tf=0 tb=0
  if [ -n "$base" ] && [ -f "$base" ]; then
    # shellcheck disable=SC2046
    read -r nfiles nbytes tf tb < "$base" 2>/dev/null
    rm -f "$base"
  fi
  : "${nfiles:=0}"; : "${nbytes:=0}"; : "${tf:=0}"; : "${tb:=0}"

  local skip=$(( tf - nfiles )); [ "$skip" -lt 0 ] && skip=0
  local skipb=$(( tb - nbytes )); [ "$skipb" -lt 0 ] && skipb=0
  local free; free="$(free_bytes "$TUI_DST")"; : "${free:=0}"

  local space_msg="十分な空きがあります"
  local enough=1
  if [ "$free" -lt "$nbytes" ]; then
    space_msg="空き容量が不足しています"
    enough=0
  fi

  local excl; excl="$(tui_options_summary)"
  local warn_line=""
  is_mount_point "$TUI_DST" && warn_line="注意: コピー先がボリュームの直下です（中身が散らばります）"
  local mounted_line=""
  dest_is_mounted "$TUI_DST" || mounted_line="注意: コピー先のボリュームがマウントされていません"

  TUI_TITLE="$PROG v$VERSION  [4/4] 転送内容の最終確認"
  TUI_HEADER="コピー元: $TUI_SRC
コピー先: $TUI_DST
除外設定: $excl

差分スキャン結果:
  ・転送対象: ${nfiles} ファイル（$(fmt_bytes "$nbytes")）
  ・スキップ: ${skip} ファイル（$(fmt_bytes "$skipb") - すでに転送済み）
  ・転送先空き: $(fmt_bytes "$free")  [$space_msg]"
  [ -n "$mounted_line" ] && TUI_HEADER="${TUI_HEADER}"$'\n'"$mounted_line"
  [ -n "$warn_line" ] && TUI_HEADER="${TUI_HEADER}"$'\n'"$warn_line"

  TUI_FOOTER="[←/→ でも ↑/↓ でも可] [Enter] 決定   [Esc] 戻る"

  if [ "$enough" = 1 ] && [ -z "$mounted_line" ]; then
    TUI_ITEMS=( "今すぐ開始する" "設定を戻す" "中止する" )
    TUI_MENU_SEL=0
  else
    TUI_ITEMS=( "開始できません（上記の注意を解消してください）" "設定を戻す" "中止する" )
    TUI_MENU_SEL=1
  fi

  tui_menu || return 2
  case "$TUI_SELECTED" in
    0) [ "$enough" = 1 ] && [ -z "$mounted_line" ] && return 0; return 1 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}
