test "parse basic query" {
  let args = parse_args(["nai", "find large files"])
  assert_eq(args.query, "find large files")
  assert_eq(args.exec, false)
  assert_eq(args.explain, false)
  assert_eq(args.provider, "auto")
  assert_eq(args.model, "")
  assert_eq(args.help, false)
  assert_eq(args.version, false)
}

test "parse --exec flag" {
  let args = parse_args(["nai", "--exec", "disk usage sorted"])
  assert_eq(args.exec, true)
  assert_eq(args.query, "disk usage sorted")
}

test "parse -e short flag" {
  let args = parse_args(["nai", "-e", "disk usage sorted"])
  assert_eq(args.exec, true)
  assert_eq(args.query, "disk usage sorted")
}

test "parse --explain flag" {
  let args = parse_args(["nai", "--explain", "find . -name '*.rs'"])
  assert_eq(args.explain, true)
  assert_eq(args.query, "find . -name '*.rs'")
}

test "parse --provider flag" {
  let args = parse_args(["nai", "--provider", "openai", "query here"])
  assert_eq(args.provider, "openai")
  assert_eq(args.query, "query here")
}

test "parse -p short flag" {
  let args = parse_args(["nai", "-p", "claude", "query here"])
  assert_eq(args.provider, "claude")
  assert_eq(args.query, "query here")
}

test "parse --model flag" {
  let args = parse_args(["nai", "-m", "gpt-4o", "my query"])
  assert_eq(args.model, "gpt-4o")
  assert_eq(args.query, "my query")
}

test "parse --help flag" {
  let args = parse_args(["nai", "--help"])
  assert_eq(args.help, true)
}

test "parse -h flag" {
  let args = parse_args(["nai", "-h"])
  assert_eq(args.help, true)
}

test "parse --version flag" {
  let args = parse_args(["nai", "--version"])
  assert_eq(args.version, true)
}

test "parse -V flag" {
  let args = parse_args(["nai", "-V"])
  assert_eq(args.version, true)
}

test "parse combined flags" {
  let args = parse_args(["nai", "-e", "-p", "ollama", "-m", "qwen2.5-coder:7b", "find big files"])
  assert_eq(args.exec, true)
  assert_eq(args.provider, "ollama")
  assert_eq(args.model, "qwen2.5-coder:7b")
  assert_eq(args.query, "find big files")
}

test "parse multi-word query without quotes" {
  let args = parse_args(["nai", "find", "all", "large", "files"])
  assert_eq(args.query, "find all large files")
}

test "parse empty args shows help" {
  let args = parse_args(["nai"])
  assert_eq(args.help, true)
}

test "default history_depth is -1" {
  let args = parse_args(["nai", "some query"])
  assert_eq(args.history_depth, -1)
}

test "parse --history-depth flag" {
  let args = parse_args(["nai", "--history-depth", "20", "some query"])
  assert_eq(args.history_depth, 20)
}

test "parse --no-history flag" {
  let args = parse_args(["nai", "--no-history", "some query"])
  assert_eq(args.no_history, true)
}

test "parse --init flag" {
  let args = parse_args(["nai", "--init", "zsh"])
  assert_eq(args.init_shell, "zsh")
}
