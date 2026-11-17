#!/usr/bin/env bash
# CopyT 端到端测试：启动真实的 CopyT.app，模拟复制各种内容，检查数据库与媒体文件。
# 用法: ./scripts/build-app.sh && ./scripts/e2e/run.sh
# 会临时使用独立的数据目录，并在结束时恢复你原有的 CopyT 设置；运行前请先退出 CopyT。
set -uo pipefail
cd "$(dirname "$0")/../.."

APP="${APP:-build/CopyT.app}"
BIN="$APP/Contents/MacOS/CopyT"
DOMAIN="io.github.cravedl.copyt"
WORK="$(mktemp -d -t copyt-e2e)"
ROOT="$WORK/library"
DB="$ROOT/copyt.sqlite"
PBTOOL="$WORK/pbtool"
PASS=0; FAIL=0; APP_PID=""

[[ -x "$BIN" ]] || { echo "找不到 $BIN，请先运行 ./scripts/build-app.sh"; exit 1; }
if pgrep -x CopyT >/dev/null; then echo "请先退出正在运行的 CopyT"; exit 1; fi

# 备份并在退出时恢复用户自己的设置
defaults export "$DOMAIN" "$WORK/prefs-backup.plist" 2>/dev/null && HAD_PREFS=1 || HAD_PREFS=0
ORIGINAL_CLIPBOARD="$(pbpaste 2>/dev/null || true)"
cleanup() {
  stop_app
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  [[ $HAD_PREFS == 1 ]] && defaults import "$DOMAIN" "$WORK/prefs-backup.plist"
  printf '%s' "$ORIGINAL_CLIPBOARD" | pbcopy
  [[ "${KEEP_E2E:-0}" == 1 ]] && echo "保留测试目录: $WORK" || rm -rf "$WORK"
}
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
check(){ local desc="$1"; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }
q()    { sqlite3 -batch -noheader "$DB" "$1" 2>/dev/null; }
sqlq() { printf "%s" "$1" | sed "s/'/''/g"; }
pref() { defaults write "$DOMAIN" "$@"; }

# 最多等 6 秒直到 SQL 返回期望值
wait_for() {
  local sql="$1" want="$2" got=""
  for _ in $(seq 1 30); do got="$(q "$sql")"; [[ "$got" == "$want" ]] && return 0; sleep 0.2; done
  echo "     期望 [$want] 实际 [$got]  SQL: $sql"; return 1
}
# 确认 2 秒内都没有出现
stays() {
  local sql="$1" want="$2"
  sleep 2; local got; got="$(q "$sql")"
  [[ "$got" == "$want" ]] || { echo "     期望保持 [$want] 实际 [$got]"; return 1; }
}
count_text() { echo "SELECT COUNT(*) FROM items WHERE text = '$(sqlq "$1")';"; }

start_app() {
  "$BIN" >"$WORK/app.log" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 50); do [[ -f "$DB" ]] && break; sleep 0.2; done
  sleep 1 # 等第一次轮询记录下启动时的 changeCount
}
stop_app() {
  [[ -n "$APP_PID" ]] || return 0
  kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null; APP_PID=""
}
alive() { [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; }

echo "▶ 编译剪贴板测试工具"
swiftc -O scripts/e2e/pbtool.swift -o "$PBTOOL" || exit 1
pb() { "$PBTOOL" "$@"; }

defaults delete "$DOMAIN" >/dev/null 2>&1 || true
pref storagePath "$ROOT"
pref hotKeyEnabled -bool true

TODAY_DIR="media/$(date +%Y/%m/%d)"

echo "▶ 1. 启动"
pb text "启动前已在剪贴板的内容"
start_app
check "应用启动并保持运行" alive
check "在指定位置创建数据库" test -f "$DB"
check "启动前已有的剪贴板内容不记录" stays "$(count_text '启动前已在剪贴板的内容')" 0

echo "▶ 2. 文本"
pb text "Hello CopyT 你好 🎉"
check "记录纯文本" wait_for "SELECT kind FROM items WHERE text = 'Hello CopyT 你好 🎉';" text
check "记录日期为今天" wait_for "SELECT day FROM items WHERE text = 'Hello CopyT 你好 🎉';" "$(date +%Y-%m-%d)"
pb text "  第二条
多行文本  "
check "记录多行文本（原样保留空白）" wait_for "$(count_text '  第二条
多行文本  ')" 1

echo "▶ 3. 去重"
pb text "Hello CopyT 你好 🎉"
check "重复复制不新增记录" stays "$(count_text 'Hello CopyT 你好 🎉')" 1
check "重复内容移到最新" wait_for "SELECT text FROM items ORDER BY created_at DESC LIMIT 1;" "Hello CopyT 你好 🎉"

echo "▶ 4. 富文本"
pb rtf "加粗的富文本"
check "记录 RTF 为富文本" wait_for "SELECT kind FROM items WHERE text = '加粗的富文本';" richText
RTF_PATH="$(q "SELECT data_path FROM items WHERE text = '加粗的富文本';")"
check "RTF 原始数据按日期保存 ($RTF_PATH)" bash -c "[[ '$RTF_PATH' == $TODAY_DIR/*.rtf && -s '$ROOT/$RTF_PATH' ]]"
pb html "<p><b>网页</b>内容</p>" "网页内容"
check "记录 HTML 为富文本" wait_for "SELECT data_path LIKE '%.html' FROM items WHERE text = '网页内容';" 1

echo "▶ 5. 图片"
pb makepng "$WORK/test.png"
pb png "$WORK/test.png"
check "记录图片" wait_for "SELECT COUNT(*) FROM items WHERE kind = 'image';" 1
IMG_PATH="$(q "SELECT data_path FROM items WHERE kind = 'image';")"
check "图片按日期保存 ($IMG_PATH)" bash -c "[[ '$IMG_PATH' == $TODAY_DIR/*.png ]]"
check "保存的图片与原图完全一致" cmp -s "$WORK/test.png" "$ROOT/$IMG_PATH"
pb png "$WORK/test.png"
check "同一张图片不重复保存" stays "SELECT COUNT(*) FROM items WHERE kind = 'image';" 1
check "media 目录中只有一份图片" bash -c "[[ \$(ls '$ROOT/$TODAY_DIR'/*.png | wc -l) -eq 1 ]]"

echo "▶ 6. 文件"
mkdir -p "$WORK/docs"; echo a > "$WORK/docs/报告 A.txt"; echo b > "$WORK/docs/b.mov"
pb files "$WORK/docs/报告 A.txt" "$WORK/docs/b.mov"
check "记录 Finder 复制的文件" wait_for "SELECT COUNT(*) FROM items WHERE kind = 'file';" 1
check "保存了所有文件路径" wait_for "SELECT (text LIKE '%报告 A.txt%') AND (text LIKE '%b.mov%') FROM items WHERE kind = 'file';" 1
echo "     记录内容: $(q "SELECT replace(text, char(10), ' | ') FROM items WHERE kind = 'file';")"
echo "     剪贴板类型: $(osascript -e 'clipboard info' 2>&1 | head -c 400)"

echo "▶ 7. 隐私"
pb concealed "my-secret-password-123"
check "密码管理器隐藏内容不记录" stays "SELECT COUNT(*) FROM items WHERE text LIKE '%my-secret-password%';" 0
pb blank
check "纯空白内容不记录" stays "SELECT COUNT(*) FROM items WHERE trim(text, ' '||char(10)) = '';" 0

echo "▶ 8. 暂停记录"
pref paused -bool true; sleep 1
pb text "暂停期间复制"
check "暂停时不记录" stays "$(count_text '暂停期间复制')" 0
pref paused -bool false; sleep 1
pb text "恢复后复制"
check "恢复后继续记录" wait_for "$(count_text '恢复后复制')" 1

echo "▶ 9. 大文本"
python3 -c "print('大文本' * 500000, end='')" > "$WORK/big.txt"
pb textfile "$WORK/big.txt"
check "记录 1.5M 字符的文本" wait_for "SELECT COUNT(*) FROM items WHERE length(text) = 1500000;" 1
check "大文本后应用仍在运行" alive

echo "▶ 10. 资源占用"
sleep 3
CPU="$(ps -o %cpu= -p "$APP_PID" | tr -d ' ')"
RSS="$(ps -o rss= -p "$APP_PID" | tr -d ' ')"
echo "     空闲 CPU ${CPU}%，内存 $((RSS/1024)) MB"
check "空闲 CPU < 5%" python3 -c "import sys; sys.exit(0 if float('$CPU') < 5 else 1)"
check "内存 < 200 MB" test "$RSS" -lt 204800

echo "▶ 11. 重启后数据保留"
TOTAL="$(q 'SELECT COUNT(*) FROM items;')"
stop_app
pb text "应用退出期间复制"
start_app
check "重启后应用正常运行" alive
check "重启后记录数不变 ($TOTAL)" wait_for "SELECT COUNT(*) FROM items;" "$TOTAL"
check "退出期间的复制不补记" stays "$(count_text '应用退出期间复制')" 0
pb text "重启后复制"
check "重启后继续记录" wait_for "$(count_text '重启后复制')" 1

echo "▶ 12. 自动清理过期记录（保留收藏）"
OLD=$(( $(date +%s) - 90*86400 ))
q "INSERT INTO items (kind,text,created_at,day,hash,byte_size,pinned) VALUES
   ('text','过期记录',$OLD,'2000-01-01','e2e-old',1,0),
   ('text','过期但已收藏',$OLD,'2000-01-01','e2e-old-pinned',1,1);"
stop_app
pref retentionDays -int 30
start_app
check "过期记录在启动时被清理" wait_for "$(count_text '过期记录')" 0
check "收藏的过期记录保留" wait_for "$(count_text '过期但已收藏')" 1
check "未过期记录保留" wait_for "$(count_text '重启后复制')" 1

echo "▶ 13. 使用新的存放位置"
stop_app
NEW_ROOT="$WORK/新位置 with space"
pref storagePath "$NEW_ROOT"
DB="$NEW_ROOT/copyt.sqlite"
start_app
check "在新位置创建数据库" test -f "$DB"
pb text "写入新位置"
check "新记录写入新位置" wait_for "$(count_text '写入新位置')" 1
check "旧位置数据未被改动" bash -c "[[ \$(sqlite3 '$ROOT/copyt.sqlite' \"SELECT COUNT(*) FROM items WHERE text='写入新位置';\") == 0 ]]"

echo "▶ 14. 稳定性"
for i in $(seq 1 30); do pb text "快速连续复制 $i"; sleep 0.05; done
sleep 2
check "快速连续复制后应用仍在运行" alive
N="$(q "SELECT COUNT(*) FROM items WHERE text LIKE '快速连续复制 %';")"
echo "     30 次快速复制记录了 $N 条（间隔 50ms，轮询 500ms，会合并部分中间状态）"
check "最后一次快速复制一定被记录" wait_for "$(count_text '快速连续复制 30')" 1
if grep -qiE "fatal|crash|exception" "$WORK/app.log"; then bad "应用日志无异常"; cat "$WORK/app.log"; else ok "应用日志无异常"; fi

echo
echo "结果：通过 $PASS，失败 $FAIL"
[[ $FAIL -eq 0 ]]
