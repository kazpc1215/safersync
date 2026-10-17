#!/usr/bin/env bash
#
# lib/tui/terminal.sh - 画面制御（Alternate Screen・カーソル・stty 退避復元・trap）
#
#   bin/safersync から source される。テストからも source できる（副作用なし）。
#
# shellcheck shell=bash
# C_RESET は env.sh の表示ヘルパを共有する。
# shellcheck disable=SC2034

TUI_STTY_SAVE=""
TUI_ACTIVE=0
TUI_WINCH=0

# 端末サイズを "COLS LINES" で返す
tui_term_size() {
  local cols lines
  cols="${COLUMNS:-}"
  lines="${LINES:-}"
  [ -n "$cols" ]  || cols="$(tput cols 2>/dev/null || printf 80)"
  [ -n "$lines" ] || lines="$(tput lines 2>/dev/null || printf 24)"
  printf '%s %s' "$cols" "$lines"
}

# 端末の元モードを保存して raw モード（1 文字ずつ・エコーなし）にする
tui_term_raw_on() {
  TUI_STTY_SAVE="$(stty -g 2>/dev/null)"
  stty -echo -icanon min 1 time 0 2>/dev/null
  return 0
}

# 端末モードを保存した状態へ戻す
tui_term_raw_off() {
  [ -n "$TUI_STTY_SAVE" ] && stty "$TUI_STTY_SAVE" 2>/dev/null
  return 0
}

# ESC の続きのバイトを 0.1 秒だけ待つモード
tui_term_esc_timeout_on()  { [ -t 0 ] && stty min 0 time 1 2>/dev/null; return 0; }
tui_term_esc_timeout_off() { [ -t 0 ] && stty min 1 time 0 2>/dev/null; return 0; }

# Alternate Screen へ切り替えて TUI を開始する
tui_term_enter() {
  TUI_ACTIVE=1
  printf '\033[?1049h'      # 代替画面へ
  printf '\033[?25l'        # カーソル非表示
  tui_term_raw_on
  trap 'tui_term_cleanup' EXIT INT TERM HUP
  trap 'TUI_WINCH=1' WINCH
}

# 終了・中断時に必ず元の画面へ戻す
tui_term_cleanup() {
  trap - EXIT INT TERM HUP WINCH
  tui_term_raw_off
  printf '\033[?25h'        # カーソル再表示
  printf '\033[?1049l'      # メインスクリーンへ復帰
  printf '%s' "${C_RESET:-}"
  TUI_ACTIVE=0
}

# 画面全体を消す
tui_screen_clear() { printf '\033[2J\033[H'; }

# 画面バッファを一括描画する（チラつき防止: 1 回の printf で出す）
tui_screen_render() {   # $1=buffer
  printf '\033[H%s\033[J' "${1-}"
}

# カーソルを指定位置へ移動する
tui_screen_move() { printf '\033[%d;%dH' "$1" "$2"; }
