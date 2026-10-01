# ══════════════════════════════════════════════════════════════════
#  ~/.zshrc — 精简自持版（不依赖 oh-my-zsh 之类的框架）
#
#  真身位置: ~/.config/zsh/zshrc    （~/.zshrc 是指向它的符号链接）
#  版本管理: 同目录是 git 仓库；local.zsh 不进版本库
#
#  必需（都是 apt 官方包）: zsh, zsh-syntax-highlighting, zsh-autosuggestions
#  可选（缺了只提示一行、不影响启动）: fzf, zoxide, eza, batcat
#  提示符: starship（可选；配置是本目录的 starship.toml，缺了会自动退回内置提示符）
#  设计原则: 启动不联网; 任何可选组件缺失都降级运行而不是报错
# ══════════════════════════════════════════════════════════════════

# ── 0. 非交互场景（脚本 / scp / 编辑器调用）直接返回 ─────────────
[[ -o interactive ]] || return

# ── 1. 环境变量与 PATH ──────────────────────────────────────────
typeset -U path PATH           # PATH 自动去重，避免反复追加出现重复项
path=("$HOME/.local/bin" "$HOME/bin" $path)

export EDITOR=vim
export VISUAL=$EDITOR
export PAGER=less
export LESS='-R -F -X -i -M'

# ── 2. 历史记录（全新开始，从零积累）─────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=$HOME/.zsh_history
setopt HIST_IGNORE_ALL_DUPS    # 重复命令只留一条
setopt HIST_REDUCE_BLANKS      # 去掉多余空白
setopt HIST_VERIFY             # 历史展开先显示、不直接执行
setopt SHARE_HISTORY           # 多个终端共享历史
setopt INC_APPEND_HISTORY      # 立即落盘，异常退出也不丢

# ── 3. 交互选项 ─────────────────────────────────────────────────
setopt AUTO_CD                 # 直接输入目录名等于 cd 进去
setopt AUTO_PUSHD              # cd 自动压栈，cd - 来回切
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS    # 交互模式允许行内 # 注释
setopt EXTENDED_GLOB
unsetopt BEEP                  # 关掉蜂鸣

# ── 4. 工具函数 ─────────────────────────────────────────────────
# 插件加载器：可给多个候选路径，命中一个即用；全找不到只提示一行，不中断启动
_zsh_load() {
  local label=$1; shift
  local f
  for f in "$@"; do
    [[ -r $f ]] && { source "$f"; return 0; }
  done
  print -u2 "⚠ 未找到 $label（可执行 sudo apt install $label 补上）"
  return 1
}
mkcd() { [[ -n $1 ]] || { print -u2 "用法: mkcd <目录>"; return 1; }; mkdir -p "$1" && cd "$1"; }
ports() { ss -tulnp; }
bigfiles() { find . -type f -size +100M -exec ls -lh {} +; }

# ── 5. 补全系统（zsh 自带，不需要装任何东西）────────────────────
autoload -Uz compinit
_zdump=${ZDOTDIR:-$HOME}/.zcompdump
if [[ -s $_zdump && -n $_zdump(#qN.mh-24) ]]; then
  compinit -C                  # 24 小时内的缓存直接用，跳过安全检查（快）
else
  compinit                     # 过期或不存在则重建
fi
zstyle ':completion:*' menu select                              # Tab 出菜单，方向键选
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'      # 补全大小写不敏感
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache
[[ -n $LS_COLORS ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# ── 6. fzf（Ctrl+R 历史搜索 / Ctrl+T 文件搜索 / Alt+C 目录跳转）─
FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*"'
FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border --info=inline'
FZF_CTRL_T_OPTS='--preview "batcat --style=numbers --color=always --line-range=:200 {}"'
if command -v fzf >/dev/null && [[ -t 0 ]]; then
  # [[ -t 0 ]]：只在真终端里装键位。非 tty 的交互式调用下，Debian 版 fzf 脚本
  # 会用 eval 恢复选项并试图打开 zle 选项，报 "can't change option: zle"，纯噪音。
  for _f in /usr/share/doc/fzf/examples/key-bindings.zsh /usr/share/fzf/key-bindings.zsh; do
    [[ -r $_f ]] && { source "$_f"; break; }
  done
  for _f in /usr/share/doc/fzf/examples/completion.zsh /usr/share/fzf/completion.zsh; do
    [[ -r $_f ]] && { source "$_f"; break; }
  done
  unset _f
fi

# ── 7. zoxide（z 关键词跳目录 / zi 交互式选择）──────────────────
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# ── 8. 自动建议（边打字边出现的灰色历史提示）────────────────────
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c6c6c'   # 暗色主题下的灰；浅色主题可改 darkgray
ZSH_AUTOSUGGEST_USE_ASYNC=1
_zsh_load zsh-autosuggestions /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey '^ ' autosuggest-accept                 # Ctrl+空格 采纳建议（右方向键也行）

# ── 9. 别名 ─────────────────────────────────────────────────────
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first'
  alias ll='eza -lh --group-directories-first --git'
  alias la='eza -lah --group-directories-first --git'
  alias lt='eza --tree --level=2 --group-directories-first'
fi
command -v batcat >/dev/null && alias cat='batcat --style=plain --paging=never'
command -v fdfind >/dev/null && alias fd='fdfind'
alias df='df -h'
alias du='du -h'
alias ..='cd ..'
alias ...='cd ../..'
alias reload='source ~/.zshrc'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'

# ── 10. 语法高亮（必须放在最后：它要包装所有 ZLE 小部件）────────
_zsh_load zsh-syntax-highlighting /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── 11. 提示符 ──────────────────────────────────────────────────
# 优先用 starship（配置放在本仓库里：~/.config/zsh/starship.toml）；
# 没有 starship 可执行文件时，自动退回下面的内置提示符，不至于没提示符可用。
_prompt_plain() {
  PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%(?.. %F{red}✘%?%f) $ '
}

if [[ -r ${ZDOTDIR:-$HOME}/.config/zsh/starship.toml ]]; then
  export STARSHIP_CONFIG=${ZDOTDIR:-$HOME}/.config/zsh/starship.toml
fi

if command -v starship >/dev/null 2>&1; then
  source <(starship init zsh)
  # 保险丝：starship 二进制若在会话中途消失（被删/不可执行），
  # 自动摘掉它的钩子并退回内置提示符，避免"提示符画不出来、终端看着像冻死"
  _starship_fuse() {
    if [[ ! -x ${commands[starship]:-} ]]; then
      add-zsh-hook -d precmd prompt_starship_precmd 2>/dev/null
      add-zsh-hook -d precmd starship_precmd 2>/dev/null
      add-zsh-hook -d preexec prompt_starship_preexec 2>/dev/null
      precmd_functions=(${precmd_functions:#_starship_fuse})
      RPROMPT=''
      _prompt_plain
      unset -f _starship_fuse
    fi
  }
  autoload -Uz add-zsh-hook
  precmd_functions=(_starship_fuse $precmd_functions)   # 排在 starship 的钩子之前检查
else
  _prompt_plain
fi

# ── 12. 本机私有配置（不进 git，放临时 export / 内网别名）───────
[[ -r ${ZDOTDIR:-$HOME}/.config/zsh/local.zsh ]] && source ${ZDOTDIR:-$HOME}/.config/zsh/local.zsh
