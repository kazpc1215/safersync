#!/usr/bin/env bats
#
# TUI 描画の性能を壊さないための静的チェック。
#
#   実測を伴うとマシン差で不安定になるため、
#   「遅くなる書き方」がソースへ戻ってきたことを直接検出する。
#
#   背景:
#     * macOS の `od` は 1 回 ~10ms。1 文字ごとに呼ぶと 1 行 500ms 級になり、
#       キー入力が目に見えて遅くなる（過去に実際そうなっていた）。
#     * `$(tui_term_size)` のようにコマンド置換で呼ぶと、代入がサブシェルへ
#       閉じ込められてサイズのキャッシュが効かず、毎フレーム tput を呼んでしまう。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "表示幅の計算は外部プロセス(od)を使わない" {
  run grep -nE 'od[[:space:]]+-An|od[[:space:]]+-tu1|\|[[:space:]]*od\b' "$ROOT/lib/tui/layout.sh"
  [ "$status" -ne 0 ]
}

@test "端末サイズはコマンド置換ではなくグローバル変数経由で取得する" {
  run grep -rn '\$(tui_term_size)' "$ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "罫線の各行はコマンド置換ではなく printf -v で組み立てる" {
  # box_*_into / *_into を用意し、tui_frame はそれを直接呼ぶ
  run grep -qc 'tui_component_box_row_into' "$ROOT/lib/tui/components.sh"
  [ "$status" -eq 0 ]
  run grep -n 'buf="\$(buf)\$(tui_component_box' "$ROOT/lib/tui/components.sh"
  [ "$status" -ne 0 ]
}
