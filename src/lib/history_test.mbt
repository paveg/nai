///|
test "parse_zsh_history extracts commands" {
  let content =
    #|: 1711234567:0;ls -la
    #|: 1711234568:0;git status
    #|: 1711234569:0;cd ~/repos
  let result = parse_history("zsh", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "cd ~/repos")
  assert_eq(result[1], "git status")
}

///|
test "parse_zsh_history skips multiline continuations" {
  let content =
    #|: 1711234567:0;for f in *.txt; do
    #|  echo "$f"
    #|done
    #|: 1711234568:0;ls -la
  let result = parse_history("zsh", content, depth=10)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "ls -la")
  assert_eq(result[1], "for f in *.txt; do")
}

///|
test "parse_bash_history extracts last N commands" {
  let content =
    #|ls -la
    #|git status
    #|cd ~/repos
    #|docker ps
  let result = parse_history("bash", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "docker ps")
  assert_eq(result[1], "cd ~/repos")
}

///|
test "parse_fish_history extracts commands" {
  let content =
    #|- cmd: ls -la
    #|  when: 1711234567
    #|- cmd: git status
    #|  when: 1711234568
  let result = parse_history("fish", content, depth=2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "git status")
  assert_eq(result[1], "ls -la")
}

///|
test "parse_history returns empty for unknown shell" {
  let result = parse_history("unknown", "some content", depth=5)
  assert_eq(result.length(), 0)
}

///|
test "parse_history respects depth limit" {
  let content =
    #|line1
    #|line2
    #|line3
    #|line4
    #|line5
  let result = parse_history("bash", content, depth=3)
  assert_eq(result.length(), 3)
}

///|
test "is_sensitive filters export lines" {
  assert_true(is_sensitive("export API_KEY=abc123"))
  assert_true(is_sensitive("export SECRET_TOKEN=xyz"))
}

///|
test "is_sensitive filters curl auth" {
  assert_true(
    is_sensitive(
      "curl -H \"Authorization: Bearer sk-xxx\" https://api.example.com",
    ),
  )
}

///|
test "is_sensitive allows safe commands" {
  assert_true(!is_sensitive("ls -la"))
  assert_true(!is_sensitive("git status"))
  assert_true(!is_sensitive("docker ps"))
}

///|
test "parse_history filters sensitive lines" {
  let content =
    #|ls -la
    #|export API_KEY=secret
    #|git status
    #|curl -H "Authorization: Bearer token" https://api.com
    #|docker ps
  let result = parse_history("bash", content, depth=10)
  let joined = result.join(" | ")
  assert_true(!joined.contains("export API_KEY"))
  assert_true(!joined.contains("Authorization"))
  assert_true(joined.contains("ls -la"))
  assert_true(joined.contains("git status"))
  assert_true(joined.contains("docker ps"))
}

///|
test "get_history_path returns zsh default" {
  let path = get_history_path("zsh")
  assert_true(path.contains(".zsh_history") || path.contains("HISTFILE"))
}

///|
test "get_history_path returns bash default" {
  let path = get_history_path("bash")
  assert_true(path.contains(".bash_history") || path.contains("HISTFILE"))
}
