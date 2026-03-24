///|
test "generate zsh script" {
  let script = generate_shell_script("zsh", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("vared"))
  assert_true(script.contains("BUFFER="))
  assert_true(script.contains("bindkey"))
  assert_true(script.contains("^]"))
}

///|
test "generate bash script" {
  let script = generate_shell_script("bash", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("READLINE_LINE"))
  assert_true(script.contains("bind"))
  assert_true(script.contains("^]"))
}

///|
test "generate fish script" {
  let script = generate_shell_script("fish", keybind="^]")
  assert_true(script.contains("_nai_widget"))
  assert_true(script.contains("commandline"))
  assert_true(script.contains("bind"))
}

///|
test "generate unknown shell returns empty" {
  let script = generate_shell_script("unknown", keybind="^]")
  assert_eq(script, "")
}

///|
test "generate zsh script with custom keybind" {
  let script = generate_shell_script("zsh", keybind="^G")
  assert_true(script.contains("^G"))
  assert_true(!script.contains("^]"))
}
