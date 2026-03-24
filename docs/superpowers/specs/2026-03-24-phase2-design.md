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
| date | BSD date (`-j -f`) | GNU date (`-d`) |
| stat | BSD stat (`-f '%z'`) | GNU stat (`-c '%s'`) |
| clipboard | `pbcopy` / `pbpaste` | `xclip` / `xsel` / `wl-copy` |
| open | `open` | `xdg-open` |
| pkg manager | `brew` | `apt` / `dnf` / `pacman` / `apk` |

**ユーザーツール（`command -v` チェック）:**

```
jq, yq, ripgrep (rg), fd, bat, eza, delta,
docker, kubectl, terraform,
git, gh, curl, wget, python3, node, deno, bun
```

### 実装設計

```
src/lib/env.mbt        — Environment型定義 + プロンプト生成ロジック（pure）
src/lib/env_test.mbt   — テスト
src/main/main.mbt      — async fn detect_env() で command -v チェック実行
```

**Environment型:**

```moonbit
pub struct Environment {
  os : String           // "macOS 15.2" / "Ubuntu 24.04"
  shell : String        // "zsh" / "bash" / "fish"
  cwd : String
  platform : String     // "macos" / "linux"
  pkg_manager : String  // "brew" / "apt" / "dnf" / ""
  clipboard : String    // "pbcopy" / "xclip" / "wl-copy" / ""
  find_variant : String // "bsd" / "gnu"
  sed_variant : String  // "bsd" / "gnu"
  date_variant : String // "bsd" / "gnu"
  stat_variant : String // "bsd" / "gnu"
  available_tools : Array[String]  // ["jq", "rg", "fd", "docker", ...]
}
```

**Linuxクリップボード検出の優先順位:**

`$WAYLAND_DISPLAY` が設定されている場合 → `wl-copy` を優先。
それ以外 → `xclip` > `xsel` の順でチェック。

**プロンプトへの反映:**

```
Environment:
- OS: macOS 15.2, Shell: zsh
- Platform tools: BSD find (supports -f), BSD sed (requires -i ''), BSD date (-j -f), BSD stat (-f)
- Clipboard: pbcopy/pbpaste
- Package manager: brew
- Available: jq, rg, fd, docker, gh, python3, node
- Not available: kubectl, terraform

Use available tools when they are better suited.
For example, prefer 'rg' over 'grep' if available, 'fd' over 'find' if available.
```

### パフォーマンス

`command -v` はPOSIX準拠で `which` より信頼性が高い。
1回の `sh -c` で全ツールをまとめてチェック:

```sh
for cmd in jq rg fd docker; do command -v "$cmd" >/dev/null 2>&1 && echo "$cmd"; done
```

---

## F2: Shell History コンテキスト

### 目的

直近のコマンド履歴をLLMに渡し、「さっきの続き」を理解させる。

### 履歴ファイルの検出

| シェル | 履歴ファイル | フォーマット |
|---|---|---|
| zsh | `$HISTFILE` or `~/.zsh_history` | `: timestamp:0;command` |
| bash | `$HISTFILE` or `~/.bash_history` | `command` (1行1コマンド) |
| fish | `$XDG_DATA_HOME/fish/fish_history` or `~/.local/share/fish/fish_history` | `- cmd: command` (YAML風) |

**エッジケース:**
- `$HISTFILE` が設定されているが存在しない → 空配列を返す
- デフォルトパスも存在しない → 空配列を返す
- fishは `$XDG_DATA_HOME` を優先チェック

### 実装設計

```
src/lib/history.mbt       — 履歴パースロジック（pure）
src/lib/history_test.mbt  — テスト
```

**インターフェース:**

```moonbit
pub fn parse_history(shell : String, content : String, depth~ : Int) -> Array[String]
// 内部でシェル種別に応じたパーサーに委譲

pub fn get_history_path(shell : String) -> String
// $HISTFILE > デフォルトパスの優先順位で解決。fishは$XDG_DATA_HOME対応

// 内部関数（private）
fn parse_zsh_history(content : String, depth~ : Int) -> Array[String]
fn parse_bash_history(content : String, depth~ : Int) -> Array[String]
fn parse_fish_history(content : String, depth~ : Int) -> Array[String]
```

**Zsh複数行エントリ:**

zsh履歴には複数行コマンドが含まれる場合がある（`: timestamp:0;` プレフィックスがない行は前のエントリの続き）。複数行エントリは最初の行のみ取得する（トークン節約のための意図的な簡略化）。

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

### プライバシー（ベストエフォート）

履歴にはパスワードやトークンが含まれる可能性がある。以下のキーワードを含む行をスキップ:

- `export`, `API_KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `PASS=`
- `curl -H "Authorization`, `curl.*Bearer`
- `mysql.*-p`, `psql.*password`

**注意:** これはベストエフォートのフィルタリングであり、すべてのセンシティブ情報を除外することを保証しない。 `echo "sk-..."` のような間接的なケースは検出できない。ユーザーが完全にオフにしたい場合は `--no-history` を使う。

---

## F3: Shell Integration (Ctrl+G)

### 目的

ターミナルでCtrl+Gを押すと、インラインプロンプトが表示され、自然言語入力→生成コマンドがコマンドラインに挿入される。

**デフォルトキーバインド: `Ctrl+G`** — "Generate" のGで覚えやすく、標準ターミナルで衝突が少ない。設定ファイルで変更可能。

### 体験フロー

```
$ ls -la src/        ← 通常のターミナル作業
                     ← Ctrl+G を押す
nai> _               ← プロンプトが表示される
nai> find all rust files modified this week
                     ← Enter を押す
$ find . -name "*.rs" -mtime -7    ← 生成コマンドが挿入される（未実行）
                                    ← ユーザーが確認・編集してEnterで実行
```

### 実装: Zsh Widget

```zsh
# ~/.config/nai/nai.zsh

_nai_widget() {
  local query
  zle -I
  # varedを使ってZLE内で安全に入力を受け取る
  local NAI_QUERY=""
  vared -p "nai> " NAI_QUERY
  if [[ -n "$NAI_QUERY" ]]; then
    local result
    result=$(nai "$NAI_QUERY" 2>/dev/null)
    if [[ -n "$result" ]]; then
      BUFFER="$result"
      CURSOR=${#BUFFER}
    fi
  fi
  zle redisplay
}

zle -N _nai_widget
bindkey '^G' _nai_widget
```

### Bash対応

```bash
# ~/.config/nai/nai.bash

_nai_widget() {
  local query
  read -e -p "nai> " query
  if [[ -n "$query" ]]; then
    local result
    result=$(nai "$query" 2>/dev/null)
    if [[ -n "$result" ]]; then
      READLINE_LINE="$result"
      READLINE_POINT=${#READLINE_LINE}
    fi
  fi
}

bind -x '"\C-g": _nai_widget'
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

bind \cg _nai_widget
```

### インストーラー

`nai --init <shell>` コマンドでセットアップ:

```sh
nai --init zsh
# → ~/.config/nai/nai.zsh を生成
# → stdoutに以下を表示:
#   Shell integration installed to ~/.config/nai/nai.zsh
#   Add this line to your ~/.zshrc:
#     source ~/.config/nai/nai.zsh
```

**動作:**
1. `~/.config/nai/` ディレクトリを作成
2. シェルスクリプトをファイルに書き出し
3. ユーザーが自分で `source` 行をrc fileに追記（自動追記はしない — 安全性のため）

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
  "keybind": "\\C-g",
  "ollama": {
    "base_url": "http://localhost:11434/v1",
    "model": "qwen2.5-coder:7b"
  },
  "openai": {
    "base_url": "https://api.openai.com/v1",
    "model": "gpt-4.1-nano"
  },
  "claude": {
    "base_url": "https://api.anthropic.com/v1",
    "model": "claude-haiku-4-5-20251001"
  }
}
```

全プロバイダーに `base_url` を持たせる（OpenAI互換プロキシやAzure OpenAI対応のため）。

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
  keybind : String             // default: "\\C-g"
  ollama_base_url : String
  ollama_model : String
  openai_base_url : String
  openai_model : String
  claude_base_url : String
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

### エッジケース

- 設定ファイルが存在しない → デフォルト値で動作
- JSONパースエラー → stderr に警告を出してデフォルト値で動作
- 未知のフィールド → 無視（前方互換性）
- フィールド欠損 → そのフィールドだけデフォルト値で埋める

---

## プロジェクト構造の変更

```
src/lib/
  ├── types.mbt          # 既存（Environment, Config型追加）
  ├── cli.mbt            # 既存（--history-depth, --no-history, --init 追加）
  ├── safety.mbt         # 既存
  ├── prompt.mbt         # 拡張（Environment対応）
  ├── provider.mbt       # 既存（Config連携）
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
