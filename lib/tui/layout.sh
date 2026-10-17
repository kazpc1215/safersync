#!/usr/bin/env bash
#
# lib/tui/layout.sh - 表示幅の計算（East Asian Width）と文字列整形
#
#   日本語は 1 文字でも表示は 2 桁。${#s} は「文字数」なので罫線合わせに使えない。
#   このファイルは表示幅（桁数）を正しく数えるための純粋関数だけを持つ。
#
#   bin/safersync から source される。単体でもテストから source できる。
#
# shellcheck shell=bash

# 文字を count 個つなげて返す
tui_repeat_char() {   # $1=char $2=count
  local ch="${1-}" n="${2:-0}" out="" i=0
  while [ "$i" -lt "$n" ]; do out="${out}${ch}"; i=$(( i + 1 )); done
  printf '%s' "$out"
}

# 文字列の表示幅（桁数）を返す。
#   UTF-8 のバイト列を 1 回だけ取り、先頭バイトで文字境界を判定して数える。
#   コードポイントが East Asian Wide/Fullwidth の主要レンジなら 2、それ以外は 1。
tui_str_width() {   # $1=string
  local s="${1-}" w=0 i=0 n=0 b b1 b2 cp wcp line
  [ -n "$s" ] || { printf 0; return 0; }

  # od は 16 バイトごとに改行し、同値の連続を '*' に省略するため -v を付け、
  # 改行を空白へつぶしてから配列へ読み込む（1 行だけ読む事故を防ぐ）。
  line="$(printf '%s' "$s" | LC_ALL=C od -An -v -tu1 | tr '\n' ' ')"
  local -a B
  read -r -a B <<< "$line"
  n=${#B[@]}

  while [ "$i" -lt "$n" ]; do
    b="${B[$i]}"
    if [ "$b" -lt 32 ] || [ "$b" -eq 127 ]; then
      i=$(( i + 1 ))                       # 制御文字は幅 0
    elif [ "$b" -lt 128 ]; then
      w=$(( w + 1 )); i=$(( i + 1 ))       # ASCII
    elif [ "$b" -lt 224 ]; then
      w=$(( w + 1 )); i=$(( i + 2 ))       # 2 バイト（U+0080–U+07FF）
    elif [ "$b" -lt 240 ]; then            # 3 バイト（U+0800–U+FFFF）
      b1="${B[$(( i + 1 ))]}"; b2="${B[$(( i + 2 ))]}"
      cp=$(( (b - 224) * 4096 + (b1 - 128) * 64 + (b2 - 128) ))
      wcp=1
      if   [ "$cp" -ge 4352 ]  && [ "$cp" -le 4447 ];  then wcp=2   # U+1100–U+115F
      elif [ "$cp" -ge 11904 ] && [ "$cp" -le 42191 ]; then wcp=2   # U+2E80–U+A4CF
      elif [ "$cp" -ge 44032 ] && [ "$cp" -le 55203 ]; then wcp=2   # U+AC00–U+D7A3
      elif [ "$cp" -ge 63744 ] && [ "$cp" -le 64255 ]; then wcp=2   # U+F900–U+FAFF
      elif [ "$cp" -ge 65072 ] && [ "$cp" -le 65103 ]; then wcp=2   # U+FE30–U+FE4F
      elif [ "$cp" -ge 65280 ] && [ "$cp" -le 65376 ]; then wcp=2   # U+FF00–U+FF60
      elif [ "$cp" -ge 65504 ] && [ "$cp" -le 65510 ]; then wcp=2   # U+FFE0–U+FFE6
      fi
      w=$(( w + wcp )); i=$(( i + 3 ))
    else
      w=$(( w + 2 )); i=$(( i + 4 ))       # 4 バイト（U+10000 以上）は概ね幅 2
    fi
  done
  printf '%d' "$w"
}

# 1 文字の表示幅（tui_truncate 用の薄いラッパ）
tui_char_width() {   # $1=char
  local c="${1-}"
  [ -n "$c" ] || { printf 0; return 0; }
  tui_str_width "$c"
}

# 表示幅が target になるよう、右側を半角スペースで埋める
tui_pad_right() {   # $1=string $2=target width
  local s="${1-}" target="${2:-0}" cur pad
  cur="$(tui_str_width "$s")"
  pad=$(( target - cur )); [ "$pad" -lt 0 ] && pad=0
  printf '%s%*s' "$s" "$pad" ''
}

# 表示幅が target になるよう、左側を半角スペースで埋める（右寄せ）
tui_pad_left() {   # $1=string $2=target width
  local s="${1-}" target="${2:-0}" cur pad
  cur="$(tui_str_width "$s")"
  pad=$(( target - cur )); [ "$pad" -lt 0 ] && pad=0
  printf '%*s%s' "$pad" '' "$s"
}

# 表示幅が max を超えないように切り詰める（文字の途中では切らない）
tui_truncate() {   # $1=string $2=max width
  local s="${1-}" max="${2:-0}" out="" i=0 n cur=0 w
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    w="$(tui_char_width "${s:i:1}")"
    cur=$(( cur + w ))
    [ "$cur" -gt "$max" ] && break
    out="${out}${s:i:1}"
    i=$(( i + 1 ))
  done
  printf '%s' "$out"
}
