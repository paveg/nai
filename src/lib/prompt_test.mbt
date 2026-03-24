test "build system prompt contains os info" {
  let prompt = build_system_prompt(os="macOS 15.2", shell="zsh", cwd="/Users/test")
  assert_true(prompt.contains("macOS 15.2"))
  assert_true(prompt.contains("zsh"))
  assert_true(prompt.contains("/Users/test"))
}

test "build system prompt contains rules" {
  let prompt = build_system_prompt(os="Linux", shell="bash", cwd="/home/user")
  assert_true(prompt.contains("one line of shell command"))
  assert_true(prompt.contains("POSIX"))
}

test "build explain prompt" {
  let prompt = build_explain_prompt("find . -name '*.rs' -mtime -7")
  assert_true(prompt.contains("find . -name '*.rs' -mtime -7"))
  // Check it asks for explanation (case-insensitive check via contains on both variants)
  assert_true(prompt.contains("Explain") || prompt.contains("explain"))
}
