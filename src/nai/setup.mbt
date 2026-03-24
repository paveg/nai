///|
fn pr(s : String) -> Unit {
  @tui.print_raw(s)
}

///|
fn prln(s : String) -> Unit {
  @tui.print_raw(s + "\n")
}

///|
fn move_up(n : Int) -> String {
  let mut s = ""
  for _ in 0..<n {
    s = s + @render.ansi_move_up()
  }
  s
}

///|
fn clear_line() -> String {
  @render.ansi_clear_line()
}

///|
fn render_select(
  question : String,
  options : Array[String],
  cursor : Int,
  selected : String,
) -> Array[String] {
  let node : @vnode.TuiNode = if selected.length() > 0 {
    @vnode.column([
      @vnode.row([
        @vnode.text("✓ ", fg="green"),
        @vnode.text(question + " ", bold=true),
        @vnode.text(selected, fg="cyan"),
      ]),
    ])
  } else {
    let children : Array[@vnode.TuiNode] = [
      @vnode.row([@vnode.text("? ", fg="yellow"), @vnode.text(question, bold=true)]),
      @vnode.text("  (↑↓ arrows, Enter to select)", fg="rgb(128,128,128)"),
    ]
    for i, opt in options {
      if i == cursor {
        children.push(
          @vnode.row([@vnode.text("  › ", fg="cyan"), @vnode.text(opt, fg="cyan", bold=true)]),
        )
      } else {
        children.push(@vnode.text("    " + opt, fg="rgb(128,128,128)"))
      }
    }
    @vnode.column(children)
  }
  @vnode.render_to_lines(node)
}

///|
fn render_input(
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
  let node : @vnode.TuiNode = if done {
    @vnode.column([
      @vnode.row([
        @vnode.text("✓ ", fg="green"),
        @vnode.text(question + " ", bold=true),
        @vnode.text(if hidden { "••••••••" } else { display }, fg="cyan"),
      ]),
    ])
  } else {
    @vnode.column([
      @vnode.row([@vnode.text("? ", fg="yellow"), @vnode.text(question, bold=true)]),
      @vnode.row([@vnode.text("  > ", fg="cyan"), @vnode.text(display)]),
    ])
  }
  @vnode.render_to_lines(node)
}

///|
fn print_lines(lines : Array[String]) -> Int {
  for line in lines {
    prln(line)
  }
  lines.length()
}

///|
fn clear_lines(n : Int) -> Unit {
  for _ in 0..<n {
    pr(move_up(1) + "\r" + clear_line())
  }
}

///|
pub async fn run_setup() -> Unit {
  let providers = ["openai", "claude", "ollama"]
  let shells = ["zsh", "bash", "fish", "skip"]

  // State
  let step = @signals.signal(0)
  let cursor = @signals.signal(0)
  let provider_choice = @signals.signal("")
  let api_key_value = @signals.signal("")
  let shell_choice = @signals.signal("")
  let completed = @signals.signal(false)

  let mut lines_rendered = 0
  pr(@render.ansi_hide_cursor())
  prln("")
  prln(
    @render.ansi_bold() +
    @render.ansi_fg_cyan() +
    "◆ nai setup" +
    @render.ansi_reset(),
  )
  prln("")

  fn render() -> Int {
    let current_step = step.get()
    let cur = cursor.get()
    let lines = match current_step {
      0 =>
        render_select(
          "Provider",
          providers,
          cur,
          provider_choice.get(),
        )
      1 =>
        render_input(
          "API key",
          api_key_value.get(),
          false,
          true,
        )
      2 =>
        render_select(
          "Shell integration",
          shells,
          cur,
          shell_choice.get(),
        )
      _ => []
    }
    print_lines(lines)
  }

  // Check if API key already exists in env
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
            clear_lines(lines_rendered)
            prln(@render.ansi_fg_red() + "Aborted." + @render.ansi_reset())
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
                clear_lines(lines_rendered)
                let chosen = providers[cursor.get()]
                provider_choice.set(chosen)
                lines_rendered = render()
                prln("")
                lines_rendered = 0
                cursor.set(0)
                // Skip API key step for ollama or if key already in env
                if chosen == "ollama" || has_api_key(chosen) {
                  if has_api_key(chosen) && chosen != "ollama" {
                    let env_name = api_key_env_name(chosen)
                    prln(
                      @render.ansi_fg_green() +
                      "  ✓ " +
                      env_name +
                      " found in environment" +
                      @render.ansi_reset(),
                    )
                    prln("")
                  }
                  step.set(2)
                } else {
                  step.set(1)
                }
              }
              1 => {
                let key_val = api_key_value.get()
                if key_val.length() > 0 {
                  clear_lines(lines_rendered)
                  let env_name = api_key_env_name(provider_choice.get())
                  let lines = render_input("API key", key_val, true, true)
                  lines_rendered = print_lines(lines)
                  prln("")
                  prln(
                    @render.ansi_fg_yellow() +
                    "  → Add to your shell profile:" +
                    @render.ansi_reset(),
                  )
                  prln(
                    @render.ansi_dim() +
                    "    export " +
                    env_name +
                    "=\"" +
                    key_val +
                    "\"" +
                    @render.ansi_reset(),
                  )
                  prln("")
                  lines_rendered = 0
                  step.set(2)
                  cursor.set(0)
                }
              }
              2 => {
                clear_lines(lines_rendered)
                let chosen = shells[cursor.get()]
                shell_choice.set(chosen)
                lines_rendered = render()
                prln("")
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
      clear_lines(lines_rendered)
      lines_rendered = render()
    }
  }

  @tui.cleanup_stdin()
  pr(@render.ansi_show_cursor())

  if completed.get() {
    // Build and save config
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

    // Create config dir
    try {
      let _ = @process.collect_output_merged("mkdir", ["-p", config_dir])

    } catch {
      _ => ()
    }

    // Write config.json
    let config_json : Json = {
      "default_provider": provider,
      "history_depth": 10,
    }
    let config_path = "\{config_dir}/config.json"
    @fs.write_file(
      config_path,
      config_json.stringify(indent=2),
      create=0o644,
      truncate=true,
    )

    prln("")
    prln(
      @render.ansi_bold() +
      @render.ansi_fg_green() +
      "✓ Setup complete" +
      @render.ansi_reset(),
    )
    prln("")
    prln("  Provider: " + provider)
    prln("  Config:   " + config_path)

    // Shell integration
    if shell != "skip" {
      let config = @lib.default_config()
      let script = @lib.generate_shell_script(shell, keybind=config.keybind)
      if script != "" {
        let home = match @sys.get_env_var("HOME") {
          Some(h) => h
          None => ""
        }
        let file_path = @lib.shell_init_path(shell).replace(
          old="~",
          new=home,
        )
        @fs.write_file(file_path, script, create=0o644, truncate=true)
        let source_path = @lib.shell_init_path(shell)
        let rc = @lib.shell_rc_file(shell)
        prln("  Shell:    " + source_path)
        prln("")
        prln(
          "  Add to " +
          rc +
          ": " +
          @render.ansi_dim() +
          "source " +
          source_path +
          @render.ansi_reset(),
        )
      }
    }
    prln("")
  }
}
