///|
/// Interactive mode: TUI-based query input with proper cursor/paste support.
/// Used by shell integration (Ctrl+]) via `nai --interactive`.
/// TUI rendering goes to stderr. Only the final command goes to stdout.
pub async fn run_interactive() -> String {
  @tui.enable_raw_mode()
  // TUI output to stderr (not stdout) so $(nai --interactive) only captures the result
  @stdio.stderr.write(@render.ansi_hide_cursor())

  let buf = StringBuilder::new()
  let mut cursor_pos = 0

  async fn render_prompt() -> Unit {
    let clear = "\r" + @render.ansi_clear_line()
    let prompt = @render.ansi_dim() +
      "nai" +
      @render.ansi_reset() +
      @render.ansi_fg_yellow() +
      "> " +
      @render.ansi_reset()
    let text = buf.to_string()
    let mut cursor_move = ""
    let text_len = text.length()
    if cursor_pos < text_len {
      let back = text_len - cursor_pos
      cursor_move = "\u001b[\{back}D"
    }
    @stdio.stderr.write(clear + prompt + text + cursor_move)
  }

  render_prompt()

  let mut result = ""
  let mut running = true

  while running {
    let key = @tui.read_key()
    if key.length() == 0 {
      continue
    }
    let event = @tui.parse_input(key)

    match event {
      @tui.InputEvent::Key(key_event) =>
        match key_event {
          @tui.KeyEvent::Char('c', @tui.KeyModifier::Ctrl) => running = false
          @tui.KeyEvent::Special(@tui.SpecialKey::Enter, _) => {
            result = buf.to_string()
            running = false
          }
          @tui.KeyEvent::Special(@tui.SpecialKey::Backspace, _) =>
            if cursor_pos > 0 {
              let s = buf.to_string()
              buf.reset()
              buf.write_string(
                s.substring(end=cursor_pos - 1) + s.substring(start=cursor_pos),
              )
              cursor_pos -= 1
              render_prompt()
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Delete, _) => {
            let s = buf.to_string()
            if cursor_pos < s.length() {
              buf.reset()
              buf.write_string(
                s.substring(end=cursor_pos) + s.substring(start=cursor_pos + 1),
              )
              render_prompt()
            }
          }
          @tui.KeyEvent::Special(@tui.SpecialKey::Left, _) =>
            if cursor_pos > 0 {
              cursor_pos -= 1
              render_prompt()
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Right, _) =>
            if cursor_pos < buf.to_string().length() {
              cursor_pos += 1
              render_prompt()
            }
          @tui.KeyEvent::Special(@tui.SpecialKey::Home, _)
          | @tui.KeyEvent::Char('a', @tui.KeyModifier::Ctrl) => {
            cursor_pos = 0
            render_prompt()
          }
          @tui.KeyEvent::Special(@tui.SpecialKey::End, _)
          | @tui.KeyEvent::Char('e', @tui.KeyModifier::Ctrl) => {
            cursor_pos = buf.to_string().length()
            render_prompt()
          }
          @tui.KeyEvent::Char('u', @tui.KeyModifier::Ctrl) => {
            buf.reset()
            cursor_pos = 0
            render_prompt()
          }
          @tui.KeyEvent::Char('w', @tui.KeyModifier::Ctrl) => {
            let s = buf.to_string()
            if cursor_pos > 0 {
              let mut new_pos = cursor_pos - 1
              while new_pos > 0 && s[new_pos] == ' ' {
                new_pos -= 1
              }
              while new_pos > 0 && s[new_pos - 1] != ' ' {
                new_pos -= 1
              }
              buf.reset()
              buf.write_string(
                s.substring(end=new_pos) + s.substring(start=cursor_pos),
              )
              cursor_pos = new_pos
              render_prompt()
            }
          }
          @tui.KeyEvent::Char(c, @tui.KeyModifier::None) => {
            let s = buf.to_string()
            buf.reset()
            buf.write_string(
              s.substring(end=cursor_pos) +
              c.to_string() +
              s.substring(start=cursor_pos),
            )
            cursor_pos += 1
            render_prompt()
          }
          _ => ()
        }
      _ => ()
    }
  }

  @tui.cleanup_stdin()
  @stdio.stderr.write(
    @render.ansi_show_cursor() + "\r" + @render.ansi_clear_line() + "\r\n",
  )

  result
}
