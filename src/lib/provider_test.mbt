///|
test "build ollama provider with defaults" {
  let p = build_provider(name="ollama", model="", api_key="")
  assert_eq(p.base_url, "http://localhost:11434/v1")
  assert_eq(p.model, "qwen2.5-coder:7b")
  assert_eq(p.headers.get("Authorization"), Some("Bearer ollama"))
}

///|
test "build ollama provider with custom model" {
  let p = build_provider(name="ollama", model="llama3:8b", api_key="")
  assert_eq(p.model, "llama3:8b")
}

///|
test "build openai provider" {
  let p = build_provider(name="openai", model="", api_key="sk-test123")
  assert_eq(p.base_url, "https://api.openai.com/v1")
  assert_eq(p.model, "gpt-4.1-mini")
  assert_eq(p.headers.get("Authorization"), Some("Bearer sk-test123"))
}

///|
test "build openai provider with custom model" {
  let p = build_provider(name="openai", model="gpt-4o", api_key="sk-test")
  assert_eq(p.model, "gpt-4o")
}

///|
test "build claude provider" {
  let p = build_provider(name="claude", model="", api_key="sk-ant-test")
  assert_eq(p.base_url, "https://api.anthropic.com/v1")
  assert_eq(p.model, "claude-haiku-4-5-20251001")
  assert_eq(p.headers.get("x-api-key"), Some("sk-ant-test"))
  assert_eq(p.headers.get("anthropic-version"), Some("2023-06-01"))
}

///|
test "build request body for openai-compatible" {
  let body = build_request_body(
    provider_name="ollama",
    model="qwen2.5-coder:7b",
    system="You are a helper",
    user="find files",
  )
  let s = body.stringify()
  assert_true(s.contains("qwen2.5-coder:7b"))
  assert_true(s.contains("system"))
  assert_true(s.contains("find files"))
}

///|
test "build request body for claude uses top-level system" {
  let body = build_request_body(
    provider_name="claude",
    model="claude-haiku-4-5-20251001",
    system="You are a helper",
    user="find files",
  )
  let s = body.stringify()
  assert_true(s.contains("\"system\""))
  assert_true(s.contains("find files"))
  assert_true(s.contains("\"user\""))
}

///|
test "extract content from openai response" {
  let json = @json.parse(
    (
      #|{"choices":[{"message":{"content":"ls -la"}}]}
    ),
  )
  let content = extract_content(json)
  assert_eq(content, "ls -la")
}

///|
test "extract content from claude response" {
  let json = @json.parse(
    (
      #|{"content":[{"type":"text","text":"ls -la"}]}
    ),
  )
  let content = extract_claude_content(json)
  assert_eq(content, "ls -la")
}
