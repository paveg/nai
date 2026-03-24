pub fn parse_args(raw : Array[String]) -> CliArgs {
  let mut exec = false
  let mut explain = false
  let mut provider = "auto"
  let mut model = ""
  let mut help = false
  let mut version = false
  let mut history_depth = -1
  let mut no_history = false
  let mut init_shell = ""
  let positional : Array[String] = []
  let mut i = 1 // skip program name
  while i < raw.length() {
    let arg = raw[i]
    match arg {
      "--exec" | "-e" => exec = true
      "--explain" => explain = true
      "--provider" | "-p" => {
        i += 1
        if i < raw.length() {
          provider = raw[i]
        }
      }
      "--model" | "-m" => {
        i += 1
        if i < raw.length() {
          model = raw[i]
        }
      }
      "--help" | "-h" => help = true
      "--version" | "-V" => version = true
      "--no-history" => no_history = true
      "--history-depth" => {
        i += 1
        if i < raw.length() {
          let mut n = 0
          let mut valid = true
          for c in raw[i] {
            if c >= '0' && c <= '9' {
              n = n * 10 + (c.to_int() - '0'.to_int())
            } else {
              valid = false
              break
            }
          }
          if valid {
            history_depth = n
          }
        }
      }
      "--init" => {
        i += 1
        if i < raw.length() {
          init_shell = raw[i]
        }
      }
      _ => positional.push(arg)
    }
    i += 1
  }
  let query = positional.join(" ")
  if query == "" && !help && !version && init_shell == "" {
    help = true
  }
  { query, exec, explain, provider, model, help, version, history_depth, no_history, init_shell }
}
