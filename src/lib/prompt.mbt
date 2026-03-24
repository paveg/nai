///|
pub fn build_system_prompt(env : Environment) -> String {
  build_env_prompt(env)
}

///|
pub fn build_explain_prompt(command : String) -> String {
  (
    $|Explain the following shell command in detail.
    $|Break down each part (command, flags, arguments, pipes).
    $|Be concise but thorough.
    $|
    $|Command: \{command}
  )
}
