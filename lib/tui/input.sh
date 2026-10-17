#!/usr/bin/env bash
#
# lib/tui/input.sh - キー入力の解析
#
#   ★ Bash 3.2 では `read -t 0.1`（小数タイムアウト）が使えない。
#     代わりに stty の min/time を使う（time の単位は 1/10 秒）。
#     通常は min 1（1 文字来るまで待つ）、ESC の続きだけ min 0 time 1（0.1 秒）。
#
#   bin/safersync から source される。テストからも source できる。
#
# shellcheck shell=bash

# 1 回のキー入力を読み、キー名（UP/DOWN/ENTER/SPACE/ESC/1 文字など）を返す。
#   待っている間に何も入力が無ければ 'NONE' を返す（タイムアウト）。
tui_read_key() {
  local c1 c2 c3
  IFS= read -rsn1 c1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    # 入力が無い（タイムアウト or EOF）。Enter（空文字）とは区別する。
    if [ "$rc" -gt 128 ]; then printf 'NONE'; else printf 'EOF'; fi
    return 0
  fi

  if [ "$c1" = $'\x1b' ]; then
    tui_term_esc_timeout_on
    if ! IFS= read -rsn1 c2; then
      tui_term_esc_timeout_off
      printf 'ESC'; return 0
    fi
    case "$c2" in
      '['|'O')
        if ! IFS= read -rsn1 c3; then
          tui_term_esc_timeout_off
          printf 'ESC'; return 0
        fi
        tui_term_esc_timeout_off
        case "$c3" in
          A) printf 'UP' ;;
          B) printf 'DOWN' ;;
          C) printf 'RIGHT' ;;
          D) printf 'LEFT' ;;
          H) printf 'HOME' ;;
          F) printf 'END' ;;
          Z) printf 'BTAB' ;;
          5) printf 'PGUP' ;;
          6) printf 'PGDN' ;;
          *) printf 'ESC' ;;
        esac
        return 0 ;;
      *) tui_term_esc_timeout_off; printf 'ESC'; return 0 ;;
    esac
  fi

  case "$c1" in
    # Enter は環境によって空文字（正準モード）/ \n / \r のいずれにもなる
    ''|$'\n'|$'\r')  printf 'ENTER' ;;
    ' ')             printf 'SPACE' ;;
    $'\x7f'|$'\b')   printf 'BACKSPACE' ;;
    q|Q)             printf 'QUIT' ;;
    j)               printf 'DOWN' ;;       # vim 風
    k)               printf 'UP' ;;
    *)               printf '%s' "$c1" ;;
  esac
}
