#!/usr/bin/env bash
#
# lib/tui/views/dashboard.sh - Step 5/6: 転送ダッシュボードと完了レポート
#
# shellcheck shell=bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034

# ダッシュボード 1 フレームを描く
tui_render_dashboard() {   # $1=pct $2=done $3=total $4=speed $5=eta
  local pct="$1" done="$2" total="$3" spd="$4" eta="${5:--1}" w h bar eta_txt buf inner
  tui_term_size; w="$TUI_COLS"; h="$TUI_LINES"
  [ "$w" -ge 50 ] || w=50
  inner=$(( w - 8 )); [ "$inner" -lt 10 ] && inner=10
  bar="$(tui_component_progress_bar "$pct" "$inner")"
  eta_txt="--"
  [ "$eta" -ge 0 ] 2>/dev/null && eta_txt="約 $(fmt_duration "$eta")"

  buf="$(tui_component_box_top "$w" "$PROG 同期中")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [$bar]  ${pct}%")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " $(fmt_bytes "$done") / $(fmt_bytes "$total")  ($(fmt_bytes "$spd")/s)  残り $eta_txt")"$'\n'
  buf="${buf}$(tui_component_box_sep "$w")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [✔] 事前チェック（マウント・空き容量）")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [▶] ファイル転送中...")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [ ] コピー後データ整合性照合")"$'\n'
  buf="${buf}$(tui_component_box_sep "$w")"$'\n'
  buf="${buf}$(tui_component_box_row "$w" " [Ctrl-C] 安全に中断（次回続きから再開できます）")"$'\n'
  buf="${buf}$(tui_component_box_bottom "$w")"
  tui_screen_render "$buf"
}

# rsync を背景実行し、転送先の増分から進捗を描く。TUI_XFER_RC を設定する
tui_run_transfer() {   # $1=src $2=dst
  local src="$1" dst="$2"
  mkdir -p "$dst" || { TUI_XFER_RC=1; return 1; }

  local total base
  total="$(scan_dir "$src" | awk '{print $2}')"; [ -n "$total" ] || total=0
  base="$(scan_dir "$dst" | awk '{print $2}')";  [ -n "$base" ]  || base=0

  local -a cmd=(rsync "${META_OPTS[@]}" --human-readable --partial "${EXCLUDE_ARGS[@]}" "$src/" "$dst/")
  if [ "$VERBOSE" = 1 ]; then cmd+=( --stats ); else cmd+=( -q ); fi
  if [ "$NO_CAFFEINATE" = 0 ] && command -v caffeinate >/dev/null 2>&1; then
    cmd=(caffeinate -i "${cmd[@]}")
  fi

  local out; out="$(mktemp "${TMPDIR:-/tmp}/safersync.tui.XXXXXX" 2>/dev/null)" || out=""
  if [ -n "$out" ]; then "${cmd[@]}" >"$out" 2>&1 & else "${cmd[@]}" 2>&1 & fi
  TUI_CHILD_PID=$!

  local start now elapsed dbytes gained speed pct eta
  start="$(date +%s)"
  while kill -0 "$TUI_CHILD_PID" 2>/dev/null; do
    sleep 1
    kill -0 "$TUI_CHILD_PID" 2>/dev/null || break
    now="$(date +%s)"; elapsed=$(( now - start )); [ "$elapsed" -gt 0 ] || elapsed=1
    dbytes="$(scan_dir "$dst" | awk '{print $2}')"; [ -n "$dbytes" ] || dbytes=0
    gained=$(( dbytes - base )); [ "$gained" -lt 0 ] && gained=0
    speed=$(( gained / elapsed ))
    pct=100; [ "$total" -gt 0 ] && pct=$(( dbytes * 100 / total )); [ "$pct" -gt 100 ] && pct=100
    eta=-1
    if [ "$speed" -gt 0 ] && [ "$total" -gt "$dbytes" ]; then eta=$(( (total - dbytes) / speed )); fi
    tui_render_dashboard "$pct" "$dbytes" "$total" "$speed" "$eta"
  done

  wait "$TUI_CHILD_PID"; local rc=$?
  TUI_CHILD_PID=""
  [ -n "$out" ] && rm -f "$out"
  TUI_XFER_RC="$rc"
  return "$rc"
}

# 照合を背景実行し、rc とログをファイルへ書き出す
tui_verify_to_file() {   # $1=basename（$1.rc と $1.log を作る）
  verify_one "$TUI_SRC" "$TUI_DST" >"$1.log" 2>&1
  local rc=$?
  printf '%s\n' "$rc" > "$1.rc"
}

# Step 5 本体。転送と照合を行い、TUI_XFER_RC を返す
tui_view_dashboard() {   # $1=src $2=dst
  local src="$1" dst="$2"
  tui_apply_options
  plan_changes "$src" "$dst"
  TUI_XFER_FILES="$PLAN_FILES"
  TUI_XFER_BYTES="$PLAN_BYTES"
  TUI_XFER_RC=0
  TUI_VERIFY_RC=0
  TUI_VERIFY_LOG=""

  local t0; t0="$(date +%s)"

  if [ "$PLAN_FILES" -gt 0 ]; then
    log_msg "COPY start  $src -> $dst ($PLAN_FILES files) [tui]"
    tui_run_transfer "$src" "$dst"
    if [ "$TUI_XFER_RC" -eq 0 ]; then
      log_msg "COPY done   $src -> $dst [tui]"
    else
      log_msg "COPY failed $src -> $dst (rc=$TUI_XFER_RC) [tui]"
    fi
  fi

  if [ "$TUI_XFER_RC" -eq 0 ]; then
    local base; base="$(mktemp "${TMPDIR:-/tmp}/safersync.vfy.XXXXXX" 2>/dev/null)"
    if [ -n "$base" ]; then
      tui_busy "コピー後の照合をしています..." tui_verify_to_file "$base"
      TUI_VERIFY_RC="$(cat "$base.rc" 2>/dev/null)"; : "${TUI_VERIFY_RC:=1}"
      TUI_VERIFY_LOG="$(cat "$base.log" 2>/dev/null)"
      rm -f "$base" "$base.rc" "$base.log"
      if [ "$TUI_VERIFY_RC" -eq 0 ]; then
        log_msg "VERIFY ok   $src vs $dst [tui]"
      else
        log_msg "VERIFY diff $src vs $dst [tui]"
      fi
    else
      TUI_VERIFY_RC=0
    fi
  else
    TUI_VERIFY_RC=1
  fi

  TUI_ELAPSED=$(( $(date +%s) - t0 ))

  # 終了コードは CLI とそろえる（コピー失敗 > 照合失敗 > 成功）
  if [ "$TUI_XFER_RC" -ne 0 ]; then return "$TUI_XFER_RC"; fi
  if [ "$TUI_VERIFY_RC" -ne 0 ]; then return 1; fi
  return 0
}

# Step 6 本体。完了レポートを表示して 1 キー待つ
tui_view_done() {   # $1=rc
  local rc="$1" w buf status verify_txt
  tui_term_size; w="$TUI_COLS"
  [ "$w" -ge 50 ] || w=50

  if [ "$rc" -eq 0 ] && [ "${TUI_VERIFY_RC:-0}" -eq 0 ]; then
    TUI_TITLE="$PROG 完了"
    status="すべての処理が正常に完了しました"
    verify_txt="正常（すべてのファイルが一致）"
  else
    TUI_TITLE="$PROG 問題あり"
    status="エラーが発生しました（終了コード $rc）"
    verify_txt="不一致または失敗（ログを確認してください）"
  fi
  TUI_HEADER=""
  TUI_FOOTER="[Enter] 終了"

  buf="$(tui_frame "$w" \
    "" \
    "  $status" \
    "" \
    "   ・転送完了: ${TUI_XFER_FILES:-0} ファイル（$(fmt_bytes "${TUI_XFER_BYTES:-0}") / $(fmt_duration "${TUI_ELAPSED:-0}")）" \
    "   ・照合結果: $verify_txt" \
    "   ・ログ保存: $LOG_FILE" \
    "" \
    "  データを保存先へコピーできました。")"
  tui_screen_render "$buf"

  local k
  while :; do
    k="$(tui_read_key)"
    case "$k" in ENTER|QUIT|ESC|' '|NONE|EOF) break;; esac
  done
}
