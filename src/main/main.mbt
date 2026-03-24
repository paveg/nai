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
    $|  -e, --exec       Execute the generated command after confirmation
    $|      --explain    Explain the generated command in detail
    $|  -p, --provider   Provider: ollama, openai, claude (default: auto-detect)
    $|  -m, --model      Model override (uses provider default if omitted)
    $|  -h, --help       Show this help
    $|  -V, --version    Show version
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
  let json = try { result.json() } catch {
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

  let os = detect_os()
  let shell = detect_shell()
  let cwd = detect_cwd()

  let provider_name = resolve_provider_name(args)
  let api_key = get_api_key(provider_name)
  let provider = @lib.build_provider(
    name=provider_name,
    model=args.model,
    api_key~,
  )

  eprintln("\u001b[2mProvider: \{provider_name} (\{provider.model})\u001b[0m")

  if args.explain {
    let prompt = @lib.build_explain_prompt(args.query)
    let system = @lib.build_system_prompt(os~, shell~, cwd~)
    let explanation = generate(provider, provider_name, system, prompt)
    eprintln(explanation)
    return
  }

  let system = @lib.build_system_prompt(os~, shell~, cwd~)
  let command = generate(provider, provider_name, system, args.query)

  let report = @lib.analyze_safety(command)
  let warning = @lib.format_warnings(report)
  if warning != "" {
    eprintln(warning)
  }

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
