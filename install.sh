#!/usr/bin/env bash
# dsh-purge installer for macOS (launchd)
set -u
VERSION="1.0.0"

LABEL="com.dshpurge.weekly"
INSTALL_DIR="$HOME/.dsh/bin"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/.dsh/logs"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
UID_="$(id -u)"
DOMAIN="gui/$UID_"

DRY=0
TIER="ab"
SCHEDULE="weekly"
ACTION="install"

usage() {
  cat <<'EOF'
dsh-purge 安装器（macOS）

用法:
  ./install.sh [选项]

选项:
  --tier <组合>     定时任务清理档位，默认 ab（可 a / b / ab / abc）
  --daily           每天执行（默认每周日 03:00）
  --off             只装脚本，不注册定时任务
  --uninstall       卸载脚本与定时任务
  --dry-run         只打印将执行的操作
  -h, --help        帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-ab}"; shift ;;
    --daily) SCHEDULE="daily" ;;
    --off) SCHEDULE="off" ;;
    --uninstall) ACTION="uninstall" ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

run() {
  if [ "$DRY" = "1" ]; then
    echo "  [dry] $*"
  else
    "$@"
  fi
}

uninstall() {
  echo "▶ 卸载 dsh-purge"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  run rm -f "$PLIST"
  run rm -f "$INSTALL_DIR/dsh-purge.sh"
  echo "完成。日志保留在 $LOG_DIR/dsh-purge.log"
  exit 0
}

[ "$ACTION" = "uninstall" ] && uninstall

echo "▶ 安装 dsh-purge $VERSION"
run mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
run cp "$SRC_DIR/purge.sh" "$INSTALL_DIR/dsh-purge.sh"
run chmod +x "$INSTALL_DIR/dsh-purge.sh"

if [ "$SCHEDULE" = "off" ]; then
  echo "已跳过定时任务注册（--off）。手动执行: $INSTALL_DIR/dsh-purge.sh --tier $TIER --yes"
  exit 0
fi

if [ "$SCHEDULE" = "daily" ]; then
  CAL='<key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer>'
  DESC="每天 03:00"
else
  CAL='<key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer>'
  DESC="每周日 03:00"
fi

PLIST_BODY="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$INSTALL_DIR/dsh-purge.sh</string>
    <string>--tier</string><string>$TIER</string>
    <string>--yes</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    $CAL
  </dict>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$LOG_DIR/dsh-purge.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/dsh-purge.err.log</string>
</dict>
</plist>"

if [ "$DRY" = "1" ]; then
  echo "  [dry] 写入 $PLIST（$DESC，档位 $TIER）"
else
  printf '%s\n' "$PLIST_BODY" > "$PLIST"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST" || { echo "❌ launchctl bootstrap 失败"; exit 1; }
fi

echo "✅ 完成"
echo "   脚本: $INSTALL_DIR/dsh-purge.sh"
echo "   定时: $DESC（档位 $TIER）"
echo "   日志: $LOG_DIR/dsh-purge.log"
echo
echo "提示: macOS 可能因 TCC 拒绝后台任务访问 ~/Documents，"
echo "      因此脚本被复制到 ~/.dsh/bin 运行，请勿把 plist 指回文档目录。"
