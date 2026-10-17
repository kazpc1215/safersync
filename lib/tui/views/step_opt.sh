#!/usr/bin/env bash
#
# lib/tui/views/step_opt.sh - Step 3: 同期オプションの設定
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# 1 項目分の表示文字列を作る（$1=index）
tui_opt_line() {
  case "$1" in
    0) printf '%s %s' "$(tui_component_checkbox "$TUI_OPT_LRV")" "プレビュー動画 (.LRV) を除外（容量・時間を節約）" ;;
    1) printf '%s %s' "$(tui_component_checkbox "$TUI_OPT_THM")" "サムネイル画像 (.THM) を除外" ;;
    2) printf '%s %s' "$(tui_component_checkbox "$TUI_OPT_TMP")" "一時ファイル (*.tmp, .DS_Store 等) も除外" ;;
    3) printf '照合方法: %s 高速照合（サイズ+更新日時・推奨）   %s 厳密照合（ハッシュ）' \
         "$(tui_component_radio "$(( 1 - TUI_OPT_CHECKSUM ))")" "$(tui_component_radio "$TUI_OPT_CHECKSUM")" ;;
    4) if command -v caffeinate >/dev/null 2>&1; then
         printf '%s %s' "$(tui_component_checkbox "$TUI_OPT_CAFFEINATE")" "スリープ防止 (caffeinate) を有効にする"
       else
         printf '%s %s' "[ ]" "スリープ防止 (caffeinate)（この環境では利用不可）"
       fi ;;
  esac
}

# Step 3 本体。0=決定 1=戻る
tui_view_options() {
  TUI_TITLE="$PROG v$VERSION  [3/4] 同期オプション"
  TUI_HEADER="スペースキーで切り替えます"
  TUI_FOOTER="[↑/↓] 移動   [Space] 切り替え   [Enter] 次へ   [Esc] 戻る"

  local n=5 sel=0 key w h i buf cur
  while :; do
    IFS=' ' read -r w h <<< "$(tui_term_size)"
    if [ "$w" -lt 50 ] || [ "$h" -lt 12 ]; then
      tui_render_tiny "$w" "$h"
      key="$(tui_read_key)"
      case "$key" in QUIT|EOF) return 1;; esac
      continue
    fi
    local -a body=()
    i=0
    while [ "$i" -lt "$n" ]; do
      cur=" "
      [ "$i" -eq "$sel" ] && cur=">"
      body+=( " $cur $(tui_opt_line "$i")" )
      i=$(( i + 1 ))
    done
    buf="$(tui_frame "$w" "${body[@]}")"
    tui_screen_render "$buf"
    key="$(tui_read_key)"
    case "$key" in
      UP|k)     sel=$(( (sel - 1 + n) % n ));;
      DOWN|j)   sel=$(( (sel + 1) % n ));;
      SPACE)
        case "$sel" in
          0) TUI_OPT_LRV=$(( 1 - TUI_OPT_LRV ));;
          1) TUI_OPT_THM=$(( 1 - TUI_OPT_THM ));;
          2) TUI_OPT_TMP=$(( 1 - TUI_OPT_TMP ));;
          3) TUI_OPT_CHECKSUM=$(( 1 - TUI_OPT_CHECKSUM ));;
          4) command -v caffeinate >/dev/null 2>&1 && TUI_OPT_CAFFEINATE=$(( 1 - TUI_OPT_CAFFEINATE ));;
        esac ;;
      ENTER)    return 0;;
      ESC|QUIT|EOF) return 1;;
      NONE)     :;;
    esac
    TUI_WINCH=0
  done
}
