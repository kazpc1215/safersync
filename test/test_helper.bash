#!/usr/bin/env bash
#
# safersync のテスト共通ヘルパ（bats-core）
#
#   すべてのテストは一時フォルダ内と、このテストが作成した exFAT
#   ディスクイメージのマウント先だけで完結する。実データには触れない。

# テスト対象（このリポジトリの bin/safersync と lib/）
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SAFERSYNC="$REPO_ROOT/bin/safersync"
LIB_DIR="$REPO_ROOT/lib"

# exFAT テスト用ボリュームの名前（exFAT のラベルは 11 文字まで）
VOL_NAME="SAFERSYNC"

# safersync 実行のラッパ
ss() {
  "$SAFERSYNC" "$@"
}

# 除外ファイルを除いたファイル数
count_files() {
  find "$1" -type f ! -name '._*' ! -name '.DS_Store' 2>/dev/null | wc -l | tr -d ' '
}

# テスト用の exFAT ボリュームを用意する（MOUNTED_VOL に設定する）。
#   * hdiutil が無い環境では skip
#   * 既に同名ボリュームがある場合は、実データを壊さないため触らず skip
require_exfat() {
  command -v hdiutil >/dev/null 2>&1 || skip "hdiutil が無いためスキップします"

  if [ -e "/Volumes/$VOL_NAME" ]; then
    skip "/Volumes/$VOL_NAME が既に存在するためスキップします（実データを守るため触りません）"
  fi

  local img="$BATS_TEST_TMPDIR/vol.dmg"
  local size="${1:-64m}"
  hdiutil create -size "$size" -fs exFAT -volname "$VOL_NAME" "$img" >/dev/null 2>&1 \
    || skip "テスト用ディスクイメージを作成できませんでした"
  hdiutil attach "$img" >/dev/null 2>&1 \
    || skip "テスト用ディスクイメージをマウントできませんでした"

  MOUNTED_VOL="/Volumes/$VOL_NAME"
  [ -d "$MOUNTED_VOL" ] || skip "マウントポイントが見つかりません: $MOUNTED_VOL"
}

# テスト用ボリュームを外す（teardown から呼ぶ）
release_exfat() {
  [ -n "${MOUNTED_VOL:-}" ] || return 0
  hdiutil detach "$MOUNTED_VOL" >/dev/null 2>&1 || true
  MOUNTED_VOL=""
}
