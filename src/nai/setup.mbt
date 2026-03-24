///|
fn tui_pr(s : String) -> Unit {
  @tui.print_raw(s)
}

///|
fn tui_prln(s : String) -> Unit {
  @tui.print_raw(s + "\r\n")
}

///|
fn ansi_up(n : Int) -> String {
  let mut s = ""
  for _ in 0..<n {
    s = s + @render.ansi_move_up()
  }
  s
}

///|
fn ansi_clear() -> String {
  @render.ansi_clear_line()
}

///|
fn tui_clear_lines(n : Int) -> Unit {
  for _ in 0..<n {
    tui_pr(ansi_up(1) + "\r" + ansi_clear())
  }
}

///|
fn dim(s : String) -> String {
  @render.ansi_dim() + s + @render.ansi_reset()
}

///|
fn cyan(s : String) -> String {
  @render.ansi_fg_cyan() + s + @render.ansi_reset()
}

///|
fn green(s : String) -> String {
  @render.ansi_fg_green() + s + @render.ansi_reset()
}

///|
fn yellow(s : String) -> String {
  @render.ansi_fg_yellow() + s + @render.ansi_reset()
}

///|
fn bold(s : String) -> String {
  @render.ansi_bold() + s + @render.ansi_reset()
}

///|
fn render_select_lines(
  question : String,
  options : Array[String],
  cursor : Int,
  selected : String,
) -> Array[String] {
  let lines : Array[String] = []
  if selected.length() > 0 {
    lines.push(green("✓ ") + bold(question + " ") + cyan(selected))
  } else {
    lines.push(yellow("? ") + bold(question))
    lines.push(dim("  (↑↓ arrows, Enter to select)"))
    for i, opt in options {
      if i == cursor {
        lines.push(cyan("  › ") + cyan(bold(opt)))
      } else {
        lines.push(dim("    " + opt))
      }
    }
  }
  lines
}

///|
fn render_input_lines(
  question : String,
  value : String,
  done : Bool,
  hidden : Bool,
) -> Array[String] {
  let display = if hidden && value.length() > 0 {
    let mut stars = ""
    for _ in 0..<value.length() {
      stars = stars + "•"
    }
    stars
  } else {
    value
  }
  let lines : Array[String] = []
  if done {
    lines.push(
      green("✓ ") +
      bold(question + " ") +
      cyan(if hidden { "••••••••" } else { display }),
    )
  } else {
    lines.push(yellow("? ") + bold(question))
    lines.push(cyan("  > ") + display)
  }
  lines
}

///|
fn tui_print_lines(lines : Array[String]) -> Int {
  for line in lines {
    tui_prln(line)
  }
  lines.length()
}

///|
pub async fn run_setup() -> Unit {
  let providers = ["openai", "claude", "ollama"]
  let shells = ["zsh", "bash", "fish", "skip"]

  let step = @signals.signal(0)
  let cursor = @signals.signal(0)
  let provider_choice = @signals.signal("")
  let api_key_value = @signals.signal("")
  let shell_choice = @signals.signal("")
  let completed = @signals.signal(false)

  let mut lines_rendered = 0
  tui_pr(@render.ansi_hide_cursor())
  tui_prln("")
  tui_prln(bold(cyan("◆ nai setup")))
  tui_prln("")

  fn render() -> Int {
    let current_step = step.get()
    let cur = cursor.get()
    let lines = match current_step {
      0 =>
        render_select_lines("Provider", providers, cur, provider_choice.get())
      1 => render_input_lines("API key", api_key_value.get(), false, true)
      2 =>
        render_select_lines(
          "Shell integration",
          shells,
          cur,
          shell_choice.get(),
        )
      _ => []
    }
    tui_print_lines(lines)
  }

  fn has_api_key(provider : String) -> Bool {
    match provider {
      "openai" => @sys.get_env_var("OPENAI_API_KEY").is_some()
      "claude" => @sys.get_env_var("ANTHROPIC_API_KEY").is_some()
      _ => true
    }
  }

  fn api_key_env_name(provider : String) -> String {
    match provider {
      "openai" => "OPENAI_API_KEY"
      "claude" => "ANTHROPIC_API_KEY"
      _ => ""
    }
  }

  lines_rendered = render()
  @tui.enable_raw_mode()

  let mut running = true
  while running {
    let key = @tui.read_key()
    if key.length() == 0 {
      continue
    }
    let event = @tui.parse_input(key)
    let current_step = step.get()
    let mut need_render = true

    match event {
      @tui.InputEvent::Key(key_event) =>
        match key_event {
          @tui.KeyEvent::Char('c', @tui.KeyModifier::Ctrl) => {
            tui_clear_lines(lines_rendered)
            tui_prln(@render.ansi_fg_red() + "Aborted." + @render.ansi_reset())
            running = false
          }
          @tui.KeyEvent::Special(@tui.SpecialKey::Up, _) =>
            if current_step != 1 {
              let max = match current_step {
                0 => providers.length()
                2 => shells.length()
                _ => 0
              }
              let cur = cursor.get()
              cursor.set(if cur > 0 { cur - 1 } else { max - 1 })
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Down, _) =>
            if current_step != 1 {
              let max = match current_step {
                0 => providers.length()
                2 => shells.length()
                _ => 0
              }
              let cur = cursor.get()
              cursor.set(if cur < max - 1 { cur + 1 } else { 0 })
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Enter, _) =>
            match current_step {
              0 => {
                tui_clear_lines(lines_rendered)
                let chosen = providers[cursor.get()]
                provider_choice.set(chosen)
                lines_rendered = render()
                tui_prln("")
                lines_rendered = 0
                cursor.set(0)
                if chosen == "ollama" || has_api_key(chosen) {
                  if has_api_key(chosen) && chosen != "ollama" {
                    let env_name = api_key_env_name(chosen)
                    tui_prln(
                      green("  ✓ " + env_name + " found in environment"),
                    )
                    tui_prln("")
                  }
                  step.set(2)
                } else {
                  step.set(1)
                }
              }
              1 => {
                let key_val = api_key_value.get()
                if key_val.length() > 0 {
                  tui_clear_lines(lines_rendered)
                  let env_name = api_key_env_name(provider_choice.get())
                  let lines = render_input_lines("API key", key_val, true, true)
                  lines_rendered = tui_print_lines(lines)
                  tui_prln("")
                  lines_rendered = 0
                  step.set(2)
                  cursor.set(0)
                }
              }
              2 => {
                tui_clear_lines(lines_rendered)
                let chosen = shells[cursor.get()]
                shell_choice.set(chosen)
                lines_rendered = render()
                tui_prln("")
                completed.set(true)
                running = false
              }
              _ => ()
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Backspace, _) =>
            if current_step == 1 {
              let val = api_key_value.get()
              if val.length() > 0 {
                api_key_value.set(val.substring(end=val.length() - 1))
              }
            }
          @tui.KeyEvent::Char(c, @tui.KeyModifier::None) =>
            if current_step == 1 {
              api_key_value.set(api_key_value.get() + c.to_string())
            } else {
              need_render = false
            }
          _ => need_render = false
        }
      _ => need_render = false
    }

    if need_render && running {
      tui_clear_lines(lines_rendered)
      lines_rendered = render()
    }
  }

  @tui.cleanup_stdin()
  tui_pr(@render.ansi_show_cursor())

  if completed.get() {
    let provider = provider_choice.get()
    let shell = shell_choice.get()

    let config_dir = match @sys.get_env_var("XDG_CONFIG_HOME") {
      Some(dir) => "\{dir}/nai"
      None => {
        let home = match @sys.get_env_var("HOME") {
          Some(h) => h
          None => ""
        }
        "\{home}/.config/nai"
      }
    }

    try {
      let _ = @process.collect_output_merged("mkdir", ["-p", config_dir])
    } catch {
      _ => ()
    }

    // Build config with API key in the provider section
    let api_key = api_key_value.get()
    // Build JSON config string manually to support dynamic provider key
    let config_str = if api_key.length() > 0 {
      let escaped_key = api_key.replace(old="\"", new="\\\"")
      "{\"default_provider\":\"\{provider}\",\"history_depth\":10,\"\{provider}\":{\"api_key\":\"\{escaped_key}\"}}"
    } else {
      "{\"default_provider\":\"\{provider}\",\"history_depth\":10}"
    }
    // Parse and re-stringify for pretty printing
    let fallback : Json = {}
    let config_json : Json = @json.parse(config_str) catch { _ => fallback }
    let config_path = "\{config_dir}/config.json"
    @fs.write_file(
      config_path,
      config_json.stringify(indent=2),
      create=0o600,
      truncate=true,
    )

    tui_prln("")
    tui_prln(bold(green("✓ Setup complete")))
    tui_prln("")
    tui_prln("  Provider: " + provider)
    tui_prln("  Config:   " + config_path)

    if shell != "skip" {
      let config = @lib.default_config()
      let script = @lib.generate_shell_script(shell, keybind=config.keybind)
      if script != "" {
        let home = match @sys.get_env_var("HOME") {
          Some(h) => h
          None => ""
        }
        let file_path = @lib.shell_init_path(shell).replace(old="~", new=home)
        @fs.write_file(file_path, script, create=0o644, truncate=true)
        let source_path = @lib.shell_init_path(shell)
        let rc = @lib.shell_rc_file(shell)
        tui_prln("  Shell:    " + source_path)
        tui_prln("")
        tui_prln("  Add to " + rc + ": " + dim("source " + source_path))
      }
    }
    tui_prln("")
  }
}
