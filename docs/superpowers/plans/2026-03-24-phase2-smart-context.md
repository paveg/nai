# Phase 2: Smart Context & Shell Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve nai's command generation accuracy by providing rich environmental context (available tools, OS variants, shell history) and add native terminal integration via Ctrl+] keybinding.

**Architecture:** Four features built in sequence (F1→F2→F4→F3). All parsing/formatting logic is pure (in `src/lib/`) and tested independently. Async IO (tool detection, history file reading, config file reading, shell script writing) lives in `src/main/main.mbt`. The `build_system_prompt` function is replaced by an Environment-aware version that includes tool availability and history context.

**Tech Stack:** MoonBit (native backend), `moonbitlang/async` (process/fs), `moonbitlang/x/sys` (env vars)

---

## File Structure

```
src/lib/
  types.mbt          — MODIFY: add Environment, Config types + new CliArgs fields
  cli.mbt            — MODIFY: add --history-depth, --no-history, --init flags
  cli_test.mbt       — MODIFY: add tests for new flags
  prompt.mbt         — MODIFY: replace build_system_prompt with Environment-aware version
  prompt_test.mbt    — MODIFY: update tests for new prompt signature
  provider.mbt       — existing (config integration deferred to Phase 3)
  provider_test.mbt  — existing
  env.mbt            — CREATE: build_env_prompt (pure formatting)
  env_test.mbt       — CREATE: tests
  history.mbt        — CREATE: parse_history, get_history_path, is_sensitive
  history_test.mbt   — CREATE: tests
  config.mbt         — CREATE: default_config, parse_config
  config_test.mbt    — CREATE: tests
  shell_init.mbt     — CREATE: generate_shell_script
  shell_init_test.mbt — CREATE: tests
src/main/
  main.mbt           — MODIFY: detect_env, load history, load config, --init handler
```

---

## Task 1: Environment Type & Prompt Formatting

**Files:**
- Modify: `src/lib/types.mbt`
- Create: `src/lib/env.mbt`
- Create: `src/lib/env_test.mbt`

- [ ] **Step 1: Add Environment type to types.mbt**

Append to `src/lib/types.mbt`:

```moonbit
pub struct Environment {
  os : String
  shell : String
  cwd : String
  platform : String
  pkg_manager : String
  clipboard : String
  find_variant : String
  sed_variant : String
  date_variant : String
  stat_variant : String
  available_tools : Array[String]
  history : Array[String]
} derive(Show)
```

- [ ] **Step 2: Write failing tests for env prompt formatting**

Create `src/lib/env_test.mbt`:

```moonbit
test "build_env_prompt includes OS and shell" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/Users/test",
    platform: "macos", pkg_manager: "brew", clipboard: "pbcopy",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: ["jq", "rg", "fd"],
    history: [],
  }
  let prompt = build_env_prompt(env)
  assert_true(prompt.contains("macOS 15.2"))
  assert_true(prompt.contains("zsh"))
  assert_true(prompt.contains("/Users/test"))
}

test "build_env_prompt includes BSD tool variants" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/tmp",
    platform: "macos", pkg_manager: "brew", clipboard: "pbcopy",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: [],
    history: [],
  }
  let prompt = build_env_prompt(env)
  assert_true(prompt.contains("BSD find"))
  assert_true(prompt.contains("BSD sed"))
  assert_true(prompt.contains("BSD date"))
  assert_true(prompt.contains("BSD stat"))
}

test "build_env_prompt includes GNU tool variants" {
  let env : Environment = {
    os: "Ubuntu 24.04", shell: "bash", cwd: "/home/user",
    platform: "linux", pkg_manager: "apt", clipboard: "xclip",
    find_variant: "gnu", sed_variant: "gnu", date_variant: "gnu",
    stat_variant: "gnu", available_tools: ["docker"],
    history: [],
  }
  let prompt = build_env_prompt(env)
  assert_true(prompt.contains("GNU find"))
  assert_true(prompt.contains("GNU sed"))
  assert_true(prompt.contains("apt"))
  assert_true(prompt.contains("xclip"))
}

test "build_env_prompt includes available tools" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/tmp",
    platform: "macos", pkg_manager: "brew", clipboard: "pbcopy",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: ["jq", "rg", "fd", "docker"],
    history: [],
  }
  let prompt = build_env_prompt(env)
  assert_true(prompt.contains("jq"))
  assert_true(prompt.contains("rg"))
  assert_true(prompt.contains("fd"))
  assert_true(prompt.contains("docker"))
}

test "build_env_prompt includes history when present" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/tmp",
    platform: "macos", pkg_manager: "", clipboard: "",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: [],
    history: ["grep -r TODO src/", "git status", "cd ~/repos"],
  }
  let prompt = build_env_prompt(env)
  assert_true(prompt.contains("Recent commands"))
  assert_true(prompt.contains("grep -r TODO src/"))
  assert_true(prompt.contains("git status"))
}

test "build_env_prompt omits history section when empty" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/tmp",
    platform: "macos", pkg_manager: "", clipboard: "",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: [],
    history: [],
  }
  let prompt = build_env_prompt(env)
  assert_true(!(prompt.contains("Recent commands")))
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `build_env_prompt` not defined

- [ ] **Step 4: Implement build_env_prompt**

Create `src/lib/env.mbt`:

```moonbit
fn variant_desc(tool : String, variant : String) -> String {
  let v = if variant == "bsd" { "BSD" } else { "GNU" }
  let detail = match (tool, variant) {
    ("find", "bsd") => " (supports -f)"
    ("sed", "bsd") => " (requires -i '')"
    ("sed", "gnu") => " (-i without arg)"
    ("date", "bsd") => " (-j -f)"
    ("date", "gnu") => " (-d)"
    ("stat", "bsd") => " (-f format)"
    ("stat", "gnu") => " (-c format)"
    _ => ""
  }
  "\{v} \{tool}\{detail}"
}

pub fn build_env_prompt(env : Environment) -> String {
  let buf = StringBuilder::new()

  // Base system prompt
  buf.write_string(
    (
      $|You are a shell command generator. Given a natural language description,
      $|output ONLY a single shell one-liner. No explanations, no markdown,
      $|no code fences — just the raw command.
      $|
      $|Rules:
      $|- Output exactly one line of shell command
      $|- If ambiguous, choose the safest interpretation
      $|- Do not wrap in backticks or quotes
    ),
  )

  // Environment section
  buf.write_string("\n\nEnvironment:\n")
  buf.write_string("- OS: \{env.os}, Shell: \{env.shell}\n")
  buf.write_string("- Current directory: \{env.cwd}\n")

  // Platform tool variants
  let variants = [
    variant_desc("find", env.find_variant),
    variant_desc("sed", env.sed_variant),
    variant_desc("date", env.date_variant),
    variant_desc("stat", env.stat_variant),
  ]
  buf.write_string("- Platform tools: \{variants.join(", ")}\n")

  // Clipboard
  if env.clipboard != "" {
    buf.write_string("- Clipboard: \{env.clipboard}\n")
  }

  // Package manager
  if env.pkg_manager != "" {
    buf.write_string("- Package manager: \{env.pkg_manager}\n")
  }

  // Available tools
  if !(env.available_tools.is_empty()) {
    buf.write_string("- Available: \{env.available_tools.join(", ")}\n")
  }

  buf.write_string(
    "\nUse available tools when they are better suited. For example, prefer 'rg' over 'grep' if available.\n",
  )

  // History section
  if !(env.history.is_empty()) {
    buf.write_string("\nRecent commands (most recent first):\n")
    for i, cmd in env.history {
      buf.write_string("\{i + 1}. \{cmd}\n")
    }
    buf.write_string(
      "\nConsider this context when generating commands. The user may be continuing a workflow.\n",
    )
  }

  buf.to_string()
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/lib/types.mbt src/lib/env.mbt src/lib/env_test.mbt
git commit -m "feat: add Environment type and build_env_prompt for rich context"
```

---

## Task 2: History Parsing

**Files:**
- Create: `src/lib/history.mbt`
- Create: `src/lib/history_test.mbt`

- [ ] **Step 1: Write failing tests for history parsing**

Create `src/lib/history_test.mbt`:

```moonbit
test "parse_zsh_history extracts commands" {
  let content =
    #|: 1711234567:0;ls -la
    #|: 1711234568:0;git status
    #|: 1711234569:0;cd ~/repos
  let result = parse_history("zsh", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "cd ~/repos")
  assert_eq(result[1], "git status")
}

test "parse_zsh_history skips multiline continuations" {
  let content =
    #|: 1711234567:0;for f in *.txt; do
    #|  echo "$f"
    #|done
    #|: 1711234568:0;ls -la
  let result = parse_history("zsh", content, depth=10)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "ls -la")
  assert_eq(result[1], "for f in *.txt; do")
}

test "parse_bash_history extracts last N commands" {
  let content =
    #|ls -la
    #|git status
    #|cd ~/repos
    #|docker ps
  let result = parse_history("bash", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "docker ps")
  assert_eq(result[1], "cd ~/repos")
}

test "parse_fish_history extracts commands" {
  let content =
    #|- cmd: ls -la
    #|  when: 1711234567
    #|- cmd: git status
    #|  when: 1711234568
  let result = parse_history("fish", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "git status")
  assert_eq(result[1], "ls -la")
}

test "parse_history returns empty for unknown shell" {
  let result = parse_history("unknown", "some content", depth=5)
  assert_eq(result.length(), 0)
}

test "parse_history respects depth limit" {
  let content =
    #|line1
    #|line2
    #|line3
    #|line4
    #|line5
  let result = parse_history("bash", content, depth=3)
  assert_eq(result.length(), 3)
}

test "is_sensitive filters export lines" {
  assert_true(is_sensitive("export API_KEY=abc123"))
  assert_true(is_sensitive("export SECRET_TOKEN=xyz"))
}

test "is_sensitive filters curl auth" {
  assert_true(is_sensitive("curl -H \"Authorization: Bearer sk-xxx\" https://api.example.com"))
}

test "is_sensitive allows safe commands" {
  assert_true(!(is_sensitive("ls -la")))
  assert_true(!(is_sensitive("git status")))
  assert_true(!(is_sensitive("docker ps")))
}

test "parse_history filters sensitive lines" {
  let content =
    #|ls -la
    #|export API_KEY=secret
    #|git status
    #|curl -H "Authorization: Bearer token" https://api.com
    #|docker ps
  let result = parse_history("bash", content, depth=10)
  // Verify sensitive lines are excluded, safe lines are included
  let joined = result.join(" | ")
  assert_true(!(joined.contains("export API_KEY")))
  assert_true(!(joined.contains("Authorization")))
  assert_true(joined.contains("ls -la"))
  assert_true(joined.contains("git status"))
  assert_true(joined.contains("docker ps"))
}

test "get_history_path returns zsh default" {
  let path = get_history_path("zsh")
  assert_true(path.contains(".zsh_history") || path.contains("HISTFILE"))
}

test "get_history_path returns bash default" {
  let path = get_history_path("bash")
  assert_true(path.contains(".bash_history") || path.contains("HISTFILE"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `parse_history`, `is_sensitive`, `get_history_path` not defined

- [ ] **Step 3: Implement history parsing**

Create `src/lib/history.mbt`:

```moonbit
let sensitive_patterns : Array[String] = [
  "export ", "api_key", "token", "secret", "password", "pass=",
  "curl -h \"authorization", "curl.*bearer",
  "mysql.*-p", "psql.*password",
]

pub fn is_sensitive(line : String) -> Bool {
  let lower = line.to_lower()
  for pattern in sensitive_patterns {
    if lower.contains(pattern) {
      return true
    }
  }
  false
}

fn parse_zsh_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.to_string().trim().to_string()
    if s == "" {
      continue
    }
    // Zsh format: ": timestamp:0;command"
    // Skip continuation lines (no ": " prefix)
    if !(s.has_prefix(": ")) {
      continue
    }
    // Extract command after the first ";"
    // Find first semicolon index manually (String.index_of does not exist)
    let mut semicolon_idx = -1
    for j = 0; j < s.length(); j = j + 1 {
      if s[j] == ';' {
        semicolon_idx = j
        break
      }
    }
    if semicolon_idx >= 0 {
      let cmd = s[(semicolon_idx + 1):].to_string()
      if cmd != "" && not(is_sensitive(cmd)) {
        entries.push(cmd)
      }
    }
  }
  // Return last N entries in reverse order (most recent first)
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

fn parse_bash_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.to_string().trim().to_string()
    if s != "" && not(is_sensitive(s)) {
      entries.push(s)
    }
  }
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

fn parse_fish_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.to_string().trim().to_string()
    if s.has_prefix("- cmd: ") {
      let cmd = s[7:].to_string()
      if cmd != "" && not(is_sensitive(cmd)) {
        entries.push(cmd)
      }
    }
  }
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

pub fn parse_history(shell : String, content : String, depth~ : Int) -> Array[String] {
  match shell {
    "zsh" => parse_zsh_history(content, depth~)
    "bash" => parse_bash_history(content, depth~)
    "fish" => parse_fish_history(content, depth~)
    _ => []
  }
}

pub fn get_history_path(shell : String) -> String {
  match @sys.get_env_var("HISTFILE") {
    Some(path) => path
    None =>
      match shell {
        "zsh" => {
          let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
          "\{home}/.zsh_history"
        }
        "bash" => {
          let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
          "\{home}/.bash_history"
        }
        "fish" => {
          let xdg = @sys.get_env_var("XDG_DATA_HOME")
          match xdg {
            Some(dir) => "\{dir}/fish/fish_history"
            None => {
              let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
              "\{home}/.local/share/fish/fish_history"
            }
          }
        }
        _ => ""
      }
  }
}
```

**Note:** `s[j]` char access syntax may need `s.char_at(j)` — adjust at build time if needed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/history.mbt src/lib/history_test.mbt
git commit -m "feat: add shell history parsing with privacy filtering"
```

---

## Task 3: CLI Args Extension

**Files:**
- Modify: `src/lib/types.mbt`
- Modify: `src/lib/cli.mbt`
- Modify: `src/lib/cli_test.mbt`

- [ ] **Step 1: Add new fields to CliArgs**

Update `CliArgs` in `src/lib/types.mbt`:

```moonbit
pub struct CliArgs {
  query : String
  exec : Bool
  explain : Bool
  provider : String
  model : String
  help : Bool
  version : Bool
  history_depth : Int    // default: -1 (meaning "use config default")
  no_history : Bool      // --no-history flag
  init_shell : String    // "" or "zsh" / "bash" / "fish"
} derive(Show, Eq)
```

- [ ] **Step 2: Write failing tests for new CLI flags**

Append to `src/lib/cli_test.mbt`:

```moonbit
test "parse --history-depth flag" {
  let args = parse_args(["nai", "--history-depth", "20", "my query"])
  assert_eq(args.history_depth, 20)
  assert_eq(args.query, "my query")
}

test "parse --no-history flag" {
  let args = parse_args(["nai", "--no-history", "my query"])
  assert_eq(args.no_history, true)
  assert_eq(args.query, "my query")
}

test "parse --init flag" {
  let args = parse_args(["nai", "--init", "zsh"])
  assert_eq(args.init_shell, "zsh")
}

test "parse default history_depth is -1" {
  let args = parse_args(["nai", "my query"])
  assert_eq(args.history_depth, -1)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — new fields don't exist on CliArgs / parse_args doesn't handle them

- [ ] **Step 4: Update parse_args to handle new flags**

Modify `src/lib/cli.mbt` — add `history_depth`, `no_history`, `init_shell`:

```moonbit
pub fn parse_args(raw : Array[String]) -> CliArgs {
  let mut exec = false
  let mut explain = false
  let mut provider = "auto"
  let mut model = ""
  let mut help = false
  let mut version = false
  let mut history_depth = -1
  let mut no_history = false
  let mut init_shell = ""
  let positional : Array[String] = []
  let mut i = 1
  while i < raw.length() {
    let arg = raw[i]
    match arg {
      "--exec" | "-e" => exec = true
      "--explain" => explain = true
      "--provider" | "-p" => {
        i += 1
        if i < raw.length() { provider = raw[i] }
      }
      "--model" | "-m" => {
        i += 1
        if i < raw.length() { model = raw[i] }
      }
      "--history-depth" => {
        i += 1
        if i < raw.length() {
          // Parse int manually (no @strconv in MoonBit core)
          let mut n = 0
          let mut valid = true
          for c in raw[i] {
            if c >= '0' && c <= '9' {
              n = n * 10 + (c.to_int() - '0'.to_int())
            } else {
              valid = false
              break
            }
          }
          if valid { history_depth = n }
        }
      }
      "--no-history" => no_history = true
      "--init" => {
        i += 1
        if i < raw.length() { init_shell = raw[i] }
      }
      "--help" | "-h" => help = true
      "--version" | "-V" => version = true
      _ => positional.push(arg)
    }
    i += 1
  }
  let query = positional.join(" ")
  if query == "" && !help && !version && init_shell == "" {
    help = true
  }
  { query, exec, explain, provider, model, help, version, history_depth, no_history, init_shell }
}
```

**Note:** Int parsing is done manually via char iteration (no `@strconv` in MoonBit core).

- [ ] **Step 5: Fix existing tests (add new fields to assertions)**

Update existing tests in `cli_test.mbt` to include the new fields where struct equality is checked (the "parse basic query" test). Either add the new fields or remove the full-struct comparison and check fields individually (which they already do).

- [ ] **Step 6: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/lib/types.mbt src/lib/cli.mbt src/lib/cli_test.mbt
git commit -m "feat: add --history-depth, --no-history, --init CLI flags"
```

---

## Task 4: Config File Support

**Files:**
- Modify: `src/lib/types.mbt` (add Config type if not already there)
- Create: `src/lib/config.mbt`
- Create: `src/lib/config_test.mbt`

- [ ] **Step 1: Add Config type to types.mbt**

Append to `src/lib/types.mbt`:

```moonbit
pub struct Config {
  default_provider : String
  history_depth : Int
  keybind : String
  ollama_base_url : String
  ollama_model : String
  openai_base_url : String
  openai_model : String
  claude_base_url : String
  claude_model : String
} derive(Show, Eq)
```

- [ ] **Step 2: Write failing tests**

Create `src/lib/config_test.mbt`:

```moonbit
test "default_config has expected values" {
  let c = default_config()
  assert_eq(c.default_provider, "ollama")
  assert_eq(c.history_depth, 10)
  assert_eq(c.keybind, "^]")
  assert_eq(c.ollama_base_url, "http://localhost:11434/v1")
  assert_eq(c.ollama_model, "qwen2.5-coder:7b")
  assert_eq(c.openai_base_url, "https://api.openai.com/v1")
  assert_eq(c.openai_model, "gpt-4.1-nano")
  assert_eq(c.claude_base_url, "https://api.anthropic.com/v1")
  assert_eq(c.claude_model, "claude-haiku-4-5-20251001")
}

test "parse_config with full JSON" {
  let json = @json.parse!(
    #|{"default_provider":"openai","history_depth":20,"keybind":"^G","ollama":{"base_url":"http://custom:11434/v1","model":"llama3:8b"},"openai":{"base_url":"https://custom.openai.com/v1","model":"gpt-4.1"},"claude":{"base_url":"https://custom.anthropic.com/v1","model":"claude-sonnet"}}
  )
  let c = parse_config(json)
  assert_eq(c.default_provider, "openai")
  assert_eq(c.history_depth, 20)
  assert_eq(c.keybind, "^G")
  assert_eq(c.ollama_base_url, "http://custom:11434/v1")
  assert_eq(c.ollama_model, "llama3:8b")
  assert_eq(c.openai_base_url, "https://custom.openai.com/v1")
  assert_eq(c.openai_model, "gpt-4.1")
  assert_eq(c.claude_base_url, "https://custom.anthropic.com/v1")
  assert_eq(c.claude_model, "claude-sonnet")
}

test "parse_config with empty JSON uses defaults" {
  let json = @json.parse!(
    #|{}
  )
  let c = parse_config(json)
  let d = default_config()
  assert_eq(c, d)
}

test "parse_config with partial JSON fills defaults" {
  let json = @json.parse!(
    #|{"default_provider":"claude","history_depth":5}
  )
  let c = parse_config(json)
  assert_eq(c.default_provider, "claude")
  assert_eq(c.history_depth, 5)
  assert_eq(c.ollama_model, "qwen2.5-coder:7b")
  assert_eq(c.openai_model, "gpt-4.1-nano")
}

test "parse_config ignores unknown fields" {
  let json = @json.parse!(
    #|{"default_provider":"openai","unknown_field":"whatever"}
  )
  let c = parse_config(json)
  assert_eq(c.default_provider, "openai")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `default_config`, `parse_config` not defined

- [ ] **Step 4: Implement config parsing**

Create `src/lib/config.mbt`:

```moonbit
pub fn default_config() -> Config {
  {
    default_provider: "ollama",
    history_depth: 10,
    keybind: "^]",
    ollama_base_url: "http://localhost:11434/v1",
    ollama_model: "qwen2.5-coder:7b",
    openai_base_url: "https://api.openai.com/v1",
    openai_model: "gpt-4.1-nano",
    claude_base_url: "https://api.anthropic.com/v1",
    claude_model: "claude-haiku-4-5-20251001",
  }
}

pub fn parse_config(json : Json) -> Config {
  let d = default_config()

  // Extract top-level fields via pattern matching
  let default_provider = match json {
    { "default_provider": String(s), .. } => s
    _ => d.default_provider
  }
  let history_depth = match json {
    { "history_depth": Number(n), .. } => n.to_int()
    _ => d.history_depth
  }
  let keybind = match json {
    { "keybind": String(s), .. } => s
    _ => d.keybind
  }

  // Extract nested provider objects
  let (ollama_base_url, ollama_model) = match json {
    { "ollama": { "base_url": String(bu), "model": String(m), .. }, .. } => (bu, m)
    { "ollama": { "base_url": String(bu), .. }, .. } => (bu, d.ollama_model)
    { "ollama": { "model": String(m), .. }, .. } => (d.ollama_base_url, m)
    _ => (d.ollama_base_url, d.ollama_model)
  }
  let (openai_base_url, openai_model) = match json {
    { "openai": { "base_url": String(bu), "model": String(m), .. }, .. } => (bu, m)
    { "openai": { "base_url": String(bu), .. }, .. } => (bu, d.openai_model)
    { "openai": { "model": String(m), .. }, .. } => (d.openai_base_url, m)
    _ => (d.openai_base_url, d.openai_model)
  }
  let (claude_base_url, claude_model) = match json {
    { "claude": { "base_url": String(bu), "model": String(m), .. }, .. } => (bu, m)
    { "claude": { "base_url": String(bu), .. }, .. } => (bu, d.claude_model)
    { "claude": { "model": String(m), .. }, .. } => (d.claude_base_url, m)
    _ => (d.claude_base_url, d.claude_model)
  }

  {
    default_provider, history_depth, keybind,
    ollama_base_url, ollama_model,
    openai_base_url, openai_model,
    claude_base_url, claude_model,
  }
}

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/lib/types.mbt src/lib/config.mbt src/lib/config_test.mbt
git commit -m "feat: add config file parsing with defaults and partial overrides"
```

---

## Task 5: Shell Init Script Generation

**Files:**
- Create: `src/lib/shell_init.mbt`
- Create: `src/lib/shell_init_test.mbt`

- [ ] **Step 1: Write failing tests**

Create `src/lib/shell_init_test.mbt`:

```moonbit
test "generate zsh script" {
  let script = generate_shell_script("zsh", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("vared"))
  assert_true(script.contains("BUFFER="))
  assert_true(script.contains("bindkey"))
  assert_true(script.contains("^]"))
}

test "generate bash script" {
  let script = generate_shell_script("bash", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("READLINE_LINE"))
  assert_true(script.contains("bind"))
  assert_true(script.contains("^]"))
}

test "generate fish script" {
  let script = generate_shell_script("fish", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("commandline"))
  assert_true(script.contains("bind"))
}

test "generate unknown shell returns empty" {
  let script = generate_shell_script("unknown", keybind="^]")
  assert_eq(script, "")
}

test "generate zsh script with custom keybind" {
  let script = generate_shell_script("zsh", keybind="^G")
  assert_true(script.contains("^G"))
  assert_true(!(script.contains("^]")))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `generate_shell_script` not defined

- [ ] **Step 3: Implement shell script generation**

Create `src/lib/shell_init.mbt`:

```moonbit
pub fn generate_shell_script(shell : String, keybind~ : String) -> String {
  match shell {
    "zsh" => generate_zsh_script(keybind)
    "bash" => generate_bash_script(keybind)
    "fish" => generate_fish_script(keybind)
    _ => ""
  }
}

fn generate_zsh_script(keybind : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# nai shell integration for zsh\n")
  buf.write_string("# Generated by: nai --init zsh\n\n")
  buf.write_string("_nai_widget() {\n")
  buf.write_string("  local query\n")
  buf.write_string("  zle -I\n")
  buf.write_string("  local NAI_QUERY=\"\"\n")
  buf.write_string("  vared -p \"nai> \" NAI_QUERY\n")
  buf.write_string("  if [[ -n \"$NAI_QUERY\" ]]; then\n")
  buf.write_string("    local result\n")
  buf.write_string("    result=$(nai \"$NAI_QUERY\" 2>/dev/null)\n")
  buf.write_string("    if [[ -n \"$result\" ]]; then\n")
  buf.write_string("      BUFFER=\"$result\"\n")
  buf.write_string("      CURSOR=${#BUFFER}\n")
  buf.write_string("    fi\n")
  buf.write_string("  fi\n")
  buf.write_string("  zle redisplay\n")
  buf.write_string("}\n\n")
  buf.write_string("zle -N _nai_widget\n")
  buf.write_string("bindkey '\{keybind}' _nai_widget\n")
  buf.to_string()
}

fn generate_bash_script(keybind : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# nai shell integration for bash\n")
  buf.write_string("# Generated by: nai --init bash\n\n")
  buf.write_string("_nai_widget() {\n")
  buf.write_string("  local query\n")
  buf.write_string("  read -e -p \"nai> \" query\n")
  buf.write_string("  if [[ -n \"$query\" ]]; then\n")
  buf.write_string("    local result\n")
  buf.write_string("    result=$(nai \"$query\" 2>/dev/null)\n")
  buf.write_string("    if [[ -n \"$result\" ]]; then\n")
  buf.write_string("      READLINE_LINE=\"$result\"\n")
  buf.write_string("      READLINE_POINT=${#READLINE_LINE}\n")
  buf.write_string("    fi\n")
  buf.write_string("  fi\n")
  buf.write_string("}\n\n")
  buf.write_string("bind -x '\"\{keybind}\": _nai_widget'\n")
  buf.to_string()
}

fn generate_fish_script(keybind : String) -> String {
  // Fish uses different bind syntax; convert ^] to \c]
  let fish_key = if keybind.has_prefix("^") {
    "\\c" + keybind[1:].to_string()
  } else {
    keybind
  }
  let buf = StringBuilder::new()
  buf.write_string("# nai shell integration for fish\n")
  buf.write_string("# Generated by: nai --init fish\n\n")
  buf.write_string("function _nai_widget\n")
  buf.write_string("  set -l query (read -P \"nai> \")\n")
  buf.write_string("  if test -n \"$query\"\n")
  buf.write_string("    set -l result (nai \"$query\" 2>/dev/null)\n")
  buf.write_string("    if test -n \"$result\"\n")
  buf.write_string("      commandline -r $result\n")
  buf.write_string("      commandline -f repaint\n")
  buf.write_string("    end\n")
  buf.write_string("  end\n")
  buf.write_string("end\n\n")
  buf.write_string("bind \{fish_key} _nai_widget\n")
  buf.to_string()
}

pub fn shell_rc_file(shell : String) -> String {
  match shell {
    "zsh" => "~/.zshrc"
    "bash" => "~/.bashrc"
    "fish" => "~/.config/fish/config.fish"
    _ => ""
  }
}

pub fn shell_init_path(shell : String) -> String {
  match shell {
    "zsh" => "~/.config/nai/nai.zsh"
    "bash" => "~/.config/nai/nai.bash"
    "fish" => "~/.config/nai/nai.fish"
    _ => ""
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/shell_init.mbt src/lib/shell_init_test.mbt
git commit -m "feat: add shell integration script generation for zsh/bash/fish"
```

---

## Task 6: Update prompt.mbt (Remove Old Signature)

**Files:**
- Modify: `src/lib/prompt.mbt`
- Modify: `src/lib/prompt_test.mbt`

- [ ] **Step 1: Update prompt.mbt**

Replace the old `build_system_prompt` with a thin wrapper that delegates to `build_env_prompt`. Keep `build_explain_prompt` unchanged.

```moonbit
pub fn build_system_prompt(env : Environment) -> String {
  build_env_prompt(env)
}

pub fn build_explain_prompt(command : String) -> String {
  $|Explain the following shell command in detail.
  $|Break down each part (command, flags, arguments, pipes).
  $|Be concise but thorough.
  $|
  $|Command: \{command}
}
```

- [ ] **Step 2: Update prompt_test.mbt**

Replace existing tests to use the new Environment-based signature:

```moonbit
test "build system prompt contains os info" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/Users/test",
    platform: "macos", pkg_manager: "brew", clipboard: "pbcopy",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: [],
    history: [],
  }
  let prompt = build_system_prompt(env)
  assert_true(prompt.contains("macOS 15.2"))
  assert_true(prompt.contains("zsh"))
  assert_true(prompt.contains("/Users/test"))
}

test "build system prompt contains rules" {
  let env : Environment = {
    os: "Linux", shell: "bash", cwd: "/home/user",
    platform: "linux", pkg_manager: "", clipboard: "",
    find_variant: "gnu", sed_variant: "gnu", date_variant: "gnu",
    stat_variant: "gnu", available_tools: [],
    history: [],
  }
  let prompt = build_system_prompt(env)
  assert_true(prompt.contains("one line of shell command"))
}

test "build explain prompt" {
  let prompt = build_explain_prompt("find . -name '*.rs' -mtime -7")
  assert_true(prompt.contains("find . -name '*.rs' -mtime -7"))
  assert_true(prompt.contains("Explain") || prompt.contains("explain"))
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add src/lib/prompt.mbt src/lib/prompt_test.mbt
git commit -m "refactor: update build_system_prompt to use Environment struct"
```

---

## Task 7: Wire Up Main Orchestrator

**Files:**
- Modify: `src/main/main.mbt`
- Modify: `src/main/moon.pkg.json` (may need additional imports)

- [ ] **Step 1: Add detect_env, config loading, history loading to main.mbt**

Replace the existing `detect_os`, `detect_shell`, `detect_cwd` functions with a unified `detect_env` that builds a full `Environment`. Add config file loading and `--init` handler.

Key changes to `async fn main`:

```moonbit
async fn detect_platform() -> String {
  try {
    let (_, _) = @process.collect_output_merged("sw_vers", ["-productVersion"])
    "macos"
  } catch {
    _ => "linux"
  }
}

async fn detect_tool_variants(platform : String) -> (String, String, String, String) {
  // BSD vs GNU detection based on platform
  if platform == "macos" {
    ("bsd", "bsd", "bsd", "bsd")
  } else {
    ("gnu", "gnu", "gnu", "gnu")
  }
}

async fn detect_available_tools() -> Array[String] {
  let tools = [
    "jq", "yq", "rg", "fd", "bat", "eza", "delta",
    "docker", "kubectl", "terraform",
    "git", "gh", "curl", "wget", "python3", "node", "deno", "bun",
  ]
  let script = StringBuilder::new()
  for tool in tools {
    script.write_string("command -v \{tool} >/dev/null 2>&1 && echo \{tool}; ")
  }
  let (_, output) = @process.collect_output_merged("sh", ["-c", script.to_string()])
  let text = try { output.text() } catch { _ => "" }
  let found : Array[String] = []
  for line in text.split("\n") {
    let s = line.to_string().trim().to_string()
    if s != "" {
      found.push(s)
    }
  }
  found
}

async fn detect_clipboard(platform : String) -> String {
  if platform == "macos" {
    return "pbcopy"
  }
  let wayland = @sys.get_env_var("WAYLAND_DISPLAY")
  if wayland.is_some() {
    // Check wl-copy
    let (code, _) = @process.collect_output_merged("sh", ["-c", "command -v wl-copy"])
    if code == 0 { return "wl-copy" }
  }
  let (code, _) = @process.collect_output_merged("sh", ["-c", "command -v xclip"])
  if code == 0 { return "xclip" }
  let (code, _) = @process.collect_output_merged("sh", ["-c", "command -v xsel"])
  if code == 0 { return "xsel" }
  ""
}

async fn detect_pkg_manager(platform : String) -> String {
  if platform == "macos" {
    let (code, _) = @process.collect_output_merged("sh", ["-c", "command -v brew"])
    if code == 0 { return "brew" }
    return ""
  }
  let managers = ["apt", "dnf", "pacman", "apk"]
  for mgr in managers {
    let (code, _) = @process.collect_output_merged("sh", ["-c", "command -v \{mgr}"])
    if code == 0 { return mgr }
  }
  ""
}

async fn load_config() -> @lib.Config {
  // XDG Base Directory support
  let config_dir = match @sys.get_env_var("XDG_CONFIG_HOME") {
    Some(dir) => "\{dir}/nai"
    None => {
      let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
      "\{home}/.config/nai"
    }
  }
  let path = "\{config_dir}/config.json"
  try {
    let content = @fs.read_file(path).text()
    let json = @json.parse!(content)
    @lib.parse_config(json)
  } catch {
    _ => @lib.default_config()
  }
}

async fn load_history(shell : String, depth : Int) -> Array[String] {
  if depth <= 0 {
    return []
  }
  let path = @lib.get_history_path(shell)
  if path == "" {
    return []
  }
  try {
    let content = @fs.read_file(path).text()
    @lib.parse_history(shell, content, depth~)
  } catch {
    _ => []
  }
}

async fn handle_init(shell : String, config : @lib.Config) -> Unit {
  let script = @lib.generate_shell_script(shell, keybind=config.keybind)
  if script == "" {
    eprintln("Error: unsupported shell '\{shell}'. Supported: zsh, bash, fish")
    return
  }
  let config_dir = match @sys.get_env_var("XDG_CONFIG_HOME") {
    Some(dir) => "\{dir}/nai"
    None => {
      let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
      "\{home}/.config/nai"
    }
  }
  // Create directory
  try {
    let (_, _) = @process.collect_output_merged("mkdir", ["-p", config_dir])
  } catch { _ => () }
  let home = match @sys.get_env_var("HOME") { Some(h) => h; None => "" }
  let file_path = @lib.shell_init_path(shell).replace(old="~", new=home)
  let f = @fs.create(file_path, permission=0o644)
  f.write(script)
  f.close()
  let rc = @lib.shell_rc_file(shell)
  let source_path = @lib.shell_init_path(shell)
  eprintln("Shell integration installed to \{source_path}")
  eprintln("Add this line to your \{rc}:")
  eprintln("  source \{source_path}")
}
```

Update `async fn main` to use the new functions:

```moonbit
async fn main {
  let raw_args = @sys.get_cli_args()
  let args = @lib.parse_args(raw_args)

  if args.help { print_help(); return }
  if args.version { print_version(); return }

  // Load config
  let config = load_config()

  // Handle --init
  if args.init_shell != "" {
    handle_init(args.init_shell, config)
    return
  }

  // Detect environment
  let os = detect_os()
  let shell = detect_shell()
  let cwd = detect_cwd()
  let platform = detect_platform()
  let (find_v, sed_v, date_v, stat_v) = detect_tool_variants(platform)
  let available = detect_available_tools()
  let clipboard = detect_clipboard(platform)
  let pkg_mgr = detect_pkg_manager(platform)

  // Load history
  let history_depth = if args.no_history {
    0
  } else if args.history_depth >= 0 {
    args.history_depth
  } else {
    config.history_depth
  }
  let history = load_history(shell, history_depth)

  let env : @lib.Environment = {
    os, shell, cwd, platform, pkg_manager: pkg_mgr,
    clipboard, find_variant: find_v, sed_variant: sed_v,
    date_variant: date_v, stat_variant: stat_v,
    available_tools: available, history,
  }

  // Resolve provider (use config for defaults)
  let provider_name = resolve_provider_name(args)
  let api_key = get_api_key(provider_name)
  let provider = @lib.build_provider(name=provider_name, model=args.model, api_key~)

  eprintln("\u001b[2mProvider: \{provider_name} (\{provider.model})\u001b[0m")

  let system = @lib.build_system_prompt(env)

  if args.explain {
    let prompt = @lib.build_explain_prompt(args.query)
    let explanation = generate(provider, provider_name, system, prompt)
    eprintln(explanation)
    return
  }

  let command = generate(provider, provider_name, system, args.query)

  let report = @lib.analyze_safety(command)
  let warning = @lib.format_warnings(report)
  if warning != "" { eprintln(warning) }

  println(command)

  if args.exec {
    if report.is_dangerous {
      eprintln("\u001b[1;31m⛔ Execution blocked — command flagged as dangerous.\u001b[0m")
      return
    }
    let confirmed = read_confirmation()
    if confirmed {
      let (_, output) = @process.collect_output_merged("sh", ["-c", command])
      let text = try { output.text() } catch { _ => "" }
      eprintln(text)
    } else {
      eprintln("Cancelled.")
    }
  }
}
```

- [ ] **Step 2: Update help text to include new flags**

Add the new flags to `print_help()`:

```
    $|      --history-depth N  Number of history entries to include (default: 10)
    $|      --no-history       Disable shell history context
    $|      --init <shell>     Generate shell integration (zsh, bash, fish)
```

- [ ] **Step 3: Build and fix compilation errors**

Run: `moon build --target native 2>&1`

This will likely need debugging. Key areas:
- `@fs.write_string` may not exist — use `@fs.create` + `write` instead
- `Option.or` may need different API
- `@json.parse!` in async context
- `build_system_prompt` signature change will cause compile errors in main.mbt

Fix all errors iteratively until build succeeds.

- [ ] **Step 4: Test help and version**

Run: `./_build/native/debug/build/main/main.exe --help`
Expected: Help text includes new flags

Run: `./_build/native/debug/build/main/main.exe --version`
Expected: `nai 0.1.0`

- [ ] **Step 5: Test with a query (verify env detection works)**

Run: `./_build/native/debug/build/main/main.exe --provider openai -m gpt-4.1-nano "find all go files"`
Expected: Generated command printed; stderr shows provider info

- [ ] **Step 6: Run full test suite**

Run: `moon test --target native`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/main/main.mbt src/main/moon.pkg.json
git commit -m "feat: wire up environment detection, config, history, and --init in main"
```

---

## Task 8: End-to-End Testing

**Files:** No new files — manual verification

- [ ] **Step 1: Test environment detection in prompt**

Run with `--explain` to see what environment info the LLM receives:

```sh
eval "$(direnv export bash 2>/dev/null)" && ./_build/native/debug/build/main/main.exe --provider openai -m gpt-4.1-nano "list files"
```

Expected: Command generated using correct platform tools

- [ ] **Step 2: Test history context**

```sh
# Run a few commands first, then:
eval "$(direnv export bash 2>/dev/null)" && ./_build/native/debug/build/main/main.exe --provider openai -m gpt-4.1-nano "do the same thing but for python files"
```

Expected: LLM considers recent history when generating

- [ ] **Step 3: Test --no-history**

```sh
eval "$(direnv export bash 2>/dev/null)" && ./_build/native/debug/build/main/main.exe --provider openai -m gpt-4.1-nano --no-history "list files"
```

Expected: Works without history context

- [ ] **Step 4: Test --init**

```sh
./_build/native/debug/build/main/main.exe --init zsh
```

Expected: Creates `~/.config/nai/nai.zsh` and prints source instruction

- [ ] **Step 5: Verify shell integration works**

```sh
source ~/.config/nai/nai.zsh
# Press Ctrl+] and type a query
```

Expected: Generated command appears in command line buffer

- [ ] **Step 6: Test config file**

Create `~/.config/nai/config.json` with custom settings, verify they are used.

- [ ] **Step 7: Run full test suite**

Run: `moon test --target native`
Expected: All tests PASS

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "feat: complete Phase 2 — smart context and shell integration"
```

---

## Summary

| Task | Deliverable | Tests |
|---|---|---|
| 1 | Environment type + build_env_prompt | 6 tests |
| 2 | History parsing (zsh/bash/fish) + privacy filter | 12 tests |
| 3 | CLI args extension (--history-depth, --no-history, --init) | 4+ tests |
| 4 | Config file parsing with defaults | 5 tests |
| 5 | Shell init script generation (zsh/bash/fish) | 5 tests |
| 6 | Update prompt.mbt to use Environment | 3 tests |
| 7 | Main orchestrator wiring | Build verification |
| 8 | End-to-end testing | Manual verification |
