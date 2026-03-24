pub fn build_system_prompt(
  os~ : String,
  shell~ : String,
  cwd~ : String
) -> String {
  $|You are a shell command generator. Given a natural language description,
  $|output ONLY a single shell one-liner. No explanations, no markdown,
  $|no code fences — just the raw command.
  $|
  $|Rules:
  $|- Output exactly one line of shell command
  $|- Valid for: OS=\{os}, Shell=\{shell}
  $|- Current directory: \{cwd}
  $|- Prefer standard POSIX tools
  $|- If ambiguous, choose the safest interpretation
  $|- Do not wrap in backticks or quotes
}

pub fn build_explain_prompt(command : String) -> String {
  $|Explain the following shell command in detail.
  $|Break down each part (command, flags, arguments, pipes).
  $|Be concise but thorough.
  $|
  $|Command: \{command}
}
