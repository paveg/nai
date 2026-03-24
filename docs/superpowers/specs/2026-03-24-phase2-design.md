# nai Phase 2 Design: Smart Context & Shell Integration

## Goal

Improve command generation quality by giving the LLM rich environmental context, and integrate nai natively into the terminal workflow.

Four features (F1–F4) implemented in sequence.

---

## F1: Tool Registration + Enhanced OS Detection

### Purpose

Tell the LLM which commands are actually available on the system so it generates platform-correct commands.

### Detection Targets

**OS core differences (auto-detected):**

| Category | macOS (BSD) | Linux (GNU) |
|---|---|---|
| find | BSD: supports `-f path` | GNU: no `-f` flag |
| sed | `-i ''` (empty string required) | `-i` (no argument) |
| date | BSD date (`-j -f`) | GNU date (`-d`) |
| stat | BSD stat (`-f '%z'`) | GNU stat (`-c '%s'`) |
| clipboard | `pbcopy` / `pbpaste` | `xclip` / `xsel` / `wl-copy` |
| open | `open` | `xdg-open` |
| pkg manager | `brew` | `apt` / `dnf` / `pacman` / `apk` |

**User tools (`command -v` check):**

```
jq, yq, ripgrep (rg), fd, bat, eza, delta,
docker, kubectl, terraform,
git, gh, curl, wget, python3, node, deno, bun
```

### Implementation

```
src/lib/env.mbt        — Environment type + prompt generation logic (pure)
src/lib/env_test.mbt   — Tests
src/main/main.mbt      — async fn detect_env() runs command -v checks
```

**Environment type:**

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

**Linux clipboard detection priority:**

If `$WAYLAND_DISPLAY` is set → prefer `wl-copy`.
Otherwise → `xclip` > `xsel` in order.

**System prompt addition:**

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

### Performance

`command -v` is POSIX-compliant and more reliable than `which`.
All tools checked in a single `sh -c` invocation:

```sh
for cmd in jq rg fd docker; do command -v "$cmd" >/dev/null 2>&1 && echo "$cmd"; done
```

---

## F2: Shell History Context

### Purpose

Pass recent command history to the LLM so it understands the user's current workflow context.

### History File Detection

| Shell | History file | Format |
|---|---|---|
| zsh | `$HISTFILE` or `~/.zsh_history` | `: timestamp:0;command` |
| bash | `$HISTFILE` or `~/.bash_history` | `command` (one per line) |
| fish | `$XDG_DATA_HOME/fish/fish_history` or `~/.local/share/fish/fish_history` | `- cmd: command` (YAML-like) |

**Edge cases:**
- `$HISTFILE` set but file doesn't exist → return empty array
- Default path doesn't exist → return empty array
- Fish checks `$XDG_DATA_HOME` first

### Implementation

```
src/lib/history.mbt       — History parsing logic (pure)
src/lib/history_test.mbt  — Tests
```

**Interface:**

```moonbit
pub fn parse_history(shell : String, content : String, depth~ : Int) -> Array[String]
// Dispatches to shell-specific parser internally

pub fn get_history_path(shell : String) -> String
// Resolves: $HISTFILE > default path. Fish checks $XDG_DATA_HOME.

// Internal (private)
fn parse_zsh_history(content : String, depth~ : Int) -> Array[String]
fn parse_bash_history(content : String, depth~ : Int) -> Array[String]
fn parse_fish_history(content : String, depth~ : Int) -> Array[String]
```

**Zsh multi-line entries:**

Zsh history can contain multi-line commands (continuation lines lack the `: timestamp:0;` prefix). Multi-line entries are truncated to the first line only (intentional simplification to save tokens).

**System prompt addition:**

```
Recent commands (most recent first):
1. grep -r "TODO" src/
2. git status
3. cd ~/repos/project
4. docker ps

Consider this context when generating commands.
The user may be continuing a workflow.
```

### Configuration

- Default: 10 entries
- `--history-depth N` flag to adjust
- `--no-history` to disable
- Config file (F4) `history_depth` to change default

### Privacy (Best-Effort)

History may contain passwords or tokens. Lines containing these keywords are skipped:

- `export`, `API_KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `PASS=`
- `curl -H "Authorization`, `curl.*Bearer`
- `mysql.*-p`, `psql.*password`

**Note:** This is best-effort filtering and does not guarantee removal of all sensitive data. Indirect cases like `echo "sk-..."` are not caught. Use `--no-history` to disable entirely.

---

## F3: Shell Integration (Ctrl+])

### Purpose

Press Ctrl+] in the terminal to open an inline prompt, type a natural language query, and have the generated command inserted into the command line buffer (not executed — user reviews first).

**Default keybind: `Ctrl+]`** — rarely used in modern terminal workflows (legacy telnet escape). Configurable via config file.

### User Experience Flow

```
$ ls -la src/        ← normal terminal work
                     ← press Ctrl+]
nai> _               ← prompt appears
nai> find all rust files modified this week
                     ← press Enter
$ find . -name "*.rs" -mtime -7    ← generated command inserted (not executed)
                                    ← user reviews, edits, then presses Enter to run
```

### Zsh Widget

```zsh
# ~/.config/nai/nai.zsh

_nai_widget() {
  local query
  zle -I
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
bindkey '^\]' _nai_widget
```

### Bash Widget

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

bind -x '"^\]": _nai_widget'
```

### Fish Widget

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

bind \c] _nai_widget
```

### Installer

`nai --init <shell>` generates the integration script:

```sh
nai --init zsh
# Output:
#   Shell integration installed to ~/.config/nai/nai.zsh
#   Add this line to your ~/.zshrc:
#     source ~/.config/nai/nai.zsh
```

**Behavior:**
1. Create `~/.config/nai/` directory
2. Write shell script to file
3. Print the `source` line for the user to add manually (no automatic rc file modification — safety first)

---

## F4: Config File

### Purpose

Persist user settings for provider defaults, history depth, keybinding, etc.

### File Path

`~/.config/nai/config.json`

### Schema

```json
{
  "default_provider": "ollama",
  "history_depth": 10,
  "keybind": "^]",
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

All providers have `base_url` (supports OpenAI-compatible proxies and Azure OpenAI).

### Implementation

```
src/lib/config.mbt       — Config type + JSON parsing
src/lib/config_test.mbt  — Tests
```

**Config type:**

```moonbit
pub struct Config {
  default_provider : String    // "ollama" | "openai" | "claude"
  history_depth : Int          // default: 10
  keybind : String             // default: "^]"
  ollama_base_url : String
  ollama_model : String
  openai_base_url : String
  openai_model : String
  claude_base_url : String
  claude_model : String
}

pub fn default_config() -> Config
pub fn parse_config(json : Json) -> Config  // missing fields filled with defaults
```

**API keys are never stored in the config file** — read from environment variables only.

### Priority Order

```
CLI flags > environment variables > config file > defaults
```

### Edge Cases

- Config file doesn't exist → use defaults
- JSON parse error → warn on stderr, use defaults
- Unknown fields → ignore (forward compatibility)
- Missing fields → fill with defaults for that field only

---

## Project Structure Changes

```
src/lib/
  ├── types.mbt          # existing (add Environment, Config types)
  ├── cli.mbt            # existing (add --history-depth, --no-history, --init)
  ├── safety.mbt         # existing
  ├── prompt.mbt         # extend (Environment-aware prompt building)
  ├── provider.mbt       # existing (Config integration)
  ├── env.mbt            # NEW: environment detection logic
  ├── env_test.mbt       # NEW
  ├── history.mbt        # NEW: history parsing logic
  ├── history_test.mbt   # NEW
  ├── config.mbt         # NEW: config file loading
  ├── config_test.mbt    # NEW
  └── shell_init.mbt     # NEW: shell script generation
src/main/
  └── main.mbt           # extend (detect_env, history loading, --init handling)
```

---

## Implementation Order

```
F1 (env.mbt + prompt.mbt extension)
  → F2 (history.mbt + cli.mbt extension)
    → F4 (config.mbt)
      → F3 (shell_init.mbt + --init + cli.mbt extension)
```

F4 is placed before F3 because shell init scripts need to read config for keybind settings.
