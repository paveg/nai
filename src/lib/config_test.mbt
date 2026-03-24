test "default_config has expected values" {
  let c = default_config()
  assert_eq(c.default_provider, "ollama")
  assert_eq(c.history_depth, 10)
  assert_eq(c.keybind, "^]")
  assert_eq(c.ollama_base_url, "http://localhost:11434/v1")
  assert_eq(c.ollama_model, "qwen2.5-coder:7b")
  assert_eq(c.openai_base_url, "https://api.openai.com/v1")
  assert_eq(c.openai_model, "gpt-4.1-mini")
  assert_eq(c.claude_base_url, "https://api.anthropic.com/v1")
  assert_eq(c.claude_model, "claude-haiku-4-5-20251001")
}

test "parse_config with full JSON" {
  let s =
    #|{"default_provider":"openai","history_depth":20,"keybind":"^G","ollama":{"base_url":"http://custom:11434/v1","model":"llama3:8b"},"openai":{"base_url":"https://custom.openai.com/v1","model":"gpt-4.1"},"claude":{"base_url":"https://custom.anthropic.com/v1","model":"claude-sonnet"}}
  let json = @json.parse(s)
  let c = parse_config(json)
  assert_eq(c.default_provider, "openai")
  assert_eq(c.history_depth, 20)
  assert_eq(c.keybind, "^G")
  assert_eq(c.ollama_base_url, "http://custom:11434/v1")
  assert_eq(c.ollama_model, "llama3:8b")
  assert_eq(c.openai_base_url, "https://custom.openai.com/v1")
  assert_eq(c.openai_model, "gpt-4.1")
  assert_eq(c.claude_base_url, "https://custom.anthropic.com/v1")
  assert_eq(c.claude_model, "claude-sonnet")
}

test "parse_config with empty JSON uses defaults" {
  let s = #|{}
  let json = @json.parse(s)
  let c = parse_config(json)
  let d = default_config()
  assert_eq(c, d)
}

test "parse_config with partial JSON fills defaults" {
  let s = #|{"default_provider":"claude","history_depth":5}
  let json = @json.parse(s)
  let c = parse_config(json)
  assert_eq(c.default_provider, "claude")
  assert_eq(c.history_depth, 5)
  assert_eq(c.ollama_model, "qwen2.5-coder:7b")
  assert_eq(c.openai_model, "gpt-4.1-mini")
}

test "parse_config ignores unknown fields" {
  let s = #|{"default_provider":"openai","unknown_field":"whatever"}
  let json = @json.parse(s)
  let c = parse_config(json)
  assert_eq(c.default_provider, "openai")
}
