#!/usr/bin/env bash
#
# lib/tui/app.sh - TUI 全体の進行（ウィザードの連結）
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# TUI のオプションをコアのグローバルへ反映する
tui_apply_options() {
  EXCLUDE_PATTERNS=()
  if [ "$TUI_OPT_LRV" = 1 ]; then EXCLUDE_PATTERNS+=( "*.LRV" ); fi
  if [ "$TUI_OPT_THM" = 1 ]; then EXCLUDE_PATTERNS+=( "*.THM" ); fi
  if [ "$TUI_OPT_TMP" = 1 ]; then EXCLUDE_PATTERNS+=( "*.tmp" "*.temp" ); fi
  CHECKSUM="$TUI_OPT_CHECKSUM"
  if [ "$TUI_OPT_CAFFEINATE" = 1 ]; then NO_CAFFEINATE=0; else NO_CAFFEINATE=1; fi
  build_rsync_opts
}

# 除外設定の表示用サマリ
tui_options_summary() {
  local s=""
  [ "$TUI_OPT_LRV" = 1 ] && s="${s}*.LRV "
  [ "$TUI_OPT_THM" = 1 ] && s="${s}*.THM "
  [ "$TUI_OPT_TMP" = 1 ] && s="${s}*.tmp "
  if [ -n "$s" ]; then printf '%s' "$s"; else printf '（なし）'; fi
}

# TUI のメインループ。終了コードを返す
tui_main() {
  tui_term_enter

  TUI_OPT_LRV=1
  TUI_OPT_THM=1
  TUI_OPT_TMP=0
  TUI_OPT_CHECKSUM=0
  TUI_OPT_CAFFEINATE=1
  TUI_SRC=""
  TUI_DST=""

  # 引数があればプリフィル（--tui と位置引数の併用）
  local stage=1
  if [ -n "${FROM_ARG:-}" ]; then
    local s; s="$(abspath "$(expand_tilde "$FROM_ARG")")"
    if [ -d "$s" ]; then TUI_SRC="$s"; stage=2; fi
  fi
  if [ -n "${TO_ARG:-}" ] && [ "$stage" = 2 ]; then
    TUI_DST="$(abspath "$(expand_tilde "$TO_ARG")")"
    stage=3
  fi

  local rc
  while :; do
    case "$stage" in
      1)
        if ! tui_view_source; then return 0; fi
        stage=2 ;;
      2)
        if ! tui_view_dest; then stage=1; continue; fi
        stage=3 ;;
      3)
        if ! tui_view_options; then stage=2; continue; fi
        stage=4 ;;
      4)
        tui_view_preview; rc=$?
        case "$rc" in
          0) stage=5; break ;;
          1) stage=3; continue ;;
          *) return 0 ;;
        esac ;;
      *) break ;;
    esac
  done

  local frc=0
  tui_view_dashboard "$TUI_SRC" "$TUI_DST"; frc=$?
  tui_view_done "$frc"
  return "$frc"
}
