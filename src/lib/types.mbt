pub struct CliArgs {
  query : String
  exec : Bool
  explain : Bool
  provider : String  // "auto", "ollama", "openai", "claude"
  model : String     // "" means use provider default
  help : Bool
  version : Bool
} derive(Show, Eq)

pub struct Provider {
  base_url : String
  headers : Map[String, String]
  model : String
} derive(Show)

pub struct DangerReport {
  is_dangerous : Bool
  warnings : Array[String]
} derive(Show, Eq)

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
} derive(Show)
