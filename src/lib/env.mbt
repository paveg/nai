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
  if !(env.available_tools.is_empty()) {
    let tools_str = env.available_tools.join(", ")
    buf.write_string("- Available: \{tools_str}\n")
  }
  buf.write_string(
    "\nUse available tools when they are better suited. For example, prefer 'rg' over 'grep' if available.\n",
  )
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
