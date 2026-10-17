#!/usr/bin/env bash
#
# lib/tui/components.sh - 描画部品（罫線ボックス・リスト・トグル・プログレスバー）
#
#   すべて「文字列を返す」純粋関数。描画（printf）は呼び出し側で一括して行う。
#   layout.sh の tui_str_width / tui_pad_right / tui_truncate を使う。
#
#   bin/safersync から source される。テストからも source できる。
#
# shellcheck shell=bash

# ┌── タイトル ─────────────┐
tui_component_box_top() {   # $1=width $2=title
  local w="$1" title="${2-}" inner label fill avail
  inner=$(( w - 2 ))
  [ "$inner" -lt 0 ] && inner=0
  label="─ ${title} "
  avail=$(( inner - $(tui_str_width "$label") ))
  if [ "$avail" -lt 0 ]; then
    label="─ $(tui_truncate "$title" $(( inner > 3 ? inner - 3 : 0 ))) "
    avail=$(( inner - $(tui_str_width "$label") ))
  fi
  [ "$avail" -lt 0 ] && avail=0
  fill="$(tui_repeat_char '─' "$avail")"
  printf '┌%s%s┐' "$label" "$fill"
}

# ├──────────────────────┤
tui_component_box_sep() {   # $1=width
  local w="$1" inner=$(( $1 - 2 ))
  [ "$inner" -lt 0 ] && inner=0
  printf '├%s┤' "$(tui_repeat_char '─' "$inner")"
}

# └──────────────────────┘
tui_component_box_bottom() {   # $1=width
  local inner=$(( $1 - 2 ))
  [ "$inner" -lt 0 ] && inner=0
  printf '└%s┘' "$(tui_repeat_char '─' "$inner")"
}

# │ テキスト（幅に合わせて詰める） │
tui_component_box_row() {   # $1=width $2=text
  local w="$1" text="${2-}" inner
  inner=$(( w - 4 ))
  [ "$inner" -lt 0 ] && inner=0
  text="$(tui_truncate "$text" "$inner")"
  printf '│ %s │' "$(tui_pad_right "$text" "$inner")"
}

# 何もない 1 行（│                    │）
tui_component_box_blank() {   # $1=width
  tui_component_box_row "$1" ""
}

# チェックボックス [X] / [ ]
tui_component_checkbox() { [ "$1" = 1 ] && printf '[X]' || printf '[ ]'; }

# ラジオボタン (*) / ( )
tui_component_radio() { [ "$1" = 1 ] && printf '(*)' || printf '( )'; }

# カーソル記号 > / 空白
tui_component_cursor() { [ "$1" = 1 ] && printf '>' || printf ' '; }

# プログレスバー（例: ██████░░░░）
tui_component_progress_bar() {   # $1=pct(0-100) $2=width
  local pct="$1" w="$2" filled i out=""
  [ "$w" -gt 0 ] || { printf ''; return 0; }
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100
  filled=$(( pct * w / 100 ))
  i=0
  while [ "$i" -lt "$filled" ]; do out="${out}█"; i=$(( i + 1 )); done
  while [ "$i" -lt "$w" ]; do out="${out}░"; i=$(( i + 1 )); done
  printf '%s' "$out"
}
