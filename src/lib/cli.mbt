pub fn parse_args(raw : Array[String]) -> CliArgs {
  let mut exec = false
  let mut explain = false
  let mut provider = "auto"
  let mut model = ""
  let mut help = false
  let mut version = false
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
      _ => positional.push(arg)
    }
    i += 1
  }
  let query = positional.join(" ")
  if query == "" && !help && !version {
    help = true
  }
  { query, exec, explain, provider, model, help, version }
}
