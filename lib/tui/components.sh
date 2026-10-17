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
# TUI_TITLE / TUI_HEADER / TUI_FOOTER / TUI_ITEMS などは呼び出し側が設定する。
# shellcheck disable=SC2154
# shellcheck disable=SC2034

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

# ---------------------------------------------------------------------------
# 対話部品（terminal.sh / input.sh と組み合わせて使う）
# ---------------------------------------------------------------------------

# 画面バッファを組み立てる共通ヘルパ。
#   TUI_TITLE / TUI_HEADER(改行区切り, 空可) / body 行 / TUI_FOOTER を 1 枚にする。
tui_frame() {   # $1=width $2..=body の行
  local w="$1"; shift
  local buf line
  buf="$(tui_component_box_top "$w" "$TUI_TITLE")"$'\n'
  if [ -n "${TUI_HEADER:-}" ]; then
    buf="${buf}$(tui_component_box_blank "$w")"$'\n'
    while IFS= read -r line; do
      buf="${buf}$(tui_component_box_row "$w" "$line")"$'\n'
    done <<< "$TUI_HEADER"
  fi
  buf="${buf}$(tui_component_box_sep "$w")"$'\n'
  for line in "$@"; do
    buf="${buf}$(tui_component_box_row "$w" "$line")"$'\n'
  done
  buf="${buf}$(tui_component_box_blank "$w")"$'\n'
  buf="${buf}$(tui_component_box_sep "$w")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" "${TUI_FOOTER:-}")"$'\n'
  buf="${buf}$(tui_component_box_bottom "$w")"
  printf '%s' "$buf"
}

# 端末が狭すぎるときの案内を描く
tui_render_tiny() {   # $1=width $2=height
  local w="$1" h="$2" buf
  buf="$(tui_component_box_top "$w" "${TUI_TITLE:-safersync}")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" "ターミナルを広げてください（現在 ${w}x${h}）")"$'\n'
  buf="${buf}$(tui_component_box_bottom "$w")"
  tui_screen_render "$buf"
}

# 単純なメッセージを出して 1 キー待つ
tui_message() {   # $1=message
  local w h
  IFS=' ' read -r w h <<< "$(tui_term_size)"
  [ "$w" -ge 40 ] || w=40
  local buf=""
  buf="$(tui_component_box_top "$w" "${TUI_TITLE:-safersync}")"$'\n'
  buf="${buf}$(tui_component_box_blank "$w")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" "  $1")"$'\n'
  buf="${buf}$(tui_component_box_blank "$w")"$'\n'
  buf="${buf}$(tui_component_box_sep "$w")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [Enter] で戻る")"$'\n'
  buf="${buf}$(tui_component_box_bottom "$w")"
  tui_screen_render "$buf"
  tui_read_key >/dev/null 2>&1
}

# リストから 1 つ選ぶ。
#   入力: TUI_ITEMS(配列) / TUI_TITLE / TUI_HEADER / TUI_FOOTER
#   出力: TUI_SELECTED(選択 index)。戻り値 0=決定 1=キャンセル
tui_menu() {
  local n=${#TUI_ITEMS[@]} key w h i cur buf
  local sel="${TUI_MENU_SEL:-0}"
  [ "$sel" -ge "$n" ] 2>/dev/null && sel=0
  [ "$n" -gt 0 ] || return 1
  while :; do
    IFS=' ' read -r w h <<< "$(tui_term_size)"
    if [ "$w" -lt 50 ] || [ "$h" -lt 12 ]; then
      tui_render_tiny "$w" "$h"
      key="$(tui_read_key)"
      case "$key" in QUIT|EOF) return 1;; esac
      continue
    fi
    local -a body=()
    i=0
    while [ "$i" -lt "$n" ]; do
      cur=" "
      [ "$i" -eq "$sel" ] && cur=">"
      body+=( " $cur ${TUI_ITEMS[$i]}" )
      i=$(( i + 1 ))
    done
    buf="$(tui_frame "$w" "${body[@]}")"
    tui_screen_render "$buf"
    key="$(tui_read_key)"
    case "$key" in
      UP|k)     sel=$(( (sel - 1 + n) % n ));;
      DOWN|j)   sel=$(( (sel + 1) % n ));;
      ENTER)    TUI_SELECTED="$sel"; return 0;;
      ESC|QUIT|EOF) return 1;;
      NONE)     :;;
    esac
    TUI_WINCH=0
  done
}

# 1 行のテキスト入力。
#   入力: TUI_TITLE / TUI_HEADER / TUI_FOOTER / TUI_PROMPT_LABEL
#   出力: TUI_INPUT。戻り値 0=決定 1=キャンセル
tui_prompt() {
  local input="" key w h buf
  while :; do
    IFS=' ' read -r w h <<< "$(tui_term_size)"
    [ "$w" -ge 40 ] || w=40
    buf="$(tui_frame "$w" \
      "" \
      "  ${TUI_PROMPT_LABEL:-入力してください}" \
      "" \
      "  > ${input}_")"
    tui_screen_render "$buf"
    key="$(tui_read_key)"
    case "$key" in
      ENTER)      TUI_INPUT="$input"; return 0;;
      ESC|QUIT|EOF) return 1;;
      BACKSPACE)  input="${input%?}";;
      NONE)       :;;
      *)          [ "${#key}" -eq 1 ] && input="${input}${key}";;
    esac
  done
}

# コマンドを背景実行し、スピナーを描きながら待つ
tui_busy() {   # $1=ラベル $2...=コマンド
  local label="$1"; shift
  "$@" &
  local pid=$!
  TUI_CHILD_PID="$pid"
  local spin='|/-\\' i=0 w h buf c
  while kill -0 "$pid" 2>/dev/null; do
    IFS=' ' read -r w h <<< "$(tui_term_size)"
    c="${spin:$(( i % 4 )):1}"
    buf="$(tui_frame "$w" "" "  $c $label")"
    tui_screen_render "$buf"
    i=$(( i + 1 ))
    sleep 0.2
  done
  wait "$pid"
  local rc=$?
  TUI_CHILD_PID=""
  return "$rc"
}
