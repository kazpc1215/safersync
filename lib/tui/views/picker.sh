#!/usr/bin/env bash
#
# lib/tui/views/picker.sh - フォルダ選択（階層移動）画面
#
#   コピー元・コピー先で共用する。CLI がフォルダをフルパスで指定できるのに
#   そろえ、ボリュームの直下だけでなく下位フォルダへも移動して選べるようにする。
#
#   in : TUI_BROWSE_DIR   起点（絶対パス・存在すること）
#   in : TUI_BROWSE_ROOT  ここより上へは移動しない（選んだボリュームのルート）
#   in : TUI_PICK_LABEL   「コピー元」「コピー先」など（文言用）
#   in : TUI_PICK_CREATE  1 なら存在しないパスの入力・作成を許可（コピー先）
#   out: TUI_PICKED       選んだ絶対パス
#   戻り値: 0=決定 1=キャンセル
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# フォルダ 1 つ分の候補を TUI_BROWSE_PATHS / TUI_BROWSE_ITEMS に作る。
#   paths 側は実パスのほか、次の予約値が入る:
#     __SELECT__ 現在のフォルダを決定 / __NEW__ 新規作成 / __MANUAL__ 手動入力
tui_browse_entries() {   # $1=dir
  local dir="$1" d base
  TUI_BROWSE_PATHS=()
  TUI_BROWSE_ITEMS=()
  # 上の階層（ボリュームのルートや "/" では出さない）
  if [ "$dir" != "$TUI_BROWSE_ROOT" ] && [ "$dir" != "/" ]; then
    TUI_BROWSE_PATHS+=( "$(dirname "$dir")" )
    TUI_BROWSE_ITEMS+=( ".. （上の階層へ）" )
  fi
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"
    case "$base" in .*) continue;; esac
    TUI_BROWSE_PATHS+=( "${d%/}" )
    TUI_BROWSE_ITEMS+=( "$base/" )
  done
  TUI_BROWSE_PATHS+=( "__SELECT__" )
  TUI_BROWSE_ITEMS+=( "このフォルダを${TUI_PICK_LABEL}にする" )
  TUI_BROWSE_PATHS+=( "__NEW__" )
  TUI_BROWSE_ITEMS+=( "新しいフォルダを作成する..." )
  TUI_BROWSE_PATHS+=( "__MANUAL__" )
  TUI_BROWSE_ITEMS+=( "パスを手動で入力する..." )
}

tui_pick_folder() {
  local dir="${TUI_BROWSE_DIR:-}"
  [ -d "$dir" ] || { tui_message "フォルダが見つかりません: $dir"; return 1; }

  while :; do
    tui_browse_entries "$dir"
    TUI_HEADER="現在のフォルダ: $dir"
    TUI_FOOTER="[↑/↓] 移動   [Enter] 選択   [Esc] 戻る"
    TUI_ITEMS=( "${TUI_BROWSE_ITEMS[@]}" )
    TUI_MENU_SEL=0
    tui_menu || return 1
    local pick="${TUI_BROWSE_PATHS[$TUI_SELECTED]}"

    case "$pick" in
      "__SELECT__")
        TUI_PICKED="$dir"; return 0 ;;
      "__NEW__")
        TUI_PROMPT_LABEL="新しいフォルダ名を入力してください（例: backup/2024）"
        tui_prompt || continue
        local name target
        name="$(strip_trailing_slashes "$TUI_INPUT")"
        [ -n "$name" ] || continue
        case "$name" in
          /*) target="$name" ;;
          *)  target="$dir/$name" ;;
        esac
        if mkdir -p "$target" 2>/dev/null; then dir="$(abspath "$target")"
        else tui_message "フォルダを作成できません: $target"; fi
        ;;
      "__MANUAL__")
        TUI_PROMPT_LABEL="パスを入力してください（例: /Volumes/HDD/GoPro）"
        tui_prompt || continue
        [ -n "$TUI_INPUT" ] || continue
        local p; p="$(abspath "$(expand_tilde "$TUI_INPUT")")"
        if [ -d "$p" ]; then
          dir="$p"
        elif [ "${TUI_PICK_CREATE:-0}" = 1 ]; then
          if mkdir -p "$p" 2>/dev/null; then dir="$p"; else tui_message "フォルダを作成できません: $p"; fi
        else
          tui_message "フォルダが見つかりません: $p"
        fi
        ;;
      *)
        dir="$pick" ;;
    esac
  done
}
