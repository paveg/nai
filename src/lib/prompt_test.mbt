test "build system prompt contains os info" {
  let env : Environment = {
    os: "macOS 15.2", shell: "zsh", cwd: "/Users/test",
    platform: "macos", pkg_manager: "brew", clipboard: "pbcopy",
    find_variant: "bsd", sed_variant: "bsd", date_variant: "bsd",
    stat_variant: "bsd", available_tools: [],
    history: [], project_type: "",
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
    history: [], project_type: "",
  }
  let prompt = build_system_prompt(env)
  assert_true(prompt.contains("one line of shell command"))
}

test "build explain prompt" {
  let prompt = build_explain_prompt("find . -name '*.rs' -mtime -7")
  assert_true(prompt.contains("find . -name '*.rs' -mtime -7"))
  assert_true(prompt.contains("Explain") || prompt.contains("explain"))
}
