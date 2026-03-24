// Project type detection from directory listing
///|
pub fn detect_project_type(files : Array[String]) -> String {
  for f in files {
    match f {
      "moon.mod.json" => return "moonbit"
      "Cargo.toml" => return "rust"
      "go.mod" => return "go"
      "package.json" => return "node"
      "pyproject.toml" | "setup.py" | "setup.cfg" => return "python"
      "Gemfile" => return "ruby"
      "pom.xml" | "build.gradle" | "build.gradle.kts" => return "java"
      "Package.swift" => return "swift"
      "mix.exs" => return "elixir"
      "deno.json" | "deno.jsonc" => return "deno"
      _ => continue
    }
  }
  ""
}

///|
fn project_desc(project_type : String) -> String {
  match project_type {
    "moonbit" =>
      "MoonBit (source files: *.mbt, build tool: moon, rg does not recognize --type mbt so use -g '*.mbt')"
    "rust" => "Rust (source files: *.rs, build tool: cargo)"
    "go" => "Go (source files: *.go, build tool: go)"
    "node" => "Node.js/TypeScript (source files: *.js, *.ts, *.tsx)"
    "python" => "Python (source files: *.py)"
    "ruby" => "Ruby (source files: *.rb)"
    "java" => "Java/Kotlin (source files: *.java, *.kt)"
    "swift" => "Swift (source files: *.swift)"
    "elixir" => "Elixir (source files: *.ex, *.exs)"
    "deno" => "Deno/TypeScript (source files: *.ts, *.tsx)"
    _ => ""
  }
}

///|
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

///|
pub fn build_env_prompt(env : Environment) -> String {
  let buf = StringBuilder::new()
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
  buf.write_string("\n\nEnvironment:\n")
  buf.write_string("- OS: \{env.os}, Shell: \{env.shell}\n")
  buf.write_string("- Current directory: \{env.cwd}\n")
  let variants = [
    variant_desc("find", env.find_variant),
    variant_desc("sed", env.sed_variant),
    variant_desc("date", env.date_variant),
    variant_desc("stat", env.stat_variant),
  ]
  let variants_str = variants.join(", ")
  buf.write_string("- Platform tools: \{variants_str}\n")
  if env.clipboard != "" {
    buf.write_string("- Clipboard: \{env.clipboard}\n")
  }
  if env.pkg_manager != "" {
    buf.write_string("- Package manager: \{env.pkg_manager}\n")
  }
  if !env.available_tools.is_empty() {
    let tools_str = env.available_tools.join(", ")
    buf.write_string("- Available: \{tools_str}\n")
  }
  // Project context
  if env.project_type != "" {
    let desc = project_desc(env.project_type)
    if desc != "" {
      buf.write_string("- Project: \{desc}\n")
    }
  }

  // Tool preference and style guidelines
  buf.write_string("\nTool preferences (use if available):\n")
  buf.write_string("- Search: rg > grep (use rg -g '*.ext' for file type filtering, not --type)\n")
  buf.write_string("- Find files: fd > find\n")
  buf.write_string("- View files: bat > cat\n")
  buf.write_string("- List files: eza > ls\n")
  buf.write_string("- JSON: jq for JSON processing\n")
  buf.write_string("- Git: gh for GitHub operations\n")
  buf.write_string("\nStyle rules:\n")
  buf.write_string("- Keep it simple. Minimize pipe chains — 2-3 pipes max.\n")
  buf.write_string("- Prefer a single tool's built-in flags over piping to another tool.\n")
  buf.write_string("- Do not use --json output piped to jq when the tool has a simpler text output mode.\n")
  buf.write_string("- For sed on this platform, use the correct variant shown above.\n")
  if !env.history.is_empty() {
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
