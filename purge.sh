#!/usr/bin/env bash
# dsh-purge — macOS 磁盘分级清理工具
# 项目主页: https://github.com/<you>/dsh-purge
# 许可证: MIT
set -u

VERSION="1.0.0"

DRY=1
TIERS=""
MANIFEST=""
LOGFILE=""
FREED_KB=0
FAILED=0

usage() {
  cat <<'EOF'
dsh-purge — macOS 磁盘分级清理

用法:
  purge.sh [选项]

选项:
  --dry-run           只统计不删除（默认行为）
  --yes               真正执行删除
  --tier <组合>        选择档位，可组合: a, b, c, ab, abc（默认 ab）
  --manifest d        列出 D 档（个人数据）清单，永不删除
  --log <文件>         同时写入日志文件
  --version           显示版本
  -h, --help          显示帮助

档位说明:
  A  可再生缓存     ~/.npm ~/.cache/uv ~/Library/Caches ~/Library/Developer ...  零风险
  B  日志           WorkBuddy / CodeBuddy 等应用日志                            零风险
  C  模型权重       ~/.ollama ~/.cache/huggingface ~/.cache/models ...          删了需重下
  D  个人数据       项目 / 聊天记录 / 容器数据                                  永不删除

示例:
  purge.sh                            # 看看能清多少
  purge.sh --tier ab --yes            # 清缓存 + 日志
  purge.sh --tier c --yes --log /tmp/purge.log

注意: 沙箱环境下（如 DSH / Codex）删除用户目录外文件需要更高权限。
EOF
}

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes)     DRY=0 ;;
    --tier)    TIERS="${2:-}"; shift ;;
    --manifest) MANIFEST="${2:-}"; shift ;;
    --log)     LOGFILE="${2:-}"; shift ;;
    --version) echo "dsh-purge $VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# 未指定档位时默认 ab
[ -z "$TIERS" ] && [ -z "$MANIFEST" ] && TIERS="ab"

# ---------- 日志 ----------
if [ -n "$LOGFILE" ]; then
  mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
  exec > >(tee -a "$LOGFILE") 2>&1
fi

say() { printf '%s\n' "$*"; }

echo "===== dsh-purge $VERSION $(date '+%Y-%m-%d %H:%M:%S') tier=${TIERS:-none} dry=${DRY} ====="

size_kb() {
  du -sk "$1" 2>/dev/null | awk '{print $1}'
}
human() {
  awk -v k="$1" 'BEGIN{
    if (k>1048576) printf "%.1fG", k/1048576;
    else if (k>1024) printf "%.0fM", k/1024;
    else printf "%dK", k;
  }'
}

# 安全护栏：绝不接受根目录 / 家目录本身
guard() {
  case "$1" in
    "/"|"$HOME"|"$HOME/"|"") say "   [拒绝] 危险路径: $1"; return 1 ;;
  esac
  return 0
}

rem() {
  local path="$1"
  [ -e "$path" ] || return 0
  guard "$path" || { FAILED=$((FAILED+1)); return 0; }
  local kb
  kb=$(size_kb "$path")
  [ -z "$kb" ] && kb=0
  if [ "$DRY" = "1" ]; then
    printf '  [统计] %6s  %s\n' "$(human "$kb")" "$path"
  elif rm -rf "$path" 2>/dev/null; then
    FREED_KB=$((FREED_KB + kb))
    printf '  [已删] %6s  %s\n' "$(human "$kb")" "$path"
  else
    FAILED=$((FAILED+1))
    printf '  [失败] %6s  %s\n' "$(human "$kb")" "$path"
  fi
}

# ---------- 各档 ----------
tier_a() {
  echo "== A 档：可再生缓存 =="
  rem "$HOME/.npm/_cacache"
  rem "$HOME/.npm/_npx"
  rem "$HOME/.cache/uv"
  rem "$HOME/.cache/rod"
  rem "$HOME/.cache/selenium"
  rem "$HOME/.yarn/berry/cache"
  rem "$HOME/.bun/install/cache"
  rem "$HOME/Library/Developer/CoreSimulator"
  rem "$HOME/Library/Developer/Xcode/DerivedData"
  rem "$HOME/Library/Developer/Xcode/Archives"
  if [ -d "$HOME/Library/Caches" ]; then
    if [ "$DRY" = "1" ]; then
      local k
      k=$(size_kb "$HOME/Library/Caches")
      printf '  [统计] %6s  %s (整体)\n' "$(human "${k:-0}")" "$HOME/Library/Caches"
    else
      for d in "$HOME"/Library/Caches/*; do
        [ -e "$d" ] || continue
        rem "$d"
      done
    fi
  fi
  if [ -d "$HOME/Library/pnpm/store" ]; then
    if [ "$DRY" = "1" ]; then
      local k
      k=$(size_kb "$HOME/Library/pnpm/store")
      printf '  [统计] %6s  %s\n' "$(human "${k:-0}")" "$HOME/Library/pnpm/store"
    elif command -v pnpm >/dev/null 2>&1; then
      pnpm store prune >/dev/null 2>&1 && say "  [已清]  $HOME/Library/pnpm/store (pnpm store prune)"
    else
      rem "$HOME/Library/pnpm/store"
    fi
  fi
}

tier_b() {
  echo "== B 档：日志 =="
  rem "$HOME/Library/Application Support/WorkBuddyExtension/Logs"
  rem "$HOME/Library/Application Support/WorkBuddy/logs"
  rem "$HOME/Library/Application Support/CodeBuddyExtension/Logs"
  rem "$HOME/.workbuddy/logs"
  rem "$HOME/Library/Logs"
  rem "$HOME/.npm/_logs"
}

tier_c() {
  echo "== C 档：模型权重（删了需重新下载）=="
  rem "$HOME/.ollama/models"
  rem "$HOME/.cache/models"
  rem "$HOME/.cache/huggingface"
  rem "$HOME/.cache/modelscope"
  rem "$HOME/models/small.pt"
  if [ -d "$HOME/.cache/whisper" ]; then
    for f in "$HOME"/.cache/whisper/*; do
      [ -e "$f" ] || continue
      case "$f" in
        */medium.pt) say "  [保留] $(human "$(size_kb "$f")")  $f"; continue ;;
      esac
      rem "$f"
    done
  fi
}

manifest_d() {
  echo "== D 档：个人数据（本工具永不删除，仅供人工确认）=="
  for p in \
    "$HOME/.workbuddy/projects" \
    "$HOME/.workbuddy/blobs" \
    "$HOME/.workbuddy/workspace" \
    "$HOME/.workbuddy/binaries" \
    "$HOME/.workbuddy/backup" \
    "$HOME/.workbuddy/file-history" \
    "$HOME/WorkBuddy" \
    "$HOME/Library/Containers" \
    "$HOME/Library/Application Support/WorkBuddyExtension/Data" \
    "$HOME/Library/Application Support/WorkBuddy/WebStorage" \
    "$HOME/Library/Application Support/WorkBuddy/CachedData" \
    "$HOME/Library/Python" \
    "$HOME/Library/Nemu/vms" ; do
    [ -e "$p" ] || continue
    printf '  %6s  %s\n' "$(human "$(size_kb "$p")")" "$p"
  done
}

# ---------- 执行 ----------
case "$TIERS" in *a*) tier_a ;; esac
case "$TIERS" in *b*) tier_b ;; esac
case "$TIERS" in *c*) tier_c ;; esac
[ "$MANIFEST" = "d" ] && manifest_d

echo
if [ "$DRY" = "1" ]; then
  say "（统计模式，未删除任何文件。确认后加 --yes 执行。）"
else
  say "本次释放约 $(human "$FREED_KB")，失败项 $FAILED（多为文件占用，可忽略）"
  av=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
  [ -n "${av:-}" ] && say "当前可用: $(human "$av")"
fi
