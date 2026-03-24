# nai Phase 2 設計: Smart Context & Shell Integration

## Goal

naiのコマンド生成品質を向上させ、ターミナルにネイティブ統合する。
F1〜F4の4機能を順に実装する。

---

## F1: Tool Registration + OS検出強化

### 目的

LLMに「このシステムで実際に使えるコマンド」を教え、プラットフォーム固有の正しいコマンドを生成させる。

### 検出対象

**OSコア差分（自動検出）:**

| カテゴリ | macOS (BSD) | Linux (GNU) |
|---|---|---|
| find | BSD: `-f path` サポート | GNU: `-f` なし |
| sed | `-i ''` (空文字必須) | `-i` (引数なし) |
| clipboard | `pbcopy` / `pbpaste` | `xclip` / `xsel` / `wl-copy` |
| open | `open` | `xdg-open` |
| pkg manager | `brew` | `apt` / `dnf` / `pacman` / `apk` |
| date | BSD date | GNU date |
| stat | BSD stat (`-f`) | GNU stat (`-c`) |

**ユーザーツール（`which` チェック）:**

```
jq, yq, ripgrep (rg), fd, bat, eza, delta,
docker, kubectl, terraform,
git, gh, curl, wget, python3, node, deno, bun
```

### 実装設計

```
src/lib/env.mbt        — Environment型定義 + 検出ロジック（pure部分）
src/lib/env_test.mbt   — テスト
src/main/main.mbt      — async fn detect_env() で which チェック実行
```

**Environment型:**

```moonbit
pub struct Environment {
  os : String           // "macOS 15.2" / "Ubuntu 24.04"
  shell : String        // "zsh" / "bash" / "fish"
  cwd : String
  platform : String     // "macos" / "linux"
  pkg_manager : String  // "brew" / "apt" / "dnf" / ""
  clipboard : String    // "pbcopy" / "xclip" / ""
  find_variant : String // "bsd" / "gnu"
  sed_variant : String  // "bsd" / "gnu"
  available_tools : Array[String]  // ["jq", "rg", "fd", "docker", ...]
}
```

**プロンプトへの反映:**

```
Environment:
- OS: macOS 15.2, Shell: zsh
- Platform tools: BSD find (supports -f), BSD sed (requires -i '')
- Clipboard: pbcopy/pbpaste
- Package manager: brew
- Available: jq, rg, fd, docker, gh, python3, node
- Not available: kubectl, terraform

Use available tools when they are better suited.
For example, prefer 'rg' over 'grep' if available, 'fd' over 'find' if available.
```

### パフォーマンス考慮

`which` を20-30個実行するコスト。2つのアプローチ:

- **A. 逐次実行**: 各ツールに `@process.collect_output_merged("which", ["jq"])` → 単純だが起動時間に20-30のプロセス生成
- **B. 一括チェック**: `which jq rg fd docker 2>/dev/null` のようにまとめて実行 → 1プロセスで済む

**採用: B** — `sh -c "which jq rg fd ... 2>/dev/null"` は存在するコマンドのパスだけ出力する。1回のプロセス起動で全チェック完了。

ただし `which` の挙動はシェル依存（bashビルトイン vs `/usr/bin/which`）。`command -v` の方がPOSIX準拠で信頼性が高い:

```sh
for cmd in jq rg fd docker; do command -v "$cmd" >/dev/null 2>&1 && echo "$cmd"; done
```

これを1回の `sh -c` で実行する。

---

## F2: Shell History コンテキスト

### 目的

直近のコマンド履歴をLLMに渡し、「さっきの続き」を理解させる。

### 履歴ファイルの検出

| シェル | 履歴ファイル | フォーマット |
|---|---|---|
| zsh | `$HISTFILE` or `~/.zsh_history` | `: timestamp:0;command` |
| bash | `$HISTFILE` or `~/.bash_history` | `command` (1行1コマンド) |
| fish | `~/.local/share/fish/fish_history` | `- cmd: command` (YAML風) |

### 実装設計

```
src/lib/history.mbt       — 履歴パースロジック（pure）
src/lib/history_test.mbt  — テスト
```

**インターフェース:**

```moonbit
pub fn parse_zsh_history(content : String, depth~ : Int) -> Array[String]
pub fn parse_bash_history(content : String, depth~ : Int) -> Array[String]
pub fn parse_fish_history(content : String, depth~ : Int) -> Array[String]

// メインから呼ぶ: シェル種別に応じてパーサーを選択
pub fn get_history_path(shell : String) -> String
pub fn detect_history_parser(shell : String) -> String  // "zsh" / "bash" / "fish"
```

**プロンプトへの反映:**

```
Recent commands (most recent first):
1. grep -r "TODO" src/
2. git status
3. cd ~/repos/project
4. docker ps

Consider this context when generating commands.
The user may be continuing a workflow.
```

### 設定

- デフォルト: 10件
- `--history-depth N` フラグで調整
- `--no-history` で無効化
- 設定ファイル（F4）の `history_depth` でデフォルト変更可能

### プライバシー

履歴にはパスワードやトークンが含まれる可能性がある。フィルタリング:

- `export`, `env`, `API_KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `PASS=` を含む行をスキップ
- `curl -H "Authorization` を含む行をスキップ

---

## F3: Shell Integration (Cmd+L)

### 目的

ターミナルでCmd+Lを押すと、インラインプロンプトが表示され、自然言語入力→生成コマンドがコマンドラインに挿入される。

### 体験フロー

```
$ ls -la src/        ← 通常のターミナル作業
                     ← Cmd+L を押す
nai> _               ← プロンプトが表示される
nai> find all rust files modified this week
                     ← Enter を押す
$ find . -name "*.rs" -mtime -7    ← 生成コマンドが挿入される（未実行）
                                    ← ユーザーが確認・編集してEnterで実行
```

### 実装: Zsh Widget

```zsh
# ~/.config/nai/nai.zsh (ソースされるファイル)

_nai_widget() {
  local query
  # ミニプロンプトを表示して入力を受け取る
  zle -I
  printf '\nnai> '
  read -r query
  if [[ -n "$query" ]]; then
    local result
    result=$(nai "$query" 2>/dev/null)
    if [[ -n "$result" ]]; then
      # 生成コマンドをコマンドラインバッファに挿入
      BUFFER="$result"
      CURSOR=${#BUFFER}
    fi
  fi
  zle redisplay
}

zle -N _nai_widget
bindkey '\x0c' _nai_widget  # Cmd+L (実際はCtrl+L相当)
```

**注意**: macOSのターミナルでは Cmd+L はターミナルアプリのショートカットに割り当てられている場合がある。実際のキーバインドは:
- **Ctrl+L**: 最も一般的（ターミナルクリアと競合するが上書き可能）
- **Ctrl+N**: 代替候補
- ユーザー設定可能にする

### Bash対応

```bash
# ~/.config/nai/nai.bash

_nai_widget() {
  local query
  printf '\nnai> '
  read -r query
  if [[ -n "$query" ]]; then
    local result
    result=$(nai "$query" 2>/dev/null)
    if [[ -n "$result" ]]; then
      READLINE_LINE="$result"
      READLINE_POINT=${#READLINE_LINE}
    fi
  fi
}

bind -x '"\C-l": _nai_widget'
```

### Fish対応

```fish
# ~/.config/nai/nai.fish

function _nai_widget
  set -l query (read -P "nai> ")
  if test -n "$query"
    set -l result (nai "$query" 2>/dev/null)
    if test -n "$result"
      commandline -r $result
      commandline -f repaint
    end
  end
end

bind \cl _nai_widget
```

### インストーラー

`nai --init <shell>` コマンドで自動セットアップ:

```sh
nai --init zsh    # → ~/.config/nai/nai.zsh を生成
                  #    ~/.zshrc に source 行を追記するか確認
nai --init bash   # → ~/.config/nai/nai.bash を生成
nai --init fish   # → ~/.config/nai/nai.fish を生成
```

**nai本体（MoonBit）での実装:**
- `--init` フラグを受け取り、シェルスクリプトをstdoutに出力
- ファイル保存と`.zshrc`への追記はシェルスクリプト側で行う（MoonBitからファイル書き込み）

---

## F4: 設定ファイル

### 目的

プロバイダー設定やhistory_depthなどのユーザー設定を永続化する。

### ファイルパス

`~/.config/nai/config.json`

### スキーマ

```json
{
  "default_provider": "ollama",
  "history_depth": 10,
  "keybind": "\\C-l",
  "ollama": {
    "base_url": "http://localhost:11434/v1",
    "model": "qwen2.5-coder:7b"
  },
  "openai": {
    "model": "gpt-4.1-nano"
  },
  "claude": {
    "model": "claude-haiku-4-5-20251001"
  }
}
```

### 実装設計

```
src/lib/config.mbt       — Config型 + JSONパース
src/lib/config_test.mbt  — テスト
```

**Config型:**

```moonbit
pub struct Config {
  default_provider : String    // "ollama" | "openai" | "claude"
  history_depth : Int          // default: 10
  keybind : String             // default: "\\C-l"
  ollama_base_url : String
  ollama_model : String
  openai_model : String
  claude_model : String
}

pub fn default_config() -> Config
pub fn parse_config(json : Json) -> Config  // 欠損フィールドはデフォルト値で埋める
```

**APIキーは設定ファイルに含めない** — 環境変数から読む設計を維持。

### 設定の優先順位

```
CLI引数 > 環境変数 > 設定ファイル > デフォルト値
```

---

## プロジェクト構造の変更

```
src/lib/
  ├── types.mbt          # 既存
  ├── cli.mbt            # 既存（--history-depth, --no-history, --init 追加）
  ├── safety.mbt         # 既存
  ├── prompt.mbt         # 拡張（Environment対応）
  ├── provider.mbt       # 既存
  ├── env.mbt            # NEW: 環境検出ロジック
  ├── env_test.mbt       # NEW
  ├── history.mbt        # NEW: 履歴パースロジック
  ├── history_test.mbt   # NEW
  ├── config.mbt         # NEW: 設定ファイル読み込み
  ├── config_test.mbt    # NEW
  └── shell_init.mbt     # NEW: シェルスクリプト生成
src/main/
  └── main.mbt           # 拡張（detect_env, history読み込み, --init処理）
```

---

## 実装順序

```
F1 (env.mbt + prompt.mbt拡張)
  → F2 (history.mbt + cli.mbt拡張)
    → F4 (config.mbt)
      → F3 (shell_init.mbt + --init + cli.mbt拡張)
```

F4をF3の前に移動（設定ファイルにkeybindやhistory_depthを保存する必要があるため）。
