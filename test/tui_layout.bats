#!/usr/bin/env bats
#
# TUI 描画の純粋関数テスト（表示幅・パディング・切り詰め）
#
#   layout.sh / components.sh は副作用なしで source できるため、
#   擬似端末なしで数値検証できる。

setup() {
  LIB_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/lib"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/layout.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/components.sh"
}

# ---------------------------------------------------------------------------
# 表示幅
# ---------------------------------------------------------------------------

@test "半角文字の表示幅は文字数と同じ" {
  run tui_str_width "abc"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "日本語は 1 文字 2 桁として数える" {
  run tui_str_width "日本語"
  [ "$output" = "6" ]
}

@test "日本語と半角の混在を正しく数える" {
  run tui_str_width "日本語abc"
  [ "$output" = "9" ]
}

@test "全角記号も幅 2 として数える" {
  run tui_str_width "（）"
  [ "$output" = "4" ]
}

@test "空文字の表示幅は 0" {
  run tui_str_width ""
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# パディング・切り詰め
# ---------------------------------------------------------------------------

@test "tui_pad_right は表示幅を target にそろえる" {
  local s
  s="$(tui_pad_right "あ" 4)"
  [ "$(tui_str_width "$s")" = "4" ]
}

@test "tui_pad_left は右寄せで表示幅をそろえる" {
  local s
  s="$(tui_pad_left "あ" 4)"
  [ "$(tui_str_width "$s")" = "4" ]
}

@test "tui_truncate は文字の途中で切らずに表示幅以下へ収める" {
  run tui_truncate "日本語" 4
  [ "$output" = "日本" ]
  run tui_truncate "日本語" 5
  [ "$output" = "日本" ]
  run tui_truncate "日本語" 3
  [ "$output" = "日" ]
  run tui_truncate "abcde" 3
  [ "$output" = "abc" ]
}

@test "tui_repeat_char は指定個数だけ繰り返す" {
  run tui_repeat_char "─" 5
  [ "$output" = "─────" ]
}

# ---------------------------------------------------------------------------
# 罫線ボックス（日本語混在でも右端がそろう）
# ---------------------------------------------------------------------------

@test "box の各行は日本語混在でも指定幅にそろう" {
  local w=44 line
  for line in \
    "$(tui_component_box_top "$w" "safersync v1.1.0")" \
    "$(tui_component_box_row "$w" "コピー元: /Volumes/Untitled/DCIM/100GOPRO")" \
    "$(tui_component_box_sep "$w")" \
    "$(tui_component_box_blank "$w")" \
    "$(tui_component_box_bottom "$w")"; do
    [ "$(tui_str_width "$line")" = "$w" ] || { echo "width!=$w: [$line]"; return 1; }
  done
}

@test "box の行は長すぎる内容を切り詰めて幅を守る" {
  local w=20 line
  line="$(tui_component_box_row "$w" "$(printf 'あ%.0s' $(seq 1 50))")"
  [ "$(tui_str_width "$line")" = "$w" ]
}
