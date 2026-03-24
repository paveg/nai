const VERSION : String = "0.1.0"

async fn eprint(s : String) -> Unit {
  @stdio.stderr.write(s)
}

async fn eprintln(s : String) -> Unit {
  @stdio.stderr.write(s + "\n")
}

async fn print_help() -> Unit {
  let help =
    $|nai v\{VERSION} — AI shell command generator
    $|
    $|Usage: nai [OPTIONS] <QUERY>
    $|
    $|Arguments:
    $|  <QUERY>     Describe what you want to do in natural language
    $|
    $|Options:
    $|  -e, --exec           Execute the generated command after confirmation
    $|      --explain        Explain the generated command in detail
    $|  -p, --provider       Provider: ollama, openai, claude (default: auto-detect)
    $|  -m, --model          Model override (uses provider default if omitted)
    $|      --history-depth N  Number of history entries to include (default: 10)
    $|      --no-history     Disable shell history context
    $|      --init <shell>   Generate shell integration (zsh, bash, fish)
    $|  -h, --help           Show this help
    $|  -V, --version        Show version
  eprintln(help)
}

async fn print_version() -> Unit {
  eprintln("nai \{VERSION}")
}

async fn detect_os() -> String {
  try {
    let (_, output) = @process.collect_output_merged("sw_vers", ["-productVersion"])
    let ver = output.text().trim().to_string()
    "macOS \{ver}"
  } catch {
    _ =>
      try {
        let content = @fs.read_file("/etc/os-release").text()
        for line in content.split("\n") {
          let s = line.to_string()
          if s.has_prefix("PRETTY_NAME=") {
            return s[12:].to_string().trim().to_string().replace(old="\"", new="")
          }
        }
        "Linux"
      } catch {
        _ => "Unknown"
      }
  }
}

fn detect_shell() -> String {
  match @sys.get_env_var("SHELL") {
    Some(shell) => {
      let parts = shell.split("/").collect()
      parts[parts.length() - 1].to_string()
    }
    None => "sh"
  }
}

fn detect_cwd() -> String {
  match @sys.get_env_var("PWD") {
    Some(pwd) => pwd
    None => "."
  }
}

async fn detect_platform() -> String {
  try {
    let (_, _) = @process.collect_output_merged("sw_vers", ["-productVersion"])
    "macos"
  } catch {
    _ => "linux"
  }
}

fn detect_tool_variants(
  platform : String
) -> (String, String, String, String) {
  if platform == "macos" {
    ("bsd", "bsd", "bsd", "bsd")
  } else {
    ("gnu", "gnu", "gnu", "gnu")
  }
}

async fn detect_available_tools() -> Array[String] {
  let tools = [
    "jq", "yq", "rg", "fd", "bat", "eza", "delta", "docker", "kubectl",
    "terraform", "git", "gh", "curl", "wget", "python3", "node", "deno", "bun",
  ]
  let buf = StringBuilder::new()
  for tool in tools {
    buf.write_string("command -v \{tool} >/dev/null 2>&1 && echo \{tool}; ")
  }
  let (_, output) = @process.collect_output_merged(
    "sh",
    ["-c", buf.to_string()],
  )
  let text = try {
    output.text()
  } catch {
    _ => ""
  }
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
  match wayland {
    Some(_) => {
      let (code, _) = @process.collect_output_merged(
        "sh",
        ["-c", "command -v wl-copy"],
      )
      if code == 0 {
        return "wl-copy"
      }
    }
    None => ()
  }
  let (code, _) = @process.collect_output_merged(
    "sh",
    ["-c", "command -v xclip"],
  )
  if code == 0 {
    return "xclip"
  }
  let (code2, _) = @process.collect_output_merged(
    "sh",
    ["-c", "command -v xsel"],
  )
  if code2 == 0 {
    return "xsel"
  }
  ""
}

async fn detect_pkg_manager(platform : String) -> String {
  if platform == "macos" {
    let (code, _) = @process.collect_output_merged(
      "sh",
      ["-c", "command -v brew"],
    )
    if code == 0 {
      return "brew"
    }
    return ""
  }
  let managers = ["apt", "dnf", "pacman", "apk"]
  for mgr in managers {
    let (code, _) = @process.collect_output_merged(
      "sh",
      ["-c", "command -v \{mgr}"],
    )
    if code == 0 {
      return mgr
    }
  }
  ""
}

async fn load_config() -> @lib.Config {
  let config_dir = match @sys.get_env_var("XDG_CONFIG_HOME") {
    Some(dir) => "\{dir}/nai"
    None => {
      let home = match @sys.get_env_var("HOME") {
        Some(h) => h
        None => ""
      }
      "\{home}/.config/nai"
    }
  }
  let path = "\{config_dir}/config.json"
  try {
    let content = @fs.read_file(path).text()
    let json = @json.parse(content)
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
    eprintln(
      "Error: unsupported shell '\{shell}'. Supported: zsh, bash, fish",
    )
    return
  }
  let config_dir = match @sys.get_env_var("XDG_CONFIG_HOME") {
    Some(dir) => "\{dir}/nai"
    None => {
      let home = match @sys.get_env_var("HOME") {
        Some(h) => h
        None => ""
      }
      "\{home}/.config/nai"
    }
  }
  // Create directory
  try {
    @fs.mkdir(config_dir, permission=0o755, recursive=true)
  } catch {
    _ => ()
  }
  let home = match @sys.get_env_var("HOME") {
    Some(h) => h
    None => ""
  }
  let file_path = @lib.shell_init_path(shell).replace(old="~", new=home)
  @fs.write_file(file_path, script, create=0o644, truncate=true)
  let source_path = @lib.shell_init_path(shell)
  let rc = @lib.shell_rc_file(shell)
  eprintln("Shell integration installed to \{source_path}")
  eprintln("Add this line to your \{rc}:")
  eprintln("  source \{source_path}")
}

async fn resolve_provider_name(args : @lib.CliArgs) -> String {
  if args.provider != "auto" {
    return args.provider
  }
  let ollama_available = try {
    let (resp, _) = @http.get("http://localhost:11434/api/version")
    resp.code >= 200 && resp.code < 300
  } catch {
    _ => false
  }
  if ollama_available {
    return "ollama"
  }
  let env = @sys.get_env_vars()
  if env.contains("OPENAI_API_KEY") {
    return "openai"
  }
  if env.contains("ANTHROPIC_API_KEY") {
    return "claude"
  }
  "ollama"
}

fn get_api_key(provider_name : String) -> String {
  match provider_name {
    "openai" =>
      match @sys.get_env_var("OPENAI_API_KEY") {
        Some(key) => key
        None => abort("Error: OPENAI_API_KEY environment variable not set")
      }
    "claude" =>
      match @sys.get_env_var("ANTHROPIC_API_KEY") {
        Some(key) => key
        None => abort("Error: ANTHROPIC_API_KEY environment variable not set")
      }
    _ => "ollama"
  }
}

async fn generate(
  provider : @lib.Provider,
  provider_name : String,
  system : String,
  user : String
) -> String {
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
  eprintln("\u001b[2mThinking...\u001b[0m")
  let (response, result) = @http.post(endpoint, body, headers=provider.headers)
  guard response.code >= 200 && response.code < 300 else {
    let error_text = try { result.text() } catch { _ => "" }
    abort("API error: \{response.code} \{response.reason}\n\{error_text}")
  }
  let json = try {
    result.json()
  } catch {
    _ => abort("Failed to parse API response as JSON")
  }
  let content = if provider_name == "claude" {
    @lib.extract_claude_content(json)
  } else {
    @lib.extract_content(json)
  }
  content.trim().to_string()
}

async fn read_confirmation() -> Bool {
  eprint("\u001b[1;33mExecute this command? [y/N]\u001b[0m ")
  let line = @stdio.stdin.read_until("\n")
  match line {
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
    os,
    shell,
    cwd,
    platform,
    pkg_manager: pkg_mgr,
    clipboard,
    find_variant: find_v,
    sed_variant: sed_v,
    date_variant: date_v,
    stat_variant: stat_v,
    available_tools: available,
    history,
  }

  // Resolve provider
  let provider_name = resolve_provider_name(args)
  let api_key = get_api_key(provider_name)
  let provider = @lib.build_provider(
    name=provider_name,
    model=args.model,
    api_key~,
  )

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
  if warning != "" {
    eprintln(warning)
  }

  println(command)

  if args.exec {
    if report.is_dangerous {
      eprintln(
        "\u001b[1;31m⛔ Execution blocked — command flagged as dangerous.\u001b[0m",
      )
      return
    }
    let confirmed = read_confirmation()
    if confirmed {
      let (_, output) = @process.collect_output_merged("sh", ["-c", command])
      let text = try {
        output.text()
      } catch {
        _ => ""
      }
      eprintln(text)
    } else {
      eprintln("Cancelled.")
    }
  }
}
