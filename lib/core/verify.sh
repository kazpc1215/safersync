#!/usr/bin/env bash
#
# lib/core/verify.sh - データ照合エンジン（差分・ファイル数・合計バイト数）
#
#   bin/safersync から source される。単体では実行しない。
#
# shellcheck shell=bash

verify_one() {   # $1=src $2=dst
  local src="$1" dst="$2"
  [ -d "$src" ] || { err "コピー元が存在しません: $src"; return 1; }
  [ -d "$dst" ] || { err "コピー先が存在しません: $dst"; return 1; }

  # --delete を付けないので、転送先の余分なファイルは差分として出ない
  collect_diff "$src" "$dst" '%i %n'

  # 「ディレクトリの属性・時刻だけの違い（.d…）」は中身とは無関係で、OS 側の
  # 都合で合わせられないことがある（exFAT のボリューム直下は 1970 年で固定）。
  # 合否はファイルの欠落・内容の違いだけで判定する。
  local sig
  sig="$(printf '%s\n' "$DIFF_RAW" | grep -v '^\.d' | grep -v '^$')"

  if [ -n "$sig" ]; then
    err "差分が見つかりました（コピー先に未転送/不一致のファイルがあります）:"
    printf '%s\n' "$sig" | head -n 20
    if [ "$(printf '%s\n' "$sig" | wc -l | tr -d ' ')" -gt 20 ]; then
      printf '    …（他 %d 件）\n' "$(( $(printf '%s\n' "$sig" | wc -l | tr -d ' ') - 20 ))"
    fi
    log_msg "VERIFY diff $src vs $dst"
    return 1
  fi

  # 集計は「参考情報」。転送先の余分なファイルは許容するため、
  # 数が一致しなくても失敗にしない（合否判定は上の rsync 差分で行う）。
  local sc dc sb db sres dres extra
  sres="$(scan_dir "$src")"; dres="$(scan_dir "$dst")"
  sc="${sres%% *}";  sb="${sres##* }"
  dc="${dres%% *}";  db="${dres##* }"
  extra=$(( dc - sc ))

  printf '    コピー元 %s ファイル / %s、転送先 %s ファイル / %s\n' \
    "$sc" "$(fmt_bytes "$sb")" "$dc" "$(fmt_bytes "$db")"
  if [ "$extra" -gt 0 ]; then
    info "転送先には ${extra} 件多いファイルがあります（削除しません）"
  elif [ "$extra" -lt 0 ]; then
    warn "転送先の方が $((-extra)) 件少ないです（要確認）"
  fi

  ok "照合 OK（コピー元の全ファイルが転送先に存在）"
  log_msg "VERIFY ok   $src vs $dst (src $sc files / dst $dc files)"
  return 0
}
