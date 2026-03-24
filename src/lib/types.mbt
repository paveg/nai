///|
pub struct CliArgs {
  query : String
  exec : Bool
  explain : Bool
  provider : String // "auto", "ollama", "openai", "claude"
  model : String // "" means use provider default
  help : Bool
  version : Bool
  history_depth : Int // -1 means use config default
  no_history : Bool
  init_shell : String // "" or "zsh"/"bash"/"fish"
  setup : Bool
  interactive : Bool
} derive(Show, Eq)

///|
pub struct Provider {
  base_url : String
  headers : Map[String, String]
  model : String
} derive(Show)

///|
pub struct DangerReport {
  is_dangerous : Bool
  warnings : Array[String]
} derive(Show, Eq)

///|
pub(all) struct Environment {
  os : String
  shell : String
  cwd : String
  platform : String
  pkg_manager : String
  clipboard : String
  find_variant : String
  sed_variant : String
  date_variant : String
  stat_variant : String
  available_tools : Array[String]
  history : Array[String]
  project_type : String // "" or "moonbit", "rust", "go", "node", "python", etc.
} derive(Show)

///|
pub struct Config {
  default_provider : String
  history_depth : Int
  keybind : String
  ollama_base_url : String
  ollama_model : String
  openai_base_url : String
  openai_model : String
  claude_base_url : String
  claude_model : String
} derive(Show, Eq)
