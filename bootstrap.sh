#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  bootstrap.sh — 在一台新机器上装好这套 zsh 环境
#
#  在配置仓库目录里执行：
#     bash bootstrap.sh                 # 装依赖 + 放好配置 + 改登录 shell
#     bash bootstrap.sh --dry-run       # 只打印要做什么，不动系统
#     bash bootstrap.sh --no-pkgs       # 跳过软件包安装
#     bash bootstrap.sh --no-chsh       # 不改登录 shell
#
#  演练/测试用参数：
#     --target-home DIR   目标家目录（默认 $HOME）
#     --os-release FILE   指定 os-release 文件（默认 /etc/os-release）
#     --zsh PATH          用于自检的 zsh（默认自动探测）
#     --repo DIR          配置仓库位置（默认脚本所在目录）
#     --pkg-manager NAME  强制指定包管理器（演练用：apt-get/dnf/pacman/zypper/brew）
# ══════════════════════════════════════════════════════════════════
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
OS_RELEASE="/etc/os-release"
DRY_RUN=0; DO_PKGS=1; DO_CHSH=1
ZSH_BIN=""
PKG_FORCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)     DRY_RUN=1 ;;
    --no-pkgs)     DO_PKGS=0 ;;
    --no-chsh)     DO_CHSH=0 ;;
    --target-home) TARGET_HOME="$2"; shift ;;
    --os-release)  OS_RELEASE="$2";  shift ;;
    --zsh)         ZSH_BIN="$2";     shift ;;
    --pkg-manager) PKG_FORCE="$2";  shift ;;   # 演练用：强制指定包管理器
    --repo)        REPO_DIR="$2";    shift ;;
    -h|--help)     sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（用 --help 看用法）" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1;36m── %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '   [演练] %s\n' "$*"; else "$@"; fi; }

# ── 1. 环境识别 ─────────────────────────────────────────────────
step "1. 环境识别"
OS_ID=""; OS_LIKE=""
if [ -r "$OS_RELEASE" ]; then
  # shellcheck disable=SC1090
  . "$OS_RELEASE" 2>/dev/null || true
  OS_ID="${ID:-}"; OS_LIKE="${ID_LIKE:-}"
fi
say "   系统     : ${PRETTY_NAME:-未知}  (ID=$OS_ID${OS_LIKE:+, LIKE=$OS_LIKE})"
say "   架构     : $(uname -m)  内核 $(uname -s)"
say "   目标家目录: $TARGET_HOME"
say "   配置仓库 : $REPO_DIR"

PKG=""
if [ -n "$PKG_FORCE" ]; then
  PKG="$PKG_FORCE"
else
  for cand in apt-get dnf pacman zypper brew; do
    command -v "$cand" >/dev/null 2>&1 && { PKG="$cand"; break; }
  done
fi
say "   包管理器 : ${PKG:-未识别}"

case "$PKG" in
  apt-get|dnf) PKGS="zsh zsh-syntax-highlighting zsh-autosuggestions fzf zoxide eza bat ripgrep fd-find" ;;
  pacman|zypper|brew) PKGS="zsh zsh-syntax-highlighting zsh-autosuggestions fzf zoxide eza bat ripgrep fd" ;;
  *) PKGS="" ;;
esac
say "   依赖包   : ${PKGS:-（无法确定，请手动安装 zsh / 高亮 / 自动建议 / fzf / zoxide / eza / bat / ripgrep / fd）}"

# ── 2. 软件包 ───────────────────────────────────────────────────
step "2. 软件包"
if [ "$DO_PKGS" = 0 ]; then
  warn "已按 --no-pkgs 跳过"
elif [ -z "$PKG" ] || [ -z "$PKGS" ]; then
  warn "没识别出包管理器，请手动安装上面的依赖包"
else
  case "$PKG" in
    apt-get) run sudo apt-get update; run sudo apt-get install -y $PKGS ;;
    dnf)     run sudo dnf install -y $PKGS ;;
    pacman)  run sudo pacman -S --needed --noconfirm $PKGS ;;
    zypper)  run sudo zypper install -y $PKGS ;;
    brew)    run brew install $PKGS ;;
  esac
fi

# ── 3. starship 可执行文件（放用户目录，不需要 sudo）─────────────
step "3. starship"
SS_BIN="$TARGET_HOME/.local/bin/starship"
run mkdir -p "$TARGET_HOME/.local/bin"
if command -v starship >/dev/null 2>&1; then
  ok "系统里已有: $(command -v starship)"
elif [ -x "$SS_BIN" ]; then
  ok "已在位: $SS_BIN"
elif [ -f "$REPO_DIR/starship" ] || [ -f "$REPO_DIR/starship-bin" ]; then
  ss_src="$REPO_DIR/starship"; [ -f "$ss_src" ] || ss_src="$REPO_DIR/starship-bin"
  run cp "$ss_src" "$SS_BIN"; run chmod +x "$SS_BIN"
  ok "从仓库里的离线副本安装"
else
  case "$(uname -m)-$(uname -s)" in
    x86_64-Linux)   TRIPLE=x86_64-unknown-linux-gnu ;;
    aarch64-Linux)  TRIPLE=aarch64-unknown-linux-musl ;;
    armv7l-Linux)   TRIPLE=armv7-unknown-linux-gnueabihf ;;
    arm64-Darwin)   TRIPLE=aarch64-apple-darwin ;;
    x86_64-Darwin)  TRIPLE=x86_64-apple-darwin ;;
    *)              TRIPLE="" ;;
  esac
  URL="https://github.com/starship/starship/releases/latest/download/starship-${TRIPLE}.tar.gz"
  if [ -n "$TRIPLE" ] && [ "$DRY_RUN" = 0 ]; then
    say "   下载: $URL"
    if curl -fsSL --connect-timeout 10 --max-time 180 -o /tmp/starship.tgz "$URL" 2>/dev/null \
       && tar xzf /tmp/starship.tgz -C "$TARGET_HOME/.local/bin" 2>/dev/null; then
      chmod +x "$SS_BIN"; rm -f /tmp/starship.tgz
      ok "安装完成: $("$SS_BIN" --version 2>/dev/null | head -1)"
    else
      warn "下载失败（网络或代理问题）"
      warn "手动方案：把一份 starship 二进制放到 $SS_BIN 并 chmod +x 即可，配置会自动用上"
    fi
  else
    say "   将尝试下载 $URL 并解到 $TARGET_HOME/.local/bin"
  fi
fi

# ── 4. 放置配置文件 ─────────────────────────────────────────────
step "4. 配置文件"
DEST="$TARGET_HOME/.config/zsh"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ "$DEST" != "$REPO_DIR" ]; then
  if [ -e "$DEST" ]; then
    run mv "$DEST" "$DEST.bak-$STAMP"
    warn "已存在的 $DEST 改名为 $DEST.bak-$STAMP"
  fi
  run mkdir -p "$DEST"
  run cp -a "$REPO_DIR/zshrc" "$REPO_DIR/starship.toml" "$DEST/"
  [ -f "$REPO_DIR/.gitignore" ] && run cp -a "$REPO_DIR/.gitignore" "$DEST/"
  ok "配置已复制到 $DEST"
else
  ok "配置就在目标位置（$DEST）"
fi

LINK="$TARGET_HOME/.zshrc"
if [ -L "$LINK" ]; then
  ok "符号链接已存在: $(readlink "$LINK")"
elif [ -e "$LINK" ]; then
  run mv "$LINK" "$LINK.bak-$STAMP"
  warn "已存在的 ~/.zshrc 改名为 .zshrc.bak-$STAMP"
fi
[ -L "$LINK" ] || run ln -sfn "$DEST/zshrc" "$LINK"
[ -L "$LINK" ] && ok "~/.zshrc → $(readlink "$LINK")"

# ── 5. 让非交互式 shell 也能找到用户目录里的程序 ────────────────
step "5. 非交互式 PATH"
ZSHENV="$TARGET_HOME/.zshenv"
if [ -f "$ZSHENV" ] && grep -q '\.local/bin' "$ZSHENV" 2>/dev/null; then
  ok "~/.zshenv 里已有 ~/.local/bin"
elif [ "$DRY_RUN" = 1 ]; then
  say "   将向 $ZSHENV 追加一行 PATH 设置（让脚本/非交互 shell 也能调用 ~/.local/bin 里的程序）"
else
  # ~/.zshenv 对每次 zsh 启动都生效（含非交互），不像 .zshrc 只在交互时读
  printf '\n# 由 zsh 配置仓库的 bootstrap.sh 添加：让 ~/.local/bin 对所有 zsh 会话可见\nif [ -d "$HOME/.local/bin" ]; then\n  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac\nexport PATH\nfi\n' >> "$ZSHENV"
  ok "已写入 $ZSHENV"
fi

# ── 6. 登录 shell ───────────────────────────────────────────────
step "6. 登录 shell"
ZSH_PATH="${ZSH_BIN:-$(command -v zsh || true)}"
[ -z "$ZSH_PATH" ] && ZSH_PATH="/usr/bin/zsh"
CUR_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || echo 未知)"
say "   当前: $CUR_SHELL"
if [ "$DO_CHSH" = 0 ]; then
  warn "已按 --no-chsh 跳过"
elif [ "$CUR_SHELL" = "$ZSH_PATH" ]; then
  ok "已经是 zsh"
else
  if [ -x "$ZSH_PATH" ]; then
    warn "要改登录 shell 需要你输密码"
    run chsh -s "$ZSH_PATH"
  else
    warn "没找到 zsh 可执行文件，先装 zsh 再执行: chsh -s $ZSH_PATH"
  fi
fi

# ── 7. Nerd Font 检查 ───────────────────────────────────────────
step "7. 字体"
if command -v fc-list >/dev/null 2>&1; then
  if fc-list 2>/dev/null | grep -qi 'nerd font'; then
    ok "系统里有 Nerd Font: $(fc-list 2>/dev/null | grep -i 'nerd font' | head -1 | cut -d: -f2 | sed 's/^ *//')"
  else
    warn "没找到 Nerd Font：语言段图标可能显示成方块。"
    warn "装一个即可（例如 0xProto / JetBrainsMono Nerd Font），并在终端设置里选中它"
  fi
else
  warn "没有 fc-list，无法检查字体"
fi

# ── 8. 自检 ─────────────────────────────────────────────────────
step "8. 自检"
if [ "$DRY_RUN" = 1 ]; then
  say "   演练模式，跳过错实际检查"
elif [ -x "$ZSH_PATH" ]; then
  OUT="$(env HOME="$TARGET_HOME" PATH="$TARGET_HOME/.local/bin:$PATH" "$ZSH_PATH" -i -c '
    print "   zsh        : $ZSH_VERSION"
    print "   compinit   : $(whence -w compinit | cut -d: -f2)"
    print "   补全函数数 : $(print -l ${(k)_comps} 2>/dev/null | wc -l)"
    print "   语法高亮   : ${(j:,:)${(k)ZSH_HIGHLIGHT_HIGHLIGHTERS:-未加载}}"
    print "   自动建议   : $(zle -la 2>/dev/null | grep -qx autosuggest-accept && echo 已就绪 || echo 未加载)"
    print "   fzf 键位   : $(zle -la 2>/dev/null | grep -qx fzf-history-widget && echo 已就绪 || echo 未加载)"
    print "   zoxide     : $(whence -w z 2>/dev/null | cut -d: -f2)"
    print "   starship   : $(command -v starship >/dev/null && starship --version | head -1 || echo 未安装)"
    print "   提示符配置 : $STARSHIP_CONFIG"
  ' 2>/dev/null)"
  echo "$OUT"
  ERR="$(env HOME="$TARGET_HOME" PATH="$TARGET_HOME/.local/bin:$PATH" "$ZSH_PATH" -i -c 'exit' 2>&1)"
  if [ -n "$ERR" ]; then warn "加载时有输出（可能有问题）:"; echo "$ERR" | sed 's/^/     /'; else ok "加载零报错"; fi
  case "$-" in
    *i*) : ;;
    *) warn "非交互环境跑的自检：ZLE 相关项（fzf 键位、自动建议）显示未加载属正常，请开一个真终端再验" ;;
  esac
elif [ "$ZSH_BIN" = "" ]; then
  warn "没找到 zsh，无法自检"
fi

step "完成"
say "   开新终端窗口即可看到新提示符（当前已开的窗口要 exec zsh）。"
say "   回滚：把 ~/.zshrc 指回原来的文件，或 git -C $DEST checkout -- zshrc"
