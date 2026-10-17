#!/usr/bin/env bats
#
# TUI 部品の表示と、キー入力の解析テスト
#
#   キー入力は標準入力へバイト列を流して検証する（擬似端末は使わない）。

setup() {
  LIB_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/lib"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/layout.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/terminal.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/input.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/components.sh"
}

# 指定バイト列を入力したときに返るキー名
key() {   # $1=bytes
  printf '%s' "$1" | tui_read_key
}

# ---------------------------------------------------------------------------
# 部品
# ---------------------------------------------------------------------------

@test "チェックボックスは ON/OFF を描き分ける" {
  run tui_component_checkbox 1
  [ "$output" = "[X]" ]
  run tui_component_checkbox 0
  [ "$output" = "[ ]" ]
}

@test "ラジオボタンは選択状態を描き分ける" {
  run tui_component_radio 1
  [ "$output" = "(*)" ]
  run tui_component_radio 0
  [ "$output" = "( )" ]
}

@test "プログレスバーは指定幅で塗り分ける" {
  run tui_component_progress_bar 50 10
  [ "$output" = "█████░░░░░" ]
  [ "$(tui_str_width "$output")" = "10" ]
}

# ---------------------------------------------------------------------------
# キー入力
# ---------------------------------------------------------------------------

@test "矢印キーの ESC シーケンスを解釈する" {
  [ "$(key $'\033[A')" = "UP" ]
  [ "$(key $'\033[B')" = "DOWN" ]
  [ "$(key $'\033[C')" = "RIGHT" ]
  [ "$(key $'\033[D')" = "LEFT" ]
}

@test "Enter / 1 文字 / q を解釈する（Bash 3.2 の Enter は空文字）" {
  [ "$(key $'\n')" = "ENTER" ]
  [ "$(key 'a')" = "a" ]
  [ "$(key 'q')" = "QUIT" ]
}

@test "スペースと q 以外の文字を区別する" {
  [ "$(key ' ')" = "SPACE" ]
  [ "$(key '3')" = "3" ]
}

@test "単独の ESC は ESC として扱う" {
  [ "$(key $'\033')" = "ESC" ]
}
