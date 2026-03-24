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
