#!/bin/sh
# dsh web 幂等自启脚本（通用版）
# 用法: sh dsh-autostart.sh [端口]          # 默认 8080
# 环境变量可覆盖:
#   DSH         dsh 可执行文件路径（默认 PATH 里的 dsh 或 ~/.npm-global/bin/dsh）
#   DSH_HOME    dsh 数据目录（默认 ~/.dsh）
#   DSH_BIND    监听地址（默认 127.0.0.1；局域网远程模式用 0.0.0.0）
PORT="${1:-8080}"
BIND="${DSH_BIND:-127.0.0.1}"
URL="http://127.0.0.1:${PORT}/"
DSH="${DSH:-$(command -v dsh 2>/dev/null || echo "$HOME/.npm-global/bin/dsh")}"
BASE="${DSH_HOME:-$HOME/.dsh}/autostart"
LOG="${DSH_HOME:-$HOME/.dsh}/dsh-web-${PORT}.log"
PIDFILE="${DSH_HOME:-$HOME/.dsh}/dsh-web-${PORT}.pid"
LOCKDIR="$BASE/.start.lock.d"
RUNLOG="$BASE/last-run.log"

[ -x "$DSH" ] || { echo "dsh not found: $DSH"; exit 1; }

# 1) HTTP 探活：已在运行则退出
if curl -s -m 2 -o /dev/null "$URL"; then
  echo "already-running (port $PORT)"
  exit 0
fi

# 2) mkdir 原子锁（带持锁者存活检测）
mkdir -p "$BASE"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  STALE=1
  [ -f "$LOCKDIR/pid" ] && LP=$(cat "$LOCKDIR/pid" 2>/dev/null) && [ -n "$LP" ] && kill -0 "$LP" 2>/dev/null && STALE=0
  [ "$STALE" -eq 0 ] && { echo "locked-by-other (pid $LP), skip"; exit 0; }
  rm -rf "$LOCKDIR" 2>/dev/null
  mkdir "$LOCKDIR" 2>/dev/null || { echo "cannot-take-lock, skip"; exit 0; }
fi
echo $$ > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT INT TERM

# 3) 启动
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null && { echo "pid-alive, skip"; exit 0; }
fi
setsid "$DSH" web --port "$PORT" --host "$BIND" >>"$LOG" 2>&1 < /dev/null &
DPID=$!
echo "$DPID" > "$PIDFILE"
echo "launched pid=$DPID, waiting for port $PORT..."

# 4) 等待就绪（最多 60s）
i=0
while [ "$i" -lt 60 ]; do
  if curl -s -m 2 -o /dev/null "$URL"; then
    echo "started OK (port $PORT, pid $DPID)"
    rm -f "$PIDFILE"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "TIMEOUT waiting for port $PORT, see $LOG"
exit 1
