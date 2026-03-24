pub fn build_provider(
  name~ : String,
  model~ : String,
  api_key~ : String
) -> Provider {
  match name {
    "ollama" => {
      let m = if model == "" { "qwen2.5-coder:7b" } else { model }
      {
        base_url: "http://localhost:11434/v1",
        headers: { "Authorization": "Bearer ollama", "Content-Type": "application/json" },
        model: m,
      }
    }
    "openai" => {
      let m = if model == "" { "gpt-4o-mini" } else { model }
      {
        base_url: "https://api.openai.com/v1",
        headers: { "Authorization": "Bearer \{api_key}", "Content-Type": "application/json" },
        model: m,
      }
    }
    "claude" => {
      let m = if model == "" { "claude-haiku-4-5-20251001" } else { model }
      {
        base_url: "https://api.anthropic.com/v1",
        headers: {
          "x-api-key": api_key,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json",
        },
        model: m,
      }
    }
    _ => {
      build_provider(name="ollama", model~, api_key~)
    }
  }
}

pub fn build_request_body(
  provider_name~ : String,
  model~ : String,
  system~ : String,
  user~ : String
) -> Json {
  if provider_name == "claude" {
    {
      "model": model,
      "system": system,
      "messages": [
        { "role": "user", "content": user },
      ],
      "max_tokens": 256,
      "temperature": 0.0,
      "stream": false,
    }
  } else {
    {
      "model": model,
      "messages": [
        { "role": "system", "content": system },
        { "role": "user", "content": user },
      ],
      "max_tokens": 256,
      "temperature": 0.0,
      "stream": false,
    }
  }
}

pub fn extract_content(json : Json) -> String {
  guard json is {
    "choices": [{ "message": { "content": String(content), .. }, .. }, ..],
    ..
  } else {
    abort("Failed to extract content from API response")
  }
  content
}

pub fn extract_claude_content(json : Json) -> String {
  guard json is {
    "content": [{ "text": String(text), .. }, ..],
    ..
  } else {
    abort("Failed to extract content from Claude API response")
  }
  text
}
