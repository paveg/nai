///|
pub fn default_config() -> Config {
  {
    default_provider: "ollama",
    history_depth: 10,
    keybind: "^]",
    ollama_base_url: "http://localhost:11434/v1",
    ollama_model: "qwen2.5-coder:7b",
    openai_base_url: "https://api.openai.com/v1",
    openai_model: "gpt-4.1-mini",
    openai_api_key: "",
    claude_base_url: "https://api.anthropic.com/v1",
    claude_model: "claude-haiku-4-5-20251001",
    claude_api_key: "",
  }
}

///|
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
  let (openai_base_url, openai_model, openai_api_key) = match json {
    {
      "openai": {
        "base_url": String(bu),
        "model": String(m),
        "api_key": String(k),
        ..
      },
      ..
    } => (bu, m, k)
    { "openai": { "base_url": String(bu), "model": String(m), .. }, .. } =>
      (bu, m, d.openai_api_key)
    { "openai": { "api_key": String(k), .. }, .. } =>
      (d.openai_base_url, d.openai_model, k)
    { "openai": { "base_url": String(bu), .. }, .. } =>
      (bu, d.openai_model, d.openai_api_key)
    { "openai": { "model": String(m), .. }, .. } =>
      (d.openai_base_url, m, d.openai_api_key)
    _ => (d.openai_base_url, d.openai_model, d.openai_api_key)
  }
  let (claude_base_url, claude_model, claude_api_key) = match json {
    {
      "claude": {
        "base_url": String(bu),
        "model": String(m),
        "api_key": String(k),
        ..
      },
      ..
    } => (bu, m, k)
    { "claude": { "base_url": String(bu), "model": String(m), .. }, .. } =>
      (bu, m, d.claude_api_key)
    { "claude": { "api_key": String(k), .. }, .. } =>
      (d.claude_base_url, d.claude_model, k)
    { "claude": { "base_url": String(bu), .. }, .. } =>
      (bu, d.claude_model, d.claude_api_key)
    { "claude": { "model": String(m), .. }, .. } =>
      (d.claude_base_url, m, d.claude_api_key)
    _ => (d.claude_base_url, d.claude_model, d.claude_api_key)
  }
  {
    default_provider,
    history_depth,
    keybind,
    ollama_base_url,
    ollama_model,
    openai_base_url,
    openai_model,
    openai_api_key,
    claude_base_url,
    claude_model,
    claude_api_key,
  }
}
