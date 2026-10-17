#!/usr/bin/env bats
#
# TUI 画面ロジックのテスト（コピー先ボリューム候補・フォルダ選択）
#
#   端末制御を含む関数は読み込まず、候補作りだけを擬似端末なしで検証する。
#
#   TUI_PICK_LABEL / TUI_BROWSE_ROOT などは source した関数が読むグローバル。
# shellcheck disable=SC2034

setup() {
  LIB_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/lib"
  # shellcheck source=/dev/null
  . "$LIB_DIR/core/env.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/core/disk.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/views/picker.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/views/step_src.sh"
  # shellcheck source=/dev/null
  . "$LIB_DIR/tui/views/step_dst.sh"

  # ボリュームの基点をテスト用の一時フォルダへ向ける
  MOUNT_ROOT="$BATS_TEST_TMPDIR/vols"
  mkdir -p "$MOUNT_ROOT/HDD"
  mkdir -p "$BATS_TEST_TMPDIR/src"
}

# ---------------------------------------------------------------------------
# コピー先ボリュームの候補
# ---------------------------------------------------------------------------

@test "コピー元が内蔵ディスクでも保存先候補が空にならない" {
  TUI_SRC="$BATS_TEST_TMPDIR/src"
  tui_dest_volumes "$TUI_SRC"
  [ "${#TUI_VOLS[@]}" -gt 0 ]
  # CLI と同様、内蔵ディスク (/) も候補に含める
  [ "${TUI_VOLS[0]}" = "/" ]
}

@test "外付けに見えるボリュームも候補に含める" {
  TUI_SRC="$BATS_TEST_TMPDIR/src"
  tui_dest_volumes "$TUI_SRC"
  local found=0 v
  for v in "${TUI_VOLS[@]}"; do
    [ "$v" = "$MOUNT_ROOT/HDD" ] && found=1
  done
  [ "$found" = 1 ]
}

@test "コピー元と同じボリュームだと分かる印を付ける" {
  TUI_SRC="$BATS_TEST_TMPDIR/src"
  tui_dest_volumes "$TUI_SRC"
  # 一時フォルダは実マウントではないので、基点 "/" がコピー元ボリュームになる
  [[ "${TUI_VOL_LABELS[0]}" == *"コピー元と同じボリューム"* ]]
}

# ---------------------------------------------------------------------------
# フォルダ選択（階層移動）の候補
# ---------------------------------------------------------------------------

@test "下位フォルダへ移動できる候補を出す" {
  mkdir -p "$BATS_TEST_TMPDIR/v/root/sub/deep"
  TUI_BROWSE_ROOT="$BATS_TEST_TMPDIR/v/root"
  TUI_PICK_LABEL="コピー元"
  tui_browse_entries "$TUI_BROWSE_ROOT"
  local joined; joined="$(printf '%s\n' "${TUI_BROWSE_PATHS[@]}")"
  [[ "$joined" == *"$TUI_BROWSE_ROOT/sub"* ]]
}

@test "上の階層へ戻れる（ルートでは戻れない）" {
  mkdir -p "$BATS_TEST_TMPDIR/v/root/sub"
  TUI_BROWSE_ROOT="$BATS_TEST_TMPDIR/v/root"
  TUI_PICK_LABEL="コピー先"

  # ルートでは ".." を出さない
  tui_browse_entries "$TUI_BROWSE_ROOT"
  local p
  for p in "${TUI_BROWSE_PATHS[@]}"; do
    [ "$p" = "$BATS_TEST_TMPDIR/v" ] && { echo "ルートで .. が出た"; return 1; }
  done

  # 下位では先頭が親フォルダになる
  tui_browse_entries "$TUI_BROWSE_ROOT/sub"
  [ "${TUI_BROWSE_PATHS[0]}" = "$TUI_BROWSE_ROOT" ]
}

@test "決定・新規作成・手動入力の項目を常に出す" {
  mkdir -p "$BATS_TEST_TMPDIR/v/root"
  TUI_BROWSE_ROOT="$BATS_TEST_TMPDIR/v/root"
  TUI_PICK_LABEL="コピー先"
  tui_browse_entries "$TUI_BROWSE_ROOT"
  local joined; joined="$(printf '%s\n' "${TUI_BROWSE_PATHS[@]}")"
  [[ "$joined" == *"__SELECT__"* ]]
  [[ "$joined" == *"__NEW__"* ]]
  [[ "$joined" == *"__MANUAL__"* ]]
}
