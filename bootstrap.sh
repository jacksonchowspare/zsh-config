#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  bootstrap.sh — 在一台新机器上装好这套 zsh 环境
#
#  说明：apt 安装时通过环境变量禁用 needrestart 的自动重启，
#        不会因为你装个字体/插件就把 nginx、面板之类的服务重启一遍。
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
#
#  字体相关：
#     --font NAME         要装的 Nerd Font 家族（默认 0xProto；也支持 JetBrainsMono/FiraCode/Hack 等）
#     --no-font           跳过字体安装
#     --font-dir DIR      字体安装目录（默认 ~/.local/share/fonts/<家族>）
#     --set-terminal-font 顺手把 GNOME 系终端（Ptyxis / GNOME Terminal）的字体也设为它
# ══════════════════════════════════════════════════════════════════
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
OS_RELEASE="/etc/os-release"
DRY_RUN=0; DO_PKGS=1; DO_CHSH=1
ZSH_BIN=""
PKG_FORCE=""
DO_FONT=1
FONT_FAMILY="0xProto"
FONT_DIR=""
SET_TERM_FONT=0
FONT_EXPLICIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)     DRY_RUN=1 ;;
    --no-pkgs)     DO_PKGS=0 ;;
    --no-chsh)     DO_CHSH=0 ;;
    --target-home) TARGET_HOME="$2"; shift ;;
    --os-release)  OS_RELEASE="$2";  shift ;;
    --zsh)         ZSH_BIN="$2";     shift ;;
    --pkg-manager) PKG_FORCE="$2";  shift ;;   # 演练用：强制指定包管理器
    --font)        FONT_FAMILY="$2"; FONT_EXPLICIT=1; shift ;;  # 字体家族，对应 Nerd Fonts 发布名：0xProto / JetBrainsMono / FiraCode ...
    --no-font)     DO_FONT=0 ;;
    --font-dir)    FONT_DIR="$2";    shift ;;  # 字体安装目录（默认 ~/.local/share/fonts/<家族>）
    --set-terminal-font) SET_TERM_FONT=1 ;;    # 顺手把 GNOME 系终端的字体也设成它
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

[ -z "$FONT_DIR" ] && FONT_DIR="$TARGET_HOME/.local/share/fonts/$FONT_FAMILY"

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
  apt-get|dnf) PKGS="zsh zsh-syntax-highlighting zsh-autosuggestions fzf zoxide eza bat ripgrep fd-find fontconfig" ;;
  pacman|zypper|brew) PKGS="zsh zsh-syntax-highlighting zsh-autosuggestions fzf zoxide eza bat ripgrep fd" ;;  # 这几个发行版自带 fontconfig
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
  pkg_install() {
    case "$PKG" in
      apt-get) run sudo env NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l apt-get install -y "$@" ;;
      dnf)     run sudo dnf install -y "$@" ;;
      pacman)  run sudo pacman -S --needed --noconfirm "$@" ;;
      zypper)  run sudo zypper install -y "$@" ;;
      brew)    run brew install "$@" ;;
    esac
  }
  PKGS_REQ="zsh zsh-syntax-highlighting zsh-autosuggestions"
  case "$PKG" in
    apt-get|dnf) PKGS_OPT="fzf zoxide eza bat ripgrep fd-find fontconfig" ;;
    *)           PKGS_OPT="fzf zoxide eza bat ripgrep fd fontconfig" ;;
  esac
  if [ "$PKG" = "apt-get" ] && command -v apt-cache >/dev/null 2>&1; then
    _avail=""; _missing=""
    for _p in $PKGS_OPT; do
      if apt-cache show "$_p" >/dev/null 2>&1; then _avail="$_avail $_p"; else _missing="$_missing $_p"; fi
    done
    [ -n "$_missing" ] && warn "仓库里没有这些包，已从清单剔除:$_missing"
    PKGS_OPT="$_avail"
    case " $PKGS_OPT " in
      *" eza "*) : ;;
      *) if apt-cache show exa >/dev/null 2>&1; then
           say "   用 exa 代替 eza（配置里已内置 exa 回退，现代版 ls 照常可用）"
           PKGS_OPT="$PKGS_OPT exa"
         fi ;;
    esac
  fi
  case "$PKG" in apt-get) run sudo env NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l apt-get update ;; esac
  say "   必需: $PKGS_REQ"
  pkg_install $PKGS_REQ || warn "必需包没装上，请手动安装 zsh 与两个插件包"
  say "   可选: $PKGS_OPT"
  if ! pkg_install $PKGS_OPT; then
    warn "整批可选包安装失败（多半是某些包在这个发行版上不存在），改为逐个安装、缺哪个跳哪个"
    for _p in $PKGS_OPT; do
      pkg_install "$_p" >/dev/null 2>&1 || warn "$_p 在这个发行版上装不上，跳过（不影响其它功能）"
    done
  fi
  if ! command -v eza >/dev/null 2>&1; then
    if command -v exa >/dev/null 2>&1; then
      ok "用 exa 代替 eza，现代版 ls/ll/la/lt 照常可用"
    else
      warn "既没有 eza 也没有 exa：ls 走系统原生版本，其它功能不受影响"
      case "$PKG" in apt-get) say "   想补上: sudo apt install -y exa" ;; esac
    fi
  fi
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
step "7. 字体（Nerd Font）"
FCLIST_OK=1
command -v fc-list >/dev/null 2>&1 || FCLIST_OK=0
[ "${BOOTSTRAP_FORCE_NO_FCLIST:-0}" = "1" ] && FCLIST_OK=0     # 演练用：强制走"没有 fc-list"分支
NERD_OK=0
if [ "$FCLIST_OK" = 1 ]; then
  if fc-list 2>/dev/null | grep -qi "nerd font"; then
    NERD_OK=1
    ok "已有 Nerd Font: $(fc-list 2>/dev/null | grep -i "nerd font" | head -1 | cut -d: -f2 | sed "s/^ *//")"
  else
    warn "系统里没有任何 Nerd Font 字体"
  fi
else
  warn "没有 fc-list（fontconfig 未装），无法探测字体"
fi

# 判断本机有没有桌面环境：决定要不要在这台机器上装字体。
# 注意不能只看 DISPLAY/WAYLAND_DISPLAY —— 人在 ssh 里跑时它们是空的，
# 但机器可能正是桌面机本身，所以再查一次图形会话。
HEADLESS=1
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  HEADLESS=0
elif [ -S "/run/user/$(id -u)/wayland-0" ]; then
  HEADLESS=0
elif command -v loginctl >/dev/null 2>&1; then
  for _s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    case "$(loginctl show-session "$_s" -p Type --value 2>/dev/null)" in
      wayland|x11) HEADLESS=0; break ;;
    esac
  done
fi
[ "${BOOTSTRAP_DEBUG:-0}" = "1" ] && echo "   [调试] 桌面环境判定: $([ "$HEADLESS" = 1 ] && echo headless\(无桌面\) || echo desktop\(有桌面\))"

FAMILY_OK=0
if [ "$FCLIST_OK" = 1 ] && fc-list 2>/dev/null | grep -qi "$FONT_FAMILY"; then FAMILY_OK=1; fi

if [ "$NERD_OK" = 0 ] || { [ "$FONT_EXPLICIT" = 1 ] && [ "$FAMILY_OK" = 0 ]; }; then
  if [ "$DO_FONT" = 0 ]; then
    warn "已按 --no-font 跳过；缺 Nerd Font 时语言段图标会显示成方块"
  elif [ "$HEADLESS" = 1 ] && [ "$FONT_EXPLICIT" = 0 ]; then
    warn "无桌面环境（headless）：字符是在你本地终端/SSH 客户端里渲染的，字体装在服务器上不起作用 → 跳过安装"
    say "   正确做法：把 Nerd Font 装在【你用的那台客户端设备】上，并在客户端设置里选中它"
    say "   确实需要在服务器上装（有 GUI 或另有用途）：加参数 --font $FONT_FAMILY"
  elif [ "$DRY_RUN" = 1 ]; then
    say "   将下载 $FONT_FAMILY（Nerd Fonts 官方发布）装到 $FONT_DIR，然后 fc-cache -f"
  else
    [ "$NERD_OK" = 1 ] && say "   系统已有其它 Nerd Font，但你要的是 $FONT_FAMILY，按你的要求安装"
    TMPZ="/tmp/nerdfont-$$.zip"
    URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$FONT_FAMILY.zip"
    say "   下载 $URL"
    if curl -fsSL --connect-timeout 10 --max-time 300 -o "$TMPZ" "$URL" 2>/dev/null && [ -s "$TMPZ" ]; then
      ok "下载完成: $(du -h "$TMPZ" | cut -f1)"
      mkdir -p "$FONT_DIR"
      UNPACKED=0
      if command -v unzip >/dev/null 2>&1; then
        unzip -oq "$TMPZ" -d "$FONT_DIR" && UNPACKED=1
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMPZ" "$FONT_DIR" && UNPACKED=1
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$TMPZ" -C "$FONT_DIR" && UNPACKED=1
      fi
      rm -f "$TMPZ"
      if [ "$UNPACKED" = 1 ]; then
        ok "字体已装到 $FONT_DIR（OFL 许可证文件随字体一起保留）"
        if command -v fc-cache >/dev/null 2>&1; then
          fc-cache -f >/dev/null 2>&1 && ok "字体缓存已重建"
        else
          warn "没有 fc-cache（fontconfig 未装）：新字体要等重新登录或重启桌面才被系统认到"
          warn "想立刻生效: sudo apt install -y fontconfig && fc-cache -f，然后重跑本脚本即可看到识别结果"
        fi
        if [ "$FCLIST_OK" = 1 ] && fc-list 2>/dev/null | grep -qi "$FONT_FAMILY"; then
          ok "系统已识别: $(fc-list 2>/dev/null | grep -i "$FONT_FAMILY" | head -1 | cut -d: -f2 | sed "s/^ *//")"
        fi
      else
        warn "没有可用的解压工具（unzip / python3 / bsdtar 都没有）"
        warn "手动方案: sudo apt install unzip 后重跑本脚本"
      fi
    else
      warn "下载失败（网络或代理问题）"
      warn "手动方案: 打开 $URL 下载解压，把 ttf 放进 $FONT_DIR，再执行 fc-cache -f"
    fi
  fi
fi

# 字体装上了不等于终端在用 —— 顺手看一眼 GNOME 系终端的设置
if command -v dconf >/dev/null 2>&1; then
  PTY_FONT="$(dconf read /org/gnome/Ptyxis/font-name 2>/dev/null | tr -d "'")"
  if [ -n "$PTY_FONT" ]; then
    say "   终端（Ptyxis）当前字体: $PTY_FONT"
    case "$PTY_FONT" in
      *[Nn]erd*) ok "   → 已经是 Nerd Font，图标能正常显示" ;;
      *) warn "   → 不是 Nerd Font，图标会变方块"
         if [ "$SET_TERM_FONT" = 1 ] && [ "$DRY_RUN" = 0 ]; then
           dconf write /org/gnome/Ptyxis/font-name "'$FONT_FAMILY Nerd Font Mono 14'" 2>/dev/null \
             && ok "   已设为 $FONT_FAMILY Nerd Font Mono 14（新开窗口生效）" \
             || warn "   设置失败，请手动在终端设置里选字体"
         else
           say "   改法: dconf write /org/gnome/Ptyxis/font-name \"'$FONT_FAMILY Nerd Font Mono 14'\""
           say "   或加参数 --set-terminal-font 让脚本替你改"
         fi ;;
    esac
  fi
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
  if [ ! -t 0 ]; then
    warn "这次自检的 stdin 不是终端：ZLE 相关项若显示未加载属正常，请在真终端里再验一次"
  elif ! echo "$OUT" | grep -q "已就绪"; then
    warn "在真终端里跑的，但 ZLE 相关项没就绪 —— 检查 zsh-syntax-highlighting / zsh-autosuggestions 是否装上"
  fi
elif [ "$ZSH_BIN" = "" ]; then
  warn "没找到 zsh，无法自检"
fi

step "完成"
say "   开新终端窗口即可看到新提示符（当前已开的窗口要 exec zsh）。"
say "   回滚：把 ~/.zshrc 指回原来的文件，或 git -C $DEST checkout -- zshrc"
