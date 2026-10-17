#!/usr/bin/env bash
#
# lib/core/sync.sh - rsync 実行・差分収集・除外制御・進捗表示
#
#   bin/safersync から source される。単体では実行しない。
#
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# 既定値（コマンドラインで上書きする）
# ---------------------------------------------------------------------------
DEFAULT_EXCLUDES=(
  ".DS_Store"
  "._*"
  ".Spotlight-V100"
  ".fseventsd"
  ".Trashes"
  ".TemporaryItems"
  ".AppleDouble"
)

# コピー先が exFAT / FAT の場合 1（既定）。
# exFAT はパーミッション・所有権を保存できず時刻にも誤差が出るため、
# それらを比較から外して「差分の誤検知」を防ぐ。
# --apfs を付けると 0 になる（-a を使う）。
FAT_MODE=1

# ---------------------------------------------------------------------------
# 除外オプションの組み立て
# ---------------------------------------------------------------------------
EXCLUDE_ARGS=()
META_OPTS=()
FIND_EXCL=()
build_rsync_opts() {
  EXCLUDE_ARGS=()
  local e
  for e in "${DEFAULT_EXCLUDES[@]}"; do EXCLUDE_ARGS+=("--exclude=$e"); done
  for e in "${EXCLUDE_PATTERNS[@]}"; do EXCLUDE_ARGS+=("--exclude=$e"); done

  if [ "$FAT_MODE" = 1 ]; then
    # -rlt: 再帰・シンボリックリンク・更新時刻を保持（-p/-o/-g は付けない）
    # --modify-window=2: exFAT の時刻丸めによる誤差を許容
    META_OPTS=( -rlt --modify-window=2 )
  else
    META_OPTS=( -a )
  fi

  # 照合時のファイル数・サイズ集計でも、転送時と同じ除外を適用する
  FIND_EXCL=()
  local first=1
  for e in "${DEFAULT_EXCLUDES[@]}" "${EXCLUDE_PATTERNS[@]}"; do
    [ -n "$e" ] || continue
    if [ "$first" = 1 ]; then FIND_EXCL+=( -name "$e" ); first=0
    else FIND_EXCL+=( -o -name "$e" ); fi
  done
}

# rsync の dry-run を行い、結果を DIFF_RAW に入れる（空なら差分なし）
#   $1=src $2=dst $3=出力フォーマット（既定: %i %n）
DIFF_RAW=""
collect_diff() {
  local -a opts=(-n --out-format="${3:-%i %n}" "${META_OPTS[@]}" "${EXCLUDE_ARGS[@]}")
  [ "$CHECKSUM" = 1 ] && opts+=( --checksum )
  DIFF_RAW="$(rsync "${opts[@]}" "$1/" "$2/" 2>/dev/null)"
}

# コピーが必要なファイルの「件数・合計バイト数・一覧」を求める
#   結果は PLAN_FILES / PLAN_BYTES / PLAN_LINES に入る。
#   ディレクトリや属性だけの変化は数えない（ファイルだけを対象にする）。
PLAN_FILES=0
PLAN_BYTES=0
PLAN_LINES=()
plan_changes() {   # $1=src $2=dst
  collect_diff "$1" "$2" '%i %l %n'

  PLAN_FILES=0
  PLAN_BYTES=0
  PLAN_LINES=()

  local line item size name
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    item="${line%% *}"
    case "$item" in
      '>f'*) ;;          # 転送される通常ファイル
      *) continue ;;     # ディレクトリ・属性のみの変化は対象外
    esac
    size="${line#* }"; size="${size%% *}"
    name="${line#* }"; name="${name#* }"
    PLAN_FILES=$(( PLAN_FILES + 1 ))
    PLAN_BYTES=$(( PLAN_BYTES + ${size:-0} ))
    PLAN_LINES+=( "$item $name" )
  done <<< "$DIFF_RAW"
}

# ---------------------------------------------------------------------------
# 進捗表示（プログレスバー ＋ 速度 ＋ 残り時間）
# ---------------------------------------------------------------------------
draw_progress() {   # $1=pct $2=done $3=total $4=speed(bps) $5=eta秒(-1で不明)
  local pct="$1" done="$2" total="$3" spd="$4" eta="$5"

  # 端末幅に合わせてバーの長さを変える（狭いと折り返して表示が崩れるため）
  local cols="${COLUMNS:-}"
  [ -n "$cols" ] || cols="$(tput cols 2>/dev/null || echo 80)"
  local width
  if   [ "$cols" -ge 110 ] 2>/dev/null; then width=24
  elif [ "$cols" -ge 90 ];              then width=16
  elif [ "$cols" -ge 70 ];              then width=8
  else                                       width=0
  fi

  local bar="" filled i prefix="" eta_txt="--"
  if [ "$width" -gt 0 ]; then
    filled=$(( pct * width / 100 ))
    i=0
    while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
    while [ "$i" -lt "$width" ];  do bar="${bar}░"; i=$((i + 1)); done
    prefix="[$bar] "
  fi
  if [ "$eta" -ge 0 ] 2>/dev/null; then eta_txt="約 $(fmt_duration "$eta")"; fi

  local tail_txt="  残り $eta_txt"
  [ "$pct" -ge 100 ] && tail_txt=""

  printf '\r\033[K  %s%3d%%  %s / %s  %s/s%s' \
    "$prefix" "$pct" "$(fmt_bytes "$done")" "$(fmt_bytes "$total")" "$(fmt_bytes "$spd")" "$tail_txt"
}

# コマンド（rsync）を実行しながら、転送先の増分から進捗と残り時間を表示する
run_with_progress() {   # $1=src $2=dst $3...=実行するコマンド
  local src="$1" dst="$2"; shift 2
  local total base start now elapsed done_bytes gained speed pct eta
  total="$(scan_dir "$src" | awk '{print $2}')"; [ -n "$total" ] || total=0
  base="$(scan_dir "$dst" | awk '{print $2}')";  [ -n "$base" ]  || base=0
  start="$(date +%s)"

  # rsync の統計出力は一時ファイルへ退避し、進捗行と混ざらないようにする
  local out; out="$(mktemp "${TMPDIR:-/tmp}/safersync.XXXXXX" 2>/dev/null)" || out=""
  if [ -n "$out" ]; then "$@" >"$out" 2>&1 & else "$@" 2>&1 & fi
  local pid=$!

  # Ctrl-C / TERM で子プロセス（caffeinate → rsync）も確実に止める
  trap 'pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; sleep 1; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf "\n中断しました\n" >&2; exit 130' INT TERM

  local cmd_rc=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2
    kill -0 "$pid" 2>/dev/null || break
    now="$(date +%s)"; elapsed=$(( now - start )); [ "$elapsed" -gt 0 ] || elapsed=1
    done_bytes="$(scan_dir "$dst" | awk '{print $2}')"; [ -n "$done_bytes" ] || done_bytes=0
    gained=$(( done_bytes - base )); [ "$gained" -lt 0 ] && gained=0
    speed=$(( gained / elapsed ))
    if [ "$total" -gt 0 ]; then pct=$(( done_bytes * 100 / total )); else pct=100; fi
    [ "$pct" -gt 100 ] && pct=100
    if [ "$speed" -gt 0 ] && [ "$total" -gt "$done_bytes" ]; then
      eta=$(( (total - done_bytes) / speed ))
    else
      eta=-1
    fi
    draw_progress "$pct" "$done_bytes" "$total" "$speed" "$eta"
  done

  wait "$pid"; cmd_rc=$?
  trap - INT TERM
  printf '\r\033[K'
  if [ -n "$out" ]; then [ -s "$out" ] && cat "$out"; rm -f "$out"; fi
  return "$cmd_rc"
}

# ---------------------------------------------------------------------------
# コピー（--delete は使わない。既存のファイルは消さない）
# ---------------------------------------------------------------------------
copy_one() {   # $1=src $2=dst
  local src="$1" dst="$2"
  [ -d "$src" ] || { err "コピー元が存在しません: $src"; return 1; }

  # ボリュームの直下を指定すると中身が散らばるので、先に知らせる
  if is_mount_point "$dst"; then
    warn "コピー先がボリュームの直下です: $dst"
    warn "コピー元の中身がこのフォルダの直下に入ります（まとめたいときは下位フォルダを指定してください）"
  fi

  # 何件・何バイトコピーする必要があるかを先に調べる
  plan_changes "$src" "$dst"

  if [ "$PLAN_FILES" -eq 0 ]; then
    ok "転送するものはありません（すべて最新です）"
    log_msg "COPY skip   $src -> $dst (no changes)"
    return 0
  fi

  if [ "$DRY_RUN" = 1 ]; then
    printf '    コピーするファイル: %d 件（%s） ※dry-run のため実際にはコピーしません\n' \
      "$PLAN_FILES" "$(fmt_bytes "$PLAN_BYTES")"
    local shown=0 l
    for l in "${PLAN_LINES[@]}"; do
      [ "$shown" -lt 20 ] || break
      printf '    %s\n' "$l"
      shown=$((shown + 1))
    done
    if [ "${#PLAN_LINES[@]}" -gt 20 ]; then
      printf '    …（他 %d 件）\n' "$(( ${#PLAN_LINES[@]} - 20 ))"
    fi
    printf '    %s\n' "（記号: > 新規/更新, f ファイル, + 新規作成, s サイズ, t 時刻）"
    return 0
  fi

  # 空き容量の確認（足りなければ、始める前に止める）
  if [ "$IGNORE_SPACE" = 0 ]; then
    local free; free="$(free_bytes "$dst")"
    if [ "${free:-0}" -gt 0 ] && [ "$PLAN_BYTES" -gt "$free" ]; then
      err "空き容量が足りません: コピーする量 $(fmt_bytes "$PLAN_BYTES") / 空き $(fmt_bytes "$free")"
      err "不要なファイルを削除するか、別の保存先を指定してください。"
      err "空き容量を無視して続行するには --ignore-space-check を付けてください。"
      log_msg "COPY abort  $src -> $dst (not enough space)"
      return 3
    fi
  fi

  mkdir -p "$dst" || { err "コピー先を作成できません: $dst"; return 1; }

  printf '    コピーするファイル: %d 件（%s）\n' "$PLAN_FILES" "$(fmt_bytes "$PLAN_BYTES")"
  log_msg "COPY start  $src -> $dst ($PLAN_FILES files)"
  local -a cmd=(rsync "${META_OPTS[@]}" --human-readable --partial "${EXCLUDE_ARGS[@]}" "$src/" "$dst/")
  if [ "$VERBOSE" = 1 ]; then cmd+=( --stats ); else cmd+=( -q ); fi
  if [ "$NO_CAFFEINATE" = 0 ] && command -v caffeinate >/dev/null 2>&1; then
    cmd=(caffeinate -i "${cmd[@]}")
  fi

  local copy_start copy_end rc=0
  copy_start="$(date +%s)"
  if [ "$SHOW_PROGRESS" = 1 ]; then
    run_with_progress "$src" "$dst" "${cmd[@]}" || rc=$?
  else
    "${cmd[@]}" || rc=$?
  fi
  copy_end="$(date +%s)"
  if [ "$rc" -ne 0 ]; then
    err "rsync がエラー終了しました (rc=$rc)"
    log_msg "COPY failed $src -> $dst (rc=$rc)"
    return 1
  fi
  ok "コピー完了（${PLAN_FILES} ファイル / $(fmt_bytes "$PLAN_BYTES") / $(fmt_duration $(( copy_end - copy_start )))）"
  log_msg "COPY done   $src -> $dst"
  TOTAL_FILES=$(( TOTAL_FILES + PLAN_FILES ))
  TOTAL_BYTES=$(( TOTAL_BYTES + PLAN_BYTES ))
  return 0
}

# ---------------------------------------------------------------------------
# 1件の処理（コピー → 照合のオーケストレーション）
# ---------------------------------------------------------------------------
run_job() {   # $1=src $2=dst
  local src="$1" dst="$2"
  if [ "$MODE" = "verify" ]; then
    verify_one "$src" "$dst"; return $?
  fi

  copy_one "$src" "$dst"; local crc=$?
  [ "$crc" -eq 0 ] || return "$crc"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi

  if [ "$DO_VERIFY" = 1 ]; then
    verify_one "$src" "$dst" || return 1
  fi
  return 0
}
