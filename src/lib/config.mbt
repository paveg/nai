pub fn default_config() -> Config {
  {
    default_provider: "ollama",
    history_depth: 10,
    keybind: "^]",
    ollama_base_url: "http://localhost:11434/v1",
    ollama_model: "qwen2.5-coder:7b",
    openai_base_url: "https://api.openai.com/v1",
    openai_model: "gpt-4.1-nano",
    claude_base_url: "https://api.anthropic.com/v1",
    claude_model: "claude-haiku-4-5-20251001",
  }
}

pub fn parse_config(json : Json) -> Config {
  let d = default_config()
  let default_provider = match json {
    { "default_provider": String(s), .. } => s
    _ => d.default_provider
  }
  let history_depth = match json {
    { "history_depth": Number(n, ..), .. } => n.to_int()
    _ => d.history_depth
  }
  let keybind = match json {
    { "keybind": String(s), .. } => s
    _ => d.keybind
  }
  let (ollama_base_url, ollama_model) = match json {
    { "ollama": { "base_url": String(bu), "model": String(m), .. }, .. } =>
      (bu, m)
    { "ollama": { "base_url": String(bu), .. }, .. } => (bu, d.ollama_model)
    { "ollama": { "model": String(m), .. }, .. } => (d.ollama_base_url, m)
    _ => (d.ollama_base_url, d.ollama_model)
  }
  let (openai_base_url, openai_model) = match json {
    { "openai": { "base_url": String(bu), "model": String(m), .. }, .. } =>
      (bu, m)
    { "openai": { "base_url": String(bu), .. }, .. } => (bu, d.openai_model)
    { "openai": { "model": String(m), .. }, .. } => (d.openai_base_url, m)
    _ => (d.openai_base_url, d.openai_model)
  }
  let (claude_base_url, claude_model) = match json {
    { "claude": { "base_url": String(bu), "model": String(m), .. }, .. } =>
      (bu, m)
    { "claude": { "base_url": String(bu), .. }, .. } => (bu, d.claude_model)
    { "claude": { "model": String(m), .. }, .. } => (d.claude_base_url, m)
    _ => (d.claude_base_url, d.claude_model)
  }
  {
    default_provider,
    history_depth,
    keybind,
    ollama_base_url,
    ollama_model,
    openai_base_url,
    openai_model,
    claude_base_url,
    claude_model,
  }
}
