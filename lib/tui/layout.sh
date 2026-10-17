#!/usr/bin/env bash
#
# lib/tui/layout.sh - 表示幅の計算（East Asian Width）と文字列整形
#
#   日本語は 1 文字でも表示は 2 桁。${#s} は「文字数」なので罫線合わせに使えない。
#   このファイルは表示幅（桁数）を正しく数えるための純粋関数だけを持つ。
#
#   ★ 性能: macOS の od は 1 回の起動に ~10ms かかるうえ、$(コマンド置換) も
#     画面の行数だけ fork する。描画のたびにそれを行うとキー入力が目に見えて遅くなる。
#   そのため
#       * 印字可能 ASCII だけの文字列は、外部プロセスを一切起動せず文字数＝表示幅
#       * 日本語を含む場合は LC_ALL=C に切り替えて「バイト単位」で走査し、
#         printf -v で各バイト値を得る（bash 組み込みのみ・fork ゼロ）
#       * 結果は printf -v で変数へ直接書き込む *_into 版を本体にする
#       * 内部変数は __tui_ 接頭辞にして、呼び出し側が渡す変数名との衝突を防ぐ
#     という方針で実装する。LC_ALL は関数から抜ける前に必ず元へ戻す。
#
#   ★ 使い方: tui_str_width_into <書き込み先変数名> <文字列>
#     書き込み先変数名がこのファイルの内部変数名（__tui_ で始まる名前）と
#     衝突しないこと。通常の名前（w, out, cur など）なら安全。
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

# 印字可能 ASCII だけの文字列か（外部プロセスなしの判定）
tui_is_ascii() {   # $1=string
  case "$1" in
    *[!\ -~]*) return 1 ;;
    *)         return 0 ;;
  esac
}

# コードポイント cp の表示幅（1 or 2）。East Asian Wide/Fullwidth の主要レンジを 2。
#   tui_str_width_into / tui_truncate_into にはインライン展開している（subshell 回避）。
tui_cp_width() {   # $1=cp -> stdout 1|2
  local cp="$1"
  if   [ "$cp" -ge 4352 ]  && [ "$cp" -le 4447 ];  then printf 2   # U+1100–U+115F
  elif [ "$cp" -ge 11904 ] && [ "$cp" -le 42191 ]; then printf 2   # U+2E80–U+A4CF
  elif [ "$cp" -ge 44032 ] && [ "$cp" -le 55203 ]; then printf 2   # U+AC00–U+D7A3
  elif [ "$cp" -ge 63744 ] && [ "$cp" -le 64255 ]; then printf 2   # U+F900–U+FAFF
  elif [ "$cp" -ge 65072 ] && [ "$cp" -le 65103 ]; then printf 2   # U+FE30–U+FE4F
  elif [ "$cp" -ge 65280 ] && [ "$cp" -le 65376 ]; then printf 2   # U+FF00–U+FF60
  elif [ "$cp" -ge 65504 ] && [ "$cp" -le 65510 ]; then printf 2   # U+FFE0–U+FFE6
  else printf 1
  fi
}

# 文字列の表示幅（桁数）を変数へ書き込む（コマンド置換を使わない）
tui_str_width_into() {   # $1=varname $2=string
  local __tui_var="$1" __tui_s="${2-}"
  if [ -z "$__tui_s" ]; then printf -v "$__tui_var" '%d' 0; return 0; fi

  # 高速パス: 印字可能 ASCII なら文字数がそのまま表示幅
  if tui_is_ascii "$__tui_s"; then printf -v "$__tui_var" '%d' "${#__tui_s}"; return 0; fi

  local __tui_saved="${LC_ALL-}"
  LC_ALL=C                       # ここからバイト単位
  local __tui_n=${#__tui_s} __tui_i=0 __tui_w=0 __tui_c __tui_b __tui_b1 __tui_b2 __tui_cp __tui_wcp
  while [ "$__tui_i" -lt "$__tui_n" ]; do
    __tui_c="${__tui_s:$__tui_i:1}"
    # 印字可能 ASCII はバイト値の取得すら不要（1 桁）
    case "$__tui_c" in
      [[:print:]]) __tui_w=$(( __tui_w + 1 )); __tui_i=$(( __tui_i + 1 )); continue ;;
    esac
    printf -v __tui_b '%d' "'$__tui_c"; [ "$__tui_b" -lt 0 ] && __tui_b=$(( __tui_b + 256 ))
    if [ "$__tui_b" -lt 128 ]; then
      __tui_i=$(( __tui_i + 1 ))             # 制御文字は幅 0
    elif [ "$__tui_b" -lt 224 ]; then
      __tui_w=$(( __tui_w + 1 )); __tui_i=$(( __tui_i + 2 ))   # 2 バイト（U+0080–U+07FF）
    elif [ "$__tui_b" -lt 240 ]; then          # 3 バイト（U+0800–U+FFFF）
      __tui_c="${__tui_s:$(( __tui_i + 1 )):1}"; printf -v __tui_b1 '%d' "'$__tui_c"; [ "$__tui_b1" -lt 0 ] && __tui_b1=$(( __tui_b1 + 256 ))
      __tui_c="${__tui_s:$(( __tui_i + 2 )):1}"; printf -v __tui_b2 '%d' "'$__tui_c"; [ "$__tui_b2" -lt 0 ] && __tui_b2=$(( __tui_b2 + 256 ))
      __tui_cp=$(( (__tui_b - 224) * 4096 + (__tui_b1 - 128) * 64 + (__tui_b2 - 128) ))
      __tui_wcp=1
      if   [ "$__tui_cp" -ge 4352 ]  && [ "$__tui_cp" -le 4447 ];  then __tui_wcp=2
      elif [ "$__tui_cp" -ge 11904 ] && [ "$__tui_cp" -le 42191 ]; then __tui_wcp=2
      elif [ "$__tui_cp" -ge 44032 ] && [ "$__tui_cp" -le 55203 ]; then __tui_wcp=2
      elif [ "$__tui_cp" -ge 63744 ] && [ "$__tui_cp" -le 64255 ]; then __tui_wcp=2
      elif [ "$__tui_cp" -ge 65072 ] && [ "$__tui_cp" -le 65103 ]; then __tui_wcp=2
      elif [ "$__tui_cp" -ge 65280 ] && [ "$__tui_cp" -le 65376 ]; then __tui_wcp=2
      elif [ "$__tui_cp" -ge 65504 ] && [ "$__tui_cp" -le 65510 ]; then __tui_wcp=2
      fi
      __tui_w=$(( __tui_w + __tui_wcp )); __tui_i=$(( __tui_i + 3 ))
    else
      __tui_w=$(( __tui_w + 2 )); __tui_i=$(( __tui_i + 4 ))   # 4 バイト（U+10000 以上）は概ね幅 2
    fi
  done
  if [ -n "$__tui_saved" ]; then LC_ALL="$__tui_saved"; else unset LC_ALL; fi
  printf -v "$__tui_var" '%d' "$__tui_w"
}

# 1 文字の表示幅
tui_char_width() {   # $1=char
  local c="${1-}" w
  tui_str_width_into w "$c"
  printf '%s' "$w"
}

# 表示幅が max を超えないように切り詰め、変数へ書き込む。
#   日本語を含む場合も、バイト境界を数えながら max 以内で切る（文字の途中で切らない）。
tui_truncate_into() {   # $1=varname $2=string $3=max width
  local __tui_var="$1" __tui_s="${2-}" __tui_max="${3:-0}"
  if [ -z "$__tui_s" ]; then printf -v "$__tui_var" '%s' ''; return 0; fi
  if ! [ "$__tui_max" -gt 0 ] 2>/dev/null; then printf -v "$__tui_var" '%s' ''; return 0; fi

  # 高速パス: 印字可能 ASCII は文字数で切れる
  if tui_is_ascii "$__tui_s"; then
    if [ "${#__tui_s}" -le "$__tui_max" ]; then printf -v "$__tui_var" '%s' "$__tui_s"
    else printf -v "$__tui_var" '%s' "${__tui_s:0:__tui_max}"; fi
    return 0
  fi

  local __tui_saved="${LC_ALL-}"
  LC_ALL=C                       # ここからバイト単位
  local __tui_n=${#__tui_s} __tui_i=0 __tui_w=0 __tui_c __tui_b __tui_b1 __tui_b2 __tui_cp __tui_wcp __tui_step
  while [ "$__tui_i" -lt "$__tui_n" ]; do
    __tui_c="${__tui_s:$__tui_i:1}"
    case "$__tui_c" in
      [[:print:]]) __tui_wcp=1; __tui_step=1 ;;
      *)
        printf -v __tui_b '%d' "'$__tui_c"; [ "$__tui_b" -lt 0 ] && __tui_b=$(( __tui_b + 256 ))
        if [ "$__tui_b" -lt 128 ]; then
          __tui_wcp=0; __tui_step=1
        elif [ "$__tui_b" -lt 224 ]; then
          __tui_wcp=1; __tui_step=2
        elif [ "$__tui_b" -lt 240 ]; then
          __tui_c="${__tui_s:$(( __tui_i + 1 )):1}"; printf -v __tui_b1 '%d' "'$__tui_c"; [ "$__tui_b1" -lt 0 ] && __tui_b1=$(( __tui_b1 + 256 ))
          __tui_c="${__tui_s:$(( __tui_i + 2 )):1}"; printf -v __tui_b2 '%d' "'$__tui_c"; [ "$__tui_b2" -lt 0 ] && __tui_b2=$(( __tui_b2 + 256 ))
          __tui_cp=$(( (__tui_b - 224) * 4096 + (__tui_b1 - 128) * 64 + (__tui_b2 - 128) ))
          __tui_wcp=1
          if   [ "$__tui_cp" -ge 4352 ]  && [ "$__tui_cp" -le 4447 ];  then __tui_wcp=2
          elif [ "$__tui_cp" -ge 11904 ] && [ "$__tui_cp" -le 42191 ]; then __tui_wcp=2
          elif [ "$__tui_cp" -ge 44032 ] && [ "$__tui_cp" -le 55203 ]; then __tui_wcp=2
          elif [ "$__tui_cp" -ge 63744 ] && [ "$__tui_cp" -le 64255 ]; then __tui_wcp=2
          elif [ "$__tui_cp" -ge 65072 ] && [ "$__tui_cp" -le 65103 ]; then __tui_wcp=2
          elif [ "$__tui_cp" -ge 65280 ] && [ "$__tui_cp" -le 65376 ]; then __tui_wcp=2
          elif [ "$__tui_cp" -ge 65504 ] && [ "$__tui_cp" -le 65510 ]; then __tui_wcp=2
          fi
          __tui_step=3
        else
          __tui_wcp=2; __tui_step=4
        fi ;;
    esac
    [ $(( __tui_w + __tui_wcp )) -gt "$__tui_max" ] && break
    __tui_w=$(( __tui_w + __tui_wcp ))
    __tui_i=$(( __tui_i + __tui_step ))
  done
  local __tui_slice="${__tui_s:0:__tui_i}"
  if [ -n "$__tui_saved" ]; then LC_ALL="$__tui_saved"; else unset LC_ALL; fi
  printf -v "$__tui_var" '%s' "$__tui_slice"
}

# 表示幅が target になるよう右側を半角スペースで埋め、変数へ書き込む
tui_pad_right_into() {   # $1=varname $2=string $3=target width
  local __tui_var="$1" __tui_s="${2-}" __tui_target="${3:-0}" __tui_cur __tui_pad
  tui_str_width_into __tui_cur "$__tui_s"
  __tui_pad=$(( __tui_target - __tui_cur )); [ "$__tui_pad" -lt 0 ] && __tui_pad=0
  printf -v "$__tui_var" '%s%*s' "$__tui_s" "$__tui_pad" ''
}

# 表示幅が target になるよう左側を半角スペースで埋め、変数へ書き込む（右寄せ）
tui_pad_left_into() {   # $1=varname $2=string $3=target width
  local __tui_var="$1" __tui_s="${2-}" __tui_target="${3:-0}" __tui_cur __tui_pad
  tui_str_width_into __tui_cur "$__tui_s"
  __tui_pad=$(( __tui_target - __tui_cur )); [ "$__tui_pad" -lt 0 ] && __tui_pad=0
  printf -v "$__tui_var" '%*s%s' "$__tui_pad" '' "$__tui_s"
}

# --- 文字列を返す薄いラッパ（単発利用・テスト向け）---

tui_str_width() { local __tui_out; tui_str_width_into  __tui_out "${1-}";          printf '%s' "$__tui_out"; }
tui_truncate()  { local __tui_out; tui_truncate_into   __tui_out "${1-}" "${2:-0}"; printf '%s' "$__tui_out"; }
tui_pad_right() { local __tui_out; tui_pad_right_into  __tui_out "${1-}" "${2:-0}"; printf '%s' "$__tui_out"; }
tui_pad_left()  { local __tui_out; tui_pad_left_into   __tui_out "${1-}" "${2:-0}"; printf '%s' "$__tui_out"; }
