# zsh-config

一个精简自持的 zsh 环境：**不用 oh-my-zsh**，用 apt 官方插件包 + starship 做出干净、可版本管理、可一键搬家的命令行配置。

## 包含什么

| 文件 | 作用 |
|---|---|
| `zshrc` | 唯一配置文件（约 180 行，按段落注释，从头读到尾能看懂） |
| `starship.toml` | 提示符：方括号分段风格 + `»` 点线连接 + 右侧日期时间到秒 + 语言版本段 |
| `bootstrap.sh` | 新机器一键部署：识别发行版、装依赖、放二进制、改登录 shell、自检 |
| `.gitignore` | 排除 `local.zsh`（本机私有配置）与运行时产物 |

`zshrc` 里有什么：

- **补全**：zsh 自带补全系统（`compinit`）+ 菜单选择 + 大小写不敏感 + 彩色补全列表，不需要装任何东西
- **语法高亮 / 自动建议**：用 apt 官方包 `zsh-syntax-highlighting`、`zsh-autosuggestions`（升级随系统，不用手抄副本）
- **fzf**：`Ctrl+R` 历史搜索 / `Ctrl+T` 文件搜索 / `Alt+C` 目录跳转
- **zoxide**：`z 关键词` 跳目录，`zi` 交互选择
- **别名**：`ls/ll/la/lt`（eza）、`cat`（batcat）、`..`/`...`、git 快捷、`mkcd`/`ports`/`bigfiles`
- **提示符**：优先用 starship；没有 starship 时自动退回内置提示符
- **保险丝**：starship 二进制若在会话中途消失，自动摘掉它的钩子退回内置提示符，**不会出现"提示符画不出来、终端像死掉"**
- **跨发行版**：插件路径覆盖 Debian/Ubuntu、Arch、Fedora、macOS(Homebrew)，命中不了还会在常见前缀浅搜兜底

## 快速开始

```bash
git clone https://github.com/jacksonchowspare/zsh-config.git ~/.config/zsh
cd ~/.config/zsh && bash bootstrap.sh
```

`bootstrap.sh` 会依次：识别系统与包管理器 → 安装依赖 → 把 starship 二进制放进 `~/.local/bin` → 建立 `~/.zshrc` 符号链接（旧文件带时间戳改名）→ 写入 `~/.zshenv`（让非交互式 shell 也能找到 `~/.local/bin`）→ 改登录 shell → 打印自检结果。

先看它打算做什么、不实际改动：

```bash
bash bootstrap.sh --dry-run
```

其他开关：`--no-pkgs`（跳过装包）、`--no-chsh`（不改登录 shell）、`--target-home DIR`（装到别处，演练用）、`--os-release FILE` / `--pkg-manager NAME`（模拟其它发行版）。

## 依赖

必需（Debian/Ubuntu 包名）：`zsh` `zsh-syntax-highlighting` `zsh-autosuggestions`
推荐：`fzf` `zoxide` `eza` `bat`（命令叫 `batcat`）`ripgrep` `fd-find`（命令叫 `fdfind`）
字体：任意 Nerd Font（语言段的图标需要，例如 0xProto / JetBrainsMono Nerd Font）

Arch/Fedora 上 `fd-find` 叫 `fd`；macOS 用 Homebrew，包名同样去掉 `-find`。缺哪个都不会让配置崩掉，只会少一项功能并给出提示。

## 手动安装（不想用脚本）

```bash
sudo apt install -y zsh zsh-syntax-highlighting zsh-autosuggestions fzf zoxide eza bat ripgrep fd-find
mkdir -p ~/.local/bin && cp starship ~/.local/bin/ && chmod +x ~/.local/bin/starship
ln -sfn ~/.config/zsh/zshrc ~/.zshrc
chsh -s /usr/bin/zsh
```

## 自定义

- **点线符号**：`starship.toml` 里 `[fill]` 的 `symbol`（默认 `»`，可换成 `.` `·` `─` `•` `⣿` `◆` 等任意字符串）
- **点线颜色**：同段落的 `style`。注意 starship 的默认值是 `bold black`，比终端背景还暗，本项目改成了 `dimmed white`
- **时间格式**：`[time]` 的 `time_format`，例如 `%Y-%m-%d %H:%M:%S` 带年份
- **提速**：把顶层 `format` 里的 `$git_status` 去掉，大仓库里每次回车可省约 45ms（分支名仍保留）
- **本机私有内容**：新建 `~/.config/zsh/local.zsh`，已被 `.gitignore` 排除，且会被自动加载
- **改完提交**：`cd ~/.config/zsh && git commit -am "说明"`；想回滚就 `git revert <提交>`

## 实测数据（Ubuntu 26.04，13,534 文件的大仓库）

- shell 启动：约 0.05 秒
- 提示符生成：非 git 目录 9ms；大仓库 55ms（其中 `git status` 占 35ms）
- 加载报错：0

## 许可

未声明许可。想开源就自己加一个（例如 MIT），或者保留默认的"保留所有权利"。
