# nai Phase 1 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working CLI that takes natural language input, sends it to Ollama (OpenAI-compatible endpoint), and outputs a shell one-liner to stdout — with safety warnings on stderr.

**Architecture:** Single-package MoonBit native app using `moonbitlang/async` for HTTP and process execution. CLI args parsed with a lightweight hand-rolled parser (no external dep for MVP). Provider logic, prompt building, and safety checking are pure functions tested independently. The async entry point orchestrates the pipeline.

**Tech Stack:** MoonBit (native backend), `moonbitlang/async` (HTTP/process/fs), `moonbitlang/x` (env vars)

---

## File Structure

```
nai/
├── moon.mod.json              # Module: paveg/nai, deps: moonbitlang/async, moonbitlang/x
├── src/
│   ├── lib/
│   │   ├── moon.pkg.json      # Library package (testable, not main)
│   │   ├── types.mbt          # Shared types: CliArgs, Provider, DangerReport
│   │   ├── cli.mbt            # parse_args(): String -> CliArgs
│   │   ├── cli_test.mbt       # Tests for CLI parsing
│   │   ├── safety.mbt         # analyze_safety(): String -> DangerReport
│   │   ├── safety_test.mbt    # Tests for safety checker
│   │   ├── prompt.mbt         # build_system_prompt(): (os, shell, cwd) -> String
│   │   └── prompt_test.mbt    # Tests for prompt builder
│   └── main/
│       ├── moon.pkg.json      # is-main: true, imports lib + async packages
│       └── main.mbt           # async fn main: orchestrate pipeline
├── docs/
│   └── superpowers/
│       └── plans/
│           └── 2026-03-24-nai-phase1-mvp.md
└── README.md
```

**Key design decision:** Split into `lib` (pure, testable) and `main` (async, IO-bound). This lets us TDD all parsing/safety/prompt logic without async test complexity. The `main` package is thin glue.

---

## Task 1: Project Scaffolding

**Files:**
- Create: `moon.mod.json`
- Create: `src/lib/moon.pkg.json`
- Create: `src/main/moon.pkg.json`
- Create: `src/lib/types.mbt`
- Create: `src/main/main.mbt`

- [ ] **Step 1: Create moon.mod.json**

```json
{
  "name": "paveg/nai",
  "version": "0.1.0",
  "preferred-target": "native",
  "deps": {
    "moonbitlang/async": "0.16.8",
    "moonbitlang/x": "0.4.6"
  },
  "source": "src"
}
```

- [ ] **Step 2: Create src/lib/moon.pkg.json**

```json
{
  "import": [
    "moonbitlang/x/sys"
  ]
}
```

- [ ] **Step 3: Create src/lib/types.mbt**

Define all shared types used across the project:

```moonbit
pub struct CliArgs {
  query : String
  exec : Bool
  explain : Bool
  provider : String  // "auto", "ollama", "openai", "claude"
  model : String     // "" means use provider default
  help : Bool
  version : Bool
} derive(Show, Eq)

pub struct Provider {
  base_url : String
  headers : Map[String, String]
  model : String
} derive(Show)

pub struct DangerReport {
  is_dangerous : Bool
  warnings : Array[String]
} derive(Show, Eq)
```

- [ ] **Step 4: Create src/main/moon.pkg.json**

```json
{
  "is-main": true,
  "import": [
    "paveg/nai/lib",
    "moonbitlang/async/http",
    "moonbitlang/async/fs",
    "moonbitlang/async/process",
    "moonbitlang/x/sys"
  ]
}
```

- [ ] **Step 5: Create src/main/main.mbt with minimal placeholder**

```moonbit
async fn main {
  println("nai v0.1.0")
}
```

- [ ] **Step 6: Install dependencies and verify build**

Run: `moon update && moon build --target native`
Expected: Build succeeds, binary at `target/native/release/build/src/main/main`

- [ ] **Step 7: Verify binary runs**

Run: `./target/native/release/build/src/main/main`
Expected: Prints `nai v0.1.0`

- [ ] **Step 8: Commit**

```bash
git init
git add moon.mod.json src/
git commit -m "feat: scaffold nai project with MoonBit native backend"
```

---

## Task 2: CLI Argument Parser

**Files:**
- Create: `src/lib/cli.mbt`
- Create: `src/lib/cli_test.mbt`

- [ ] **Step 1: Write failing tests for CLI parsing**

File: `src/lib/cli_test.mbt`

```moonbit
test "parse basic query" {
  let args = parse_args(["nai", "find large files"])
  assert_eq!(args.query, "find large files")
  assert_eq!(args.exec, false)
  assert_eq!(args.explain, false)
  assert_eq!(args.provider, "auto")
  assert_eq!(args.model, "")
  assert_eq!(args.help, false)
  assert_eq!(args.version, false)
}

test "parse --exec flag" {
  let args = parse_args(["nai", "--exec", "disk usage sorted"])
  assert_eq!(args.exec, true)
  assert_eq!(args.query, "disk usage sorted")
}

test "parse -e short flag" {
  let args = parse_args(["nai", "-e", "disk usage sorted"])
  assert_eq!(args.exec, true)
  assert_eq!(args.query, "disk usage sorted")
}

test "parse --explain flag" {
  let args = parse_args(["nai", "--explain", "find . -name '*.rs'"])
  assert_eq!(args.explain, true)
  assert_eq!(args.query, "find . -name '*.rs'")
}

test "parse --provider flag" {
  let args = parse_args(["nai", "--provider", "openai", "query here"])
  assert_eq!(args.provider, "openai")
  assert_eq!(args.query, "query here")
}

test "parse -p short flag" {
  let args = parse_args(["nai", "-p", "claude", "query here"])
  assert_eq!(args.provider, "claude")
  assert_eq!(args.query, "query here")
}

test "parse --model flag" {
  let args = parse_args(["nai", "-m", "gpt-4o", "my query"])
  assert_eq!(args.model, "gpt-4o")
  assert_eq!(args.query, "my query")
}

test "parse --help flag" {
  let args = parse_args(["nai", "--help"])
  assert_eq!(args.help, true)
}

test "parse -h flag" {
  let args = parse_args(["nai", "-h"])
  assert_eq!(args.help, true)
}

test "parse --version flag" {
  let args = parse_args(["nai", "--version"])
  assert_eq!(args.version, true)
}

test "parse -V flag" {
  let args = parse_args(["nai", "-V"])
  assert_eq!(args.version, true)
}

test "parse combined flags" {
  let args = parse_args(["nai", "-e", "-p", "ollama", "-m", "qwen2.5-coder:7b", "find big files"])
  assert_eq!(args.exec, true)
  assert_eq!(args.provider, "ollama")
  assert_eq!(args.model, "qwen2.5-coder:7b")
  assert_eq!(args.query, "find big files")
}

test "parse multi-word query without quotes" {
  let args = parse_args(["nai", "find", "all", "large", "files"])
  assert_eq!(args.query, "find all large files")
}

test "parse empty args shows help" {
  let args = parse_args(["nai"])
  assert_eq!(args.help, true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `parse_args` not defined

- [ ] **Step 3: Implement parse_args**

File: `src/lib/cli.mbt`

```moonbit
pub fn parse_args(raw : Array[String]) -> CliArgs {
  let mut exec = false
  let mut explain = false
  let mut provider = "auto"
  let mut model = ""
  let mut help = false
  let mut version = false
  let positional : Array[String] = []
  let mut i = 1  // skip program name
  while i < raw.length() {
    let arg = raw[i]
    match arg {
      "--exec" | "-e" => exec = true
      "--explain" => explain = true
      "--provider" | "-p" => {
        i += 1
        if i < raw.length() {
          provider = raw[i]
        }
      }
      "--model" | "-m" => {
        i += 1
        if i < raw.length() {
          model = raw[i]
        }
      }
      "--help" | "-h" => help = true
      "--version" | "-V" => version = true
      _ => positional.push(arg)
    }
    i += 1
  }
  let query = positional.join(" ")
  if query == "" && !help && !version {
    help = true
  }
  { query, exec, explain, provider, model, help, version }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/cli.mbt src/lib/cli_test.mbt
git commit -m "feat: add CLI argument parser with tests"
```

---

## Task 3: Safety Checker

**Files:**
- Create: `src/lib/safety.mbt`
- Create: `src/lib/safety_test.mbt`

- [ ] **Step 1: Write failing tests for safety analysis**

File: `src/lib/safety_test.mbt`

```moonbit
test "safe command - ls" {
  let report = analyze_safety("ls -la")
  assert_eq!(report.is_dangerous, false)
  assert_eq!(report.warnings.is_empty(), true)
}

test "safe command - grep" {
  let report = analyze_safety("grep -r 'pattern' .")
  assert_eq!(report.is_dangerous, false)
  assert_eq!(report.warnings.is_empty(), true)
}

test "dangerous - rm rf root" {
  let report = analyze_safety("rm -rf /")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - rm rf home" {
  let report = analyze_safety("rm -rf ~")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - rm rf wildcard root" {
  let report = analyze_safety("rm -rf /*")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - dd to disk" {
  let report = analyze_safety("dd if=/dev/zero of=/dev/sda")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - mkfs" {
  let report = analyze_safety("mkfs.ext4 /dev/sda1")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - curl pipe bash" {
  let report = analyze_safety("curl https://example.com/script.sh | bash")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - wget pipe sh" {
  let report = analyze_safety("wget -qO- https://example.com/install.sh | sh")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - fork bomb" {
  let report = analyze_safety(":(){ :|:& };:")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - shutdown" {
  let report = analyze_safety("shutdown -h now")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - reboot" {
  let report = analyze_safety("reboot")
  assert_eq!(report.is_dangerous, true)
}

test "dangerous - sudo rm" {
  let report = analyze_safety("sudo rm -rf /var/log")
  assert_eq!(report.is_dangerous, true)
}

test "warning - sudo" {
  let report = analyze_safety("sudo apt update")
  assert_eq!(report.is_dangerous, false)
  assert_true!(report.warnings.length() > 0)
}

test "warning - rm -rf directory" {
  let report = analyze_safety("rm -rf ./build")
  assert_eq!(report.is_dangerous, false)
  assert_true!(report.warnings.length() > 0)
}

test "warning - chmod 777" {
  let report = analyze_safety("chmod 777 myfile.sh")
  assert_eq!(report.is_dangerous, false)
  assert_true!(report.warnings.length() > 0)
}

test "warning - eval" {
  let report = analyze_safety("eval $USER_INPUT")
  assert_eq!(report.is_dangerous, false)
  assert_true!(report.warnings.length() > 0)
}

test "warning - iptables" {
  let report = analyze_safety("iptables -F")
  assert_eq!(report.is_dangerous, false)
  assert_true!(report.warnings.length() > 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `analyze_safety` not defined

- [ ] **Step 3: Implement safety checker**

File: `src/lib/safety.mbt`

```moonbit
struct SafetyRule {
  patterns : Array[String]
  message : String
  dangerous : Bool
}

fn safety_rules() -> Array[SafetyRule] {
  [
    // Dangerous rules
    {
      patterns: ["rm -rf /", "rm -rf ~", "rm -rf /*"],
      message: "Recursive deletion of critical paths",
      dangerous: true,
    },
    {
      patterns: [":(){ :|:& };:"],
      message: "Fork bomb detected",
      dangerous: true,
    },
    {
      patterns: ["> /dev/sda", "dd if=", "mkfs."],
      message: "Direct disk write operation",
      dangerous: true,
    },
    {
      patterns: ["curl | sh", "curl | bash", "wget | sh", "wget | bash",
                  "| bash", "| sh"],
      message: "Remote script execution via pipe",
      dangerous: true,
    },
    {
      patterns: ["sudo rm", "sudo dd", "sudo mkfs"],
      message: "Destructive command with elevated privileges",
      dangerous: true,
    },
    {
      patterns: ["shutdown", "reboot", "halt", "poweroff"],
      message: "System shutdown or reboot",
      dangerous: true,
    },
    // Warning rules
    {
      patterns: ["sudo "],
      message: "Command requires elevated privileges",
      dangerous: false,
    },
    {
      patterns: ["rm -rf", "rm -r "],
      message: "Recursive deletion",
      dangerous: false,
    },
    {
      patterns: ["chmod 777"],
      message: "Overly permissive file permissions",
      dangerous: false,
    },
    {
      patterns: ["eval ", "exec "],
      message: "Dynamic command execution",
      dangerous: false,
    },
    {
      patterns: ["iptables", "ufw "],
      message: "Firewall configuration change",
      dangerous: false,
    },
  ]
}

pub fn analyze_safety(command : String) -> DangerReport {
  let lower = command.to_lower()
  let warnings : Array[String] = []
  let mut is_dangerous = false
  let rules = safety_rules()
  for rule in rules {
    let mut matched = false
    for pattern in rule.patterns {
      if lower.contains(pattern) {
        matched = true
        break
      }
    }
    if matched {
      warnings.push(rule.message)
      if rule.dangerous {
        is_dangerous = true
      }
    }
  }
  { is_dangerous, warnings }
}

pub fn format_warnings(report : DangerReport) -> String {
  if report.warnings.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  if report.is_dangerous {
    buf.write_string("\x1b[1;31m⛔ DANGEROUS COMMAND DETECTED\x1b[0m\n")
  } else {
    buf.write_string("\x1b[1;33m⚠ Warning: potentially dangerous command\x1b[0m\n")
  }
  for w in report.warnings {
    buf.write_string("  → \{w}\n")
  }
  buf.to_string()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/safety.mbt src/lib/safety_test.mbt
git commit -m "feat: add safety checker with dangerous/warning pattern detection"
```

---

## Task 4: System Prompt Builder

**Files:**
- Create: `src/lib/prompt.mbt`
- Create: `src/lib/prompt_test.mbt`

- [ ] **Step 1: Write failing tests for prompt builder**

File: `src/lib/prompt_test.mbt`

```moonbit
test "build system prompt contains os info" {
  let prompt = build_system_prompt(os="macOS 15.2", shell="zsh", cwd="/Users/test")
  assert_true!(prompt.contains("macOS 15.2"))
  assert_true!(prompt.contains("zsh"))
  assert_true!(prompt.contains("/Users/test"))
}

test "build system prompt contains rules" {
  let prompt = build_system_prompt(os="Linux", shell="bash", cwd="/home/user")
  assert_true!(prompt.contains("one line of shell command"))
  assert_true!(prompt.contains("POSIX"))
}

test "build explain prompt" {
  let prompt = build_explain_prompt("find . -name '*.rs' -mtime -7")
  assert_true!(prompt.contains("find . -name '*.rs' -mtime -7"))
  assert_true!(prompt.contains("explain"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — `build_system_prompt` not defined

- [ ] **Step 3: Implement prompt builder**

File: `src/lib/prompt.mbt`

```moonbit
pub fn build_system_prompt(
  os~ : String,
  shell~ : String,
  cwd~ : String
) -> String {
  $|You are a shell command generator. Given a natural language description,
  $|output ONLY a single shell one-liner. No explanations, no markdown,
  $|no code fences — just the raw command.
  $|
  $|Rules:
  $|- Output exactly one line of shell command
  $|- Valid for: OS=\{os}, Shell=\{shell}
  $|- Current directory: \{cwd}
  $|- Prefer standard POSIX tools
  $|- If ambiguous, choose the safest interpretation
  $|- Do not wrap in backticks or quotes
}

pub fn build_explain_prompt(command : String) -> String {
  $|Explain the following shell command in detail.
  $|Break down each part (command, flags, arguments, pipes).
  $|Be concise but thorough.
  $|
  $|Command: \{command}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/prompt.mbt src/lib/prompt_test.mbt
git commit -m "feat: add system prompt builder with OS/shell/cwd context"
```

---

## Task 5: Provider Construction (Pure Logic)

**Files:**
- Modify: `src/lib/types.mbt` (add provider defaults)
- Create: `src/lib/provider.mbt`
- Create: `src/lib/provider_test.mbt`

- [ ] **Step 1: Write failing tests for provider construction**

File: `src/lib/provider_test.mbt`

```moonbit
test "build ollama provider with defaults" {
  let p = build_provider(name="ollama", model="", api_key="")
  assert_eq!(p.base_url, "http://localhost:11434/v1")
  assert_eq!(p.model, "qwen2.5-coder:7b")
  assert_eq!(p.headers.get("Authorization"), Some("Bearer ollama"))
}

test "build ollama provider with custom model" {
  let p = build_provider(name="ollama", model="llama3:8b", api_key="")
  assert_eq!(p.model, "llama3:8b")
}

test "build openai provider" {
  let p = build_provider(name="openai", model="", api_key="sk-test123")
  assert_eq!(p.base_url, "https://api.openai.com/v1")
  assert_eq!(p.model, "gpt-4o-mini")
  assert_eq!(p.headers.get("Authorization"), Some("Bearer sk-test123"))
}

test "build openai provider with custom model" {
  let p = build_provider(name="openai", model="gpt-4o", api_key="sk-test")
  assert_eq!(p.model, "gpt-4o")
}

test "build claude provider" {
  let p = build_provider(name="claude", model="", api_key="sk-ant-test")
  assert_eq!(p.base_url, "https://api.anthropic.com/v1")
  assert_eq!(p.model, "claude-haiku-4-5-20251001")
  assert_eq!(p.headers.get("x-api-key"), Some("sk-ant-test"))
  assert_eq!(p.headers.get("anthropic-version"), Some("2023-06-01"))
}

test "build request body for openai-compatible" {
  let body = build_request_body(
    provider_name="ollama",
    model="qwen2.5-coder:7b",
    system="You are a helper",
    user="find files",
  )
  let s = body.stringify()
  assert_true!(s.contains("qwen2.5-coder:7b"))
  assert_true!(s.contains("system"))
  assert_true!(s.contains("find files"))
}

test "build request body for claude uses top-level system" {
  let body = build_request_body(
    provider_name="claude",
    model="claude-haiku-4-5-20251001",
    system="You are a helper",
    user="find files",
  )
  let s = body.stringify()
  // Claude format: system is top-level, not in messages
  assert_true!(s.contains("\"system\""))
  assert_true!(s.contains("find files"))
  // messages should only have user role, not system role
  assert_true!(s.contains("\"user\""))
}

test "extract content from openai response" {
  let json = @json.parse(
    #|{"choices":[{"message":{"content":"ls -la"}}]}
  )
  let content = extract_content(json)
  assert_eq!(content, "ls -la")
}

test "extract content from claude response" {
  let json = @json.parse(
    #|{"content":[{"type":"text","text":"ls -la"}]}
  )
  let content = extract_claude_content(json)
  assert_eq!(content, "ls -la")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --target native -p paveg/nai/lib`
Expected: FAIL — functions not defined

- [ ] **Step 3: Implement provider construction**

File: `src/lib/provider.mbt`

```moonbit
pub fn build_provider(
  name~ : String,
  model~ : String,
  api_key~ : String
) -> Provider {
  match name {
    "ollama" => {
      let m = if model == "" { "qwen2.5-coder:7b" } else { model }
      {
        base_url: "http://localhost:11434/v1",
        headers: { "Authorization": "Bearer ollama", "Content-Type": "application/json" },
        model: m,
      }
    }
    "openai" => {
      let m = if model == "" { "gpt-4o-mini" } else { model }
      {
        base_url: "https://api.openai.com/v1",
        headers: { "Authorization": "Bearer \{api_key}", "Content-Type": "application/json" },
        model: m,
      }
    }
    "claude" => {
      let m = if model == "" { "claude-haiku-4-5-20251001" } else { model }
      {
        base_url: "https://api.anthropic.com/v1",
        headers: {
          "x-api-key": api_key,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json",
        },
        model: m,
      }
    }
    _ => {
      // Default to ollama
      build_provider(name="ollama", model~, api_key~)
    }
  }
}

pub fn build_request_body(
  provider_name~ : String,
  model~ : String,
  system~ : String,
  user~ : String
) -> Json {
  if provider_name == "claude" {
    // Claude API format: system is top-level
    {
      "model": model,
      "system": system,
      "messages": [
        { "role": "user", "content": user },
      ],
      "max_tokens": 256,
      "temperature": 0.0,
      "stream": false,
    }
  } else {
    // OpenAI-compatible format (Ollama, OpenAI)
    {
      "model": model,
      "messages": [
        { "role": "system", "content": system },
        { "role": "user", "content": user },
      ],
      "max_tokens": 256,
      "temperature": 0.0,
      "stream": false,
    }
  }
}

pub fn extract_content(json : Json) -> String {
  // OpenAI format: choices[0].message.content
  guard json is {
    "choices": [{ "message": { "content": String(content) }, .. }, ..],
    ..
  } else {
    fail("Failed to extract content from API response")
  }
  content
}

pub fn extract_claude_content(json : Json) -> String {
  // Claude format: content[0].text
  guard json is {
    "content": [{ "text": String(text), .. }, ..],
    ..
  } else {
    fail("Failed to extract content from Claude API response")
  }
  text
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --target native -p paveg/nai/lib`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/lib/provider.mbt src/lib/provider_test.mbt
git commit -m "feat: add provider construction and request/response handling"
```

---

## Task 6: Main Orchestrator (Async Integration)

**Files:**
- Modify: `src/main/main.mbt`

- [ ] **Step 1: Implement the full async main pipeline**

File: `src/main/main.mbt`

```moonbit
const VERSION : String = "0.1.0"

fn print_help() -> Unit {
  let help =
    $|nai v\{VERSION} — AI shell command generator
    $|
    $|Usage: nai [OPTIONS] <QUERY>
    $|
    $|Arguments:
    $|  <QUERY>     Describe what you want to do in natural language
    $|
    $|Options:
    $|  -e, --exec       Execute the generated command after confirmation
    $|      --explain    Explain the generated command in detail
    $|  -p, --provider   Provider: ollama, openai, claude (default: auto-detect)
    $|  -m, --model      Model override (uses provider default if omitted)
    $|  -h, --help       Show this help
    $|  -V, --version    Show version
  eprintln(help)
}

fn print_version() -> Unit {
  eprintln("nai \{VERSION}")
}

async fn detect_os() -> String {
  try {
    let (_, output) = @process.collect_output_merged("sw_vers", ["-productVersion"])
    "macOS \{output.text().trim().to_string()}"
  } catch {
    _ =>
      try {
        let content = @fs.read_file("/etc/os-release").text()
        // Extract PRETTY_NAME from os-release
        for line in content.split("\n") {
          if line.to_string().has_prefix("PRETTY_NAME=") {
            return line.to_string()[12:].to_string().trim().to_string().replace(old="\"", new="")
          }
        }
        "Linux"
      } catch {
        _ => "Unknown"
      }
  }
}

fn detect_shell() -> String {
  let env = @sys.get_env_vars()
  match env.get("SHELL") {
    Some(shell) => {
      // Extract shell name from path (e.g., /bin/zsh -> zsh)
      let parts = shell.split("/").collect()
      parts[parts.length() - 1].to_string()
    }
    None => "sh"
  }
}

fn detect_cwd() -> String {
  let env = @sys.get_env_vars()
  match env.get("PWD") {
    Some(pwd) => pwd
    None => "."
  }
}

async fn resolve_provider_name(args : @lib.CliArgs) -> String {
  if args.provider != "auto" {
    return args.provider
  }
  // Auto-detect: try Ollama first
  let ollama_available = try {
    let (resp, _) = @http.get("http://localhost:11434/api/version")
    resp.code >= 200 && resp.code < 300
  } catch {
    _ => false
  }
  if ollama_available {
    return "ollama"
  }
  // Fall back to cloud APIs
  let env = @sys.get_env_vars()
  if env.contains("OPENAI_API_KEY") {
    return "openai"
  }
  if env.contains("ANTHROPIC_API_KEY") {
    return "claude"
  }
  // Default to ollama (will fail with connection error, but that's informative)
  "ollama"
}

fn get_api_key(provider_name : String) -> String {
  let env = @sys.get_env_vars()
  match provider_name {
    "openai" =>
      match env.get("OPENAI_API_KEY") {
        Some(key) => key
        None => {
          eprintln("\x1b[31mError: OPENAI_API_KEY environment variable not set\x1b[0m")
          panic()
        }
      }
    "claude" =>
      match env.get("ANTHROPIC_API_KEY") {
        Some(key) => key
        None => {
          eprintln("\x1b[31mError: ANTHROPIC_API_KEY environment variable not set\x1b[0m")
          panic()
        }
      }
    _ => "ollama"
  }
}

async fn generate(provider : @lib.Provider, provider_name : String, system : String, user : String) -> String {
  let body = @lib.build_request_body(
    provider_name~,
    model=provider.model,
    system~,
    user~,
  )
  let endpoint = if provider_name == "claude" {
    "\{provider.base_url}/messages"
  } else {
    "\{provider.base_url}/chat/completions"
  }
  eprintln("\x1b[2mThinking...\x1b[0m")
  let (response, result) = @http.post(endpoint, body, headers=provider.headers)
  guard response.code >= 200 && response.code < 300 else {
    fail("API error: \{response.code} \{response.reason}")
  }
  let json = result.json()
  let content = if provider_name == "claude" {
    @lib.extract_claude_content(json)
  } else {
    @lib.extract_content(json)
  }
  content.trim().to_string()
}

async fn read_confirmation() -> Bool {
  eprintln("\x1b[1;33mExecute this command? [y/N]\x1b[0m ")
  let input = @stdio.stdin.read_until("\n")
  match input {
    Some(s) => {
      let answer = s.trim().to_string().to_lower()
      answer == "y" || answer == "yes"
    }
    None => false
  }
}

async fn main {
  let raw_args = @sys.get_cli_args()
  let args = @lib.parse_args(raw_args)

  if args.help {
    print_help()
    return
  }
  if args.version {
    print_version()
    return
  }

  // Detect environment
  let os = detect_os()
  let shell = detect_shell()
  let cwd = detect_cwd()

  // Resolve provider
  let provider_name = resolve_provider_name(args)
  let api_key = get_api_key(provider_name)
  let provider = @lib.build_provider(name=provider_name, model=args.model, api_key~)

  eprintln("\x1b[2mProvider: \{provider_name} (\{provider.model})\x1b[0m")

  if args.explain {
    // Explain mode: use explain prompt
    let prompt = @lib.build_explain_prompt(args.query)
    let system = @lib.build_system_prompt(os~, shell~, cwd~)
    let explanation = generate(provider, provider_name, system, prompt)
    eprintln(explanation)
    return
  }

  // Generate command
  let system = @lib.build_system_prompt(os~, shell~, cwd~)
  let command = generate(provider, provider_name, system, args.query)

  // Safety check
  let report = @lib.analyze_safety(command)
  let warning = @lib.format_warnings(report)
  if warning != "" {
    eprintln(warning)
  }

  // Output command to stdout
  println(command)

  // Execute mode
  if args.exec {
    if report.is_dangerous {
      eprintln("\x1b[1;31m⛔ This command is flagged as dangerous. Execution blocked.\x1b[0m")
      eprintln("Copy and run manually if you're sure: \{command}")
      return
    }
    let confirmed = read_confirmation()
    if confirmed {
      let (_, output) = @process.collect_output_merged("sh", ["-c", command])
      eprintln(output.text())
    } else {
      eprintln("Cancelled.")
    }
  }
}
```

**Note:** Key API corrections applied from review: `@sys.get_cli_args()` (not `get_args`), `map.get(key)` (not `map[key]` for Option), `.to_lower()` (not `.to_lowercase()`), `.has_prefix()` (not `.starts_with()`), `@stdio.stdin.read_until("\n")` (not `@io.BufReader`). The `@stdio.stdin` and `@io` APIs may still need adjustment at build time — verify with `moon doc` if build fails.

- [ ] **Step 2: Update src/main/moon.pkg.json with all needed imports**

```json
{
  "is-main": true,
  "import": [
    "paveg/nai/lib",
    "moonbitlang/async/http",
    "moonbitlang/async/fs",
    "moonbitlang/async/process",
    "moonbitlang/async/io",
    "moonbitlang/async/stdio",
    "moonbitlang/x/sys"
  ]
}
```

- [ ] **Step 3: Build and fix any compilation errors**

Run: `moon build --target native 2>&1`
Expected: Successful build. If there are API mismatches (e.g., `@sys.get_args` doesn't exist or has different name), fix by consulting `moon doc` or exploring the package API with `moon info`.

- [ ] **Step 4: Test the binary manually**

Run: `./target/native/release/build/src/main/main --help`
Expected: Help text printed to stderr

Run: `./target/native/release/build/src/main/main --version`
Expected: `nai 0.1.0` printed to stderr

- [ ] **Step 5: Commit**

```bash
git add src/main/main.mbt src/main/moon.pkg.json
git commit -m "feat: wire up async main with provider resolution, generation, and safety"
```

---

## Task 7: End-to-End Smoke Test

**Files:** No new files — manual testing

- [ ] **Step 1: Test with Ollama (if available)**

Run: `./target/native/release/build/src/main/main "find files larger than 100MB"`
Expected: A shell command printed to stdout (e.g., `find . -size +100M`)

- [ ] **Step 2: Test safety warning**

Run: `./target/native/release/build/src/main/main "delete everything in root directory"`
Expected: Command on stdout, danger warning on stderr

- [ ] **Step 3: Test pipe compatibility**

Run: `./target/native/release/build/src/main/main "list files" 2>/dev/null`
Expected: Only the command, no extra output

- [ ] **Step 4: Test provider flag**

Run: `./target/native/release/build/src/main/main --provider openai "list running docker containers"`
Expected: Uses OpenAI API (requires OPENAI_API_KEY set)

- [ ] **Step 5: Run full test suite**

Run: `moon test --target native`
Expected: All unit tests pass

- [ ] **Step 6: Final commit with any fixes**

```bash
git add -A
git commit -m "feat: complete Phase 1 MVP — nai generates shell commands from natural language"
```

---

## Summary of Deliverables

After completing all 7 tasks:

1. `nai` accepts natural language queries and generates shell one-liners
2. Ollama is auto-detected; falls back to OpenAI/Claude via env vars
3. Safety checker warns about dangerous commands on stderr
4. Commands go to stdout (pipe-friendly)
5. `--help`, `--version`, `--provider`, `--model` flags work
6. All pure logic has unit tests (CLI parser, safety checker, prompt builder, provider construction)
7. Project builds with `moon build --target native`
