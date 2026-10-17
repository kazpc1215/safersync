#!/usr/bin/env bats
#
# safersync のテスト（bats-core）
#
#   bats test/                      # すべて実行
#   bats test/safersync.bats        # このファイルだけ
#
# 方針:
#   * 実データには一切触れない。作業は BATS_TEST_TMPDIR と、このテストが
#     作成した exFAT ディスクイメージのマウント先だけで完結する。
#   * exFAT ボリュームが必要なテストは、同名ボリュームが既にあれば skip する。

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  MOUNTED_VOL=""

  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC/alpha" "$SRC/beta"
  echo "v1" > "$SRC/alpha/a1.mp4"
  echo "v2" > "$SRC/alpha/a2.mp4"
  echo "p1" > "$SRC/beta/b1.jpg"
}

teardown() {
  release_exfat
}

# ---------------------------------------------------------------------------
# 基本（ヘルプ・バージョン・設定ファイルを使わないこと）
# ---------------------------------------------------------------------------

@test "--version は v1.0.0 を表示する" {
  run ss --version
  [ "$status" -eq 0 ]
  [ "$output" = "safersync v1.0.0" ]
}

@test "--help に主要なオプションが表示される" {
  run ss --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"このツールはデータを削除しません"* ]]

  local opts=(--to --from --exclude --fat --apfs
              --status --verify-only --no-verify --checksum --dry-run
              --mount-root --ignore-space-check --stats)
  local o
  for o in "${opts[@]}"; do
    [[ "$output" == *"$o"* ]] || { echo "ヘルプに $o がありません"; return 1; }
  done
}

@test "設定ファイルは使わない（本体に読み込み処理が無い）" {
  ! grep -qE 'CONFIG_FILE|load_config|\.config/safersync' "$SAFERSYNC"
}

@test "--help は終了コードの一覧を表示する" {
  run ss --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"終了コード"* ]]
  [[ "$output" == *"2 コピー先が未マウント"* ]]
  [[ "$output" == *"3 空き容量不足"* ]]
}

# ---------------------------------------------------------------------------
# 引数の検証
# ---------------------------------------------------------------------------

@test "コピー元を指定しないとエラー（終了コード1）" {
  run ss
  [ "$status" -eq 1 ]
  [[ "$output" == *"コピー元"* ]]
}

@test "コピー先を指定しないとエラー（終了コード1）" {
  run ss "$SRC/alpha"
  [ "$status" -eq 1 ]
  [[ "$output" == *"コピー先"* ]]
}

@test "引数を3つ以上指定するとエラー" {
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/d" "$SRC/beta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"多すぎます"* ]]
}

@test "コピー元を2回指定するとエラー" {
  run ss --from "$SRC/alpha" --from "$SRC/beta" "$BATS_TEST_TMPDIR/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1つだけ"* ]]
}

@test "存在しないコピー元はエラー" {
  run ss "$SRC/does-not-exist" --to "$BATS_TEST_TMPDIR/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"存在しません"* ]]
}

@test "コピー先にファイルを指定するとエラー" {
  echo "x" > "$BATS_TEST_TMPDIR/afile"
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/afile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"フォルダではありません"* ]]
}

@test "不明なオプションはエラー" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/d" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"不明なオプション"* ]]
}

@test "コピー先のボリュームが未マウントなら終了コード2で中断する" {
  run ss "$SRC/alpha" "/Volumes/NO_SUCH_VOLUME_SAFERSYNC/alpha"
  [ "$status" -eq 2 ]
  [[ "$output" == *"マウントされていません"* ]]
}

# ---------------------------------------------------------------------------
# コピーと照合
# ---------------------------------------------------------------------------

@test "位置引数2つでコピーし、コピー元は残る" {
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/dst"
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dst")" -eq 2 ]
  [ "$(count_files "$SRC/alpha")" -eq 2 ]
}

@test "--from / --to でも指定できる（順序は自由）" {
  run ss --from "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dstf"
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dstf")" -eq 2 ]

  run ss --to "$BATS_TEST_TMPDIR/dstf2" "$SRC/alpha"
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dstf2")" -eq 2 ]
}

@test "相対パスは実行時のカレントディレクトリ基準になる" {
  cd "$BATS_TEST_TMPDIR" || return 1
  run ss ./src/alpha --to ./dstrel
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dstrel")" -eq 2 ]
}

@test "末尾の / の有無で意味が変わらない（フォルダが1段増えない）" {
  run ss "$SRC/alpha/" "$BATS_TEST_TMPDIR/dslash/"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/dslash/a1.mp4" ]
  [ -f "$BATS_TEST_TMPDIR/dslash/a2.mp4" ]
  [ ! -d "$BATS_TEST_TMPDIR/dslash/alpha" ]
}

@test "コピー先にファイルを末尾スラッシュ付きで指定してもエラーになる" {
  echo "x" > "$BATS_TEST_TMPDIR/afile2"
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/afile2/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"フォルダではありません"* ]]
}

@test "照合に成功すると「照合 OK」を表示する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dstok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"照合 OK"* ]]
}

@test "照合時にファイル数と合計サイズを正しく集計する（stat の実装差を吸収）" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dsc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"コピー元 2 ファイル"* ]]
  [[ "$output" == *"転送先 2 ファイル"* ]]
}

@test "既定では rsync の統計ブロックを表示しない" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dquiet"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Number of files"* ]]
}

@test "--stats を付けると rsync の統計を表示する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dstats" --stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Number of files"* ]]
}

@test "差分がないときは「転送するものはありません」と表示する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dnone"
  [ "$status" -eq 0 ]

  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dnone"
  [ "$status" -eq 0 ]
  [[ "$output" == *"転送するものはありません"* ]]
}

@test "完了時に件数とサイズのサマリを表示する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dsum"
  [ "$status" -eq 0 ]
  [[ "$output" == *"すべて完了（2 ファイル"* ]]
}

@test "--verify-only は欠けているファイルを検出して失敗する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dv"
  [ "$status" -eq 0 ]

  rm -f "$BATS_TEST_TMPDIR/dv/a1.mp4"
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dv" --verify-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"差分"* ]]
}

@test "--verify-only は一致していれば成功する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dv2"
  [ "$status" -eq 0 ]

  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dv2" --verify-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"照合 OK"* ]]
}

@test "--exclude で指定したパターンはコピーしない" {
  echo "tmp" > "$SRC/alpha/note.tmp"
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/de" --exclude '*.tmp'
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/de/note.tmp" ]
  [ -f "$BATS_TEST_TMPDIR/de/a1.mp4" ]
}

@test "--apfs（-a を使う）でもコピーできる" {
  run ss "$SRC/beta" --to "$BATS_TEST_TMPDIR/dapfs" --apfs
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dapfs")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 削除しないこと（このツールの最重要の性質）
# ---------------------------------------------------------------------------

@test "dry-run ではコピー先を作らない" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dry" -n
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/dry" ]
}

@test "dry-run はコピー件数と、省略した残り件数を表示する" {
  local i
  for i in $(seq 1 25); do echo "x" > "$SRC/alpha/n$i.mp4"; done
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dry2" -n
  [ "$status" -eq 0 ]
  # 既存 2 件 + 追加 25 件 = 27 件
  [[ "$output" == *"コピーするファイル: 27 件"* ]]
  [[ "$output" == *"…（他 7 件）"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/dry2" ]
}

@test "空き容量が足りないときは開始前に中止する（終了コード3）" {
  require_exfat 8m
  dd if=/dev/zero of="$SRC/alpha/big.bin" bs=1048576 count=20 2>/dev/null
  run ss "$SRC/alpha" "$MOUNTED_VOL/alpha"
  [ "$status" -eq 3 ]
  [[ "$output" == *"空き容量"* ]]
  [ ! -e "$MOUNTED_VOL/alpha/big.bin" ]
}

@test "--ignore-space-check なら空き容量を無視して続行できる" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dignore" --ignore-space-check
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dignore")" -eq 2 ]
}

@test "転送先の余分なファイルも、コピー元で消したファイルも削除しない" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/d2"
  [ "$status" -eq 0 ]

  # 転送先に余分なファイルを置き、コピー元からは1つ消す
  echo "extra" > "$BATS_TEST_TMPDIR/d2/extra.bin"
  rm -f "$SRC/alpha/a2.mp4"

  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/d2"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/d2/a2.mp4" ]     # コピー元で消しても転送先に残る
  [ -f "$BATS_TEST_TMPDIR/d2/extra.bin" ]  # 余分なファイルも消さない
}

@test "本体に削除コマンド（rm -rf / --delete）が無い" {
  ! awk '{ sub(/#.*/, ""); print }' "$SAFERSYNC" | grep -qE 'rm -rf|--delete'
}

# ---------------------------------------------------------------------------
# exFAT ボリューム（明示パス）
# ---------------------------------------------------------------------------

@test "exFAT の下位フォルダへコピーできる（無ければ作られる）" {
  require_exfat
  run ss "$SRC/alpha" "$MOUNTED_VOL/backup/alpha"
  [ "$status" -eq 0 ]
  [ "$(count_files "$MOUNTED_VOL/backup/alpha")" -eq 2 ]
}

@test "exFAT 上でも照合に成功する（属性差を誤検知しない）" {
  require_exfat
  run ss "$SRC/beta" "$MOUNTED_VOL/beta"
  [ "$status" -eq 0 ]
  [[ "$output" == *"照合 OK"* ]]
}

@test "コピー先がボリュームの直下なら警告し、時刻の差で照合は失敗しない" {
  require_exfat
  run ss "$SRC/alpha" "$MOUNTED_VOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ボリュームの直下"* ]]
  [[ "$output" == *"照合 OK"* ]]
  # ボリューム直下には .fseventsd などもできるため、コピーしたファイルだけを見る
  [ -f "$MOUNTED_VOL/a1.mp4" ]
  [ -f "$MOUNTED_VOL/a2.mp4" ]

  # 末尾に / を付けても「ボリューム直下」と判定される
  run ss "$SRC/alpha/" "$MOUNTED_VOL/"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ボリュームの直下"* ]]
}

# ---------------------------------------------------------------------------
# 進捗表示と状態確認
# ---------------------------------------------------------------------------

@test "非対話（パイプ）では進捗の制御文字を出力しない" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dp"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "--progress を強制しても最後まで完了する" {
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dpp" --progress
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dpp")" -eq 2 ]
}

@test "--status はマウント状況を表示する" {
  run ss --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"マウントされているボリューム"* ]]
}

@test "--to を先に書いても、位置引数をコピー元として扱う" {
  run ss --to "$BATS_TEST_TMPDIR/dorder" "$SRC/alpha"
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/dorder")" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 移植性（macOS 以外の環境向け）
# ---------------------------------------------------------------------------

@test "--mount-root でボリュームの基点を変更できる" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/mnt/NOVOL/alpha" --mount-root "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"マウントされていません"* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/mnt/NOVOL/alpha"* ]]
}

@test "環境変数 SAFERSYNC_MOUNT_ROOT でも基点を変更できる" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt2"
  export SAFERSYNC_MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt2"
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/mnt2/NOVOL/alpha"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/mnt2"* ]]
}

@test "基点の外（一時フォルダ）は未マウント判定をしない" {
  run ss "$SRC/alpha" "$BATS_TEST_TMPDIR/outside" --mount-root "$BATS_TEST_TMPDIR/mnt9"
  [ "$status" -eq 0 ]
  [ "$(count_files "$BATS_TEST_TMPDIR/outside")" -eq 2 ]
}

@test "環境変数 SAFERSYNC_LOG_DIR でログの場所を変更できる" {
  export SAFERSYNC_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dl"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/logs/safersync.log" ]
  grep -q "COPY done" "$BATS_TEST_TMPDIR/logs/safersync.log"
}

@test "XDG_STATE_HOME があればログはその下の safersync/ に置く" {
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  run ss "$SRC/alpha" --to "$BATS_TEST_TMPDIR/dx"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/state/safersync/safersync.log" ]
}

@test "--status は --mount-root を反映する" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt3"
  run ss --status --mount-root "$BATS_TEST_TMPDIR/mnt3"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/mnt3"* ]]
}

# ---------------------------------------------------------------------------
# 静的チェック
# ---------------------------------------------------------------------------

@test "shellcheck の警告がない（-S warning）" {
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck が無いためスキップします"
  run shellcheck -S warning "$SAFERSYNC"
  [ "$status" -eq 0 ]
}
