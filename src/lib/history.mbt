let sensitive_patterns : Array[String] = [
  "export ", "api_key", "token", "secret", "password", "pass=",
  "authorization",
  "mysql.*-p", "psql.*password",
]

pub fn is_sensitive(line : String) -> Bool {
  let lower = line.to_lower()
  for pattern in sensitive_patterns {
    if lower.contains(pattern) {
      return true
    }
  }
  false
}

fn parse_zsh_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.trim().to_string()
    if s == "" {
      continue
    }
    // Zsh format: ": timestamp:0;command"
    // Skip continuation lines (no ": " prefix)
    if !(s.has_prefix(": ")) {
      continue
    }
    // Find first semicolon
    let mut semicolon_idx = -1
    for j, c in s {
      if c == ';' {
        semicolon_idx = j
        break
      }
    }
    if semicolon_idx >= 0 {
      let cmd = s[(semicolon_idx + 1):].to_string()
      if cmd != "" && !(is_sensitive(cmd)) {
        entries.push(cmd)
      }
    }
  }
  // Return last N entries in reverse order (most recent first)
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

fn parse_bash_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.trim().to_string()
    if s != "" && !(is_sensitive(s)) {
      entries.push(s)
    }
  }
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

fn parse_fish_history(content : String, depth~ : Int) -> Array[String] {
  let entries : Array[String] = []
  for line in content.split("\n") {
    let s = line.trim().to_string()
    if s.has_prefix("- cmd: ") {
      let cmd = s[7:].to_string()
      if cmd != "" && !(is_sensitive(cmd)) {
        entries.push(cmd)
      }
    }
  }
  let start = if entries.length() > depth { entries.length() - depth } else { 0 }
  let result : Array[String] = []
  let mut i = entries.length() - 1
  while i >= start && result.length() < depth {
    result.push(entries[i])
    i -= 1
  }
  result
}

pub fn parse_history(shell : String, content : String, depth~ : Int) -> Array[String] {
  match shell {
    "zsh" => parse_zsh_history(content, depth~)
    "bash" => parse_bash_history(content, depth~)
    "fish" => parse_fish_history(content, depth~)
    _ => []
  }
}

pub fn get_history_path(shell : String) -> String {
  match @sys.get_env_var("HISTFILE") {
    Some(path) => path
    None =>
      match shell {
        "zsh" => {
          let home = match @sys.get_env_var("HOME") {
            Some(h) => h
            None => ""
          }
          "\{home}/.zsh_history"
        }
        "bash" => {
          let home = match @sys.get_env_var("HOME") {
            Some(h) => h
            None => ""
          }
          "\{home}/.bash_history"
        }
        "fish" => {
          match @sys.get_env_var("XDG_DATA_HOME") {
            Some(dir) => "\{dir}/fish/fish_history"
            None => {
              let home = match @sys.get_env_var("HOME") {
                Some(h) => h
                None => ""
              }
              "\{home}/.local/share/fish/fish_history"
            }
          }
        }
        _ => ""
      }
  }
}
