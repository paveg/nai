///|
/// Interactive mode: TUI-based query input with proper cursor/paste support.
/// Used by shell integration (Ctrl+]) via `nai --interactive`.
/// Reads query with TUI, outputs generated command to stdout.
pub async fn run_interactive() -> String {
  @tui.enable_raw_mode()
  tui_pr(@render.ansi_hide_cursor())

  let buf = StringBuilder::new()
  let mut cursor_pos = 0

  // Render the prompt line
  fn render_prompt() {
    tui_pr("\r" + ansi_clear())
    let prompt = dim("nai") + yellow("> ")
    let text = buf.to_string()
    tui_pr(prompt + text)
    // Move cursor to correct position if not at end
    let text_len = text.length()
    if cursor_pos < text_len {
      let back = text_len - cursor_pos
      // Move cursor left N positions
      tui_pr("\u001b[\{back}D")
    }
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
          // Ctrl+C — abort
          @tui.KeyEvent::Char('c', @tui.KeyModifier::Ctrl) => running = false
          // Enter — submit
          @tui.KeyEvent::Special(@tui.SpecialKey::Enter, _) => {
            result = buf.to_string()
            running = false
          }
          // Backspace
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
          // Delete
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
          // Left arrow
          @tui.KeyEvent::Special(@tui.SpecialKey::Left, _) =>
            if cursor_pos > 0 {
              cursor_pos -= 1
              render_prompt()
            }
          // Right arrow
          @tui.KeyEvent::Special(@tui.SpecialKey::Right, _) =>
            if cursor_pos < buf.to_string().length() {
              cursor_pos += 1
              render_prompt()
            }
          // Home / Ctrl+A
          @tui.KeyEvent::Special(@tui.SpecialKey::Home, _)
          | @tui.KeyEvent::Char('a', @tui.KeyModifier::Ctrl) => {
            cursor_pos = 0
            render_prompt()
          }
          // End / Ctrl+E
          @tui.KeyEvent::Special(@tui.SpecialKey::End, _)
          | @tui.KeyEvent::Char('e', @tui.KeyModifier::Ctrl) => {
            cursor_pos = buf.to_string().length()
            render_prompt()
          }
          // Ctrl+U — clear line
          @tui.KeyEvent::Char('u', @tui.KeyModifier::Ctrl) => {
            buf.reset()
            cursor_pos = 0
            render_prompt()
          }
          // Ctrl+W — delete word backward
          @tui.KeyEvent::Char('w', @tui.KeyModifier::Ctrl) => {
            let s = buf.to_string()
            if cursor_pos > 0 {
              let mut new_pos = cursor_pos - 1
              // Skip spaces
              while new_pos > 0 && s[new_pos] == ' ' {
                new_pos -= 1
              }
              // Skip word
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
          // Regular character
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

  // Cleanup
  @tui.cleanup_stdin()
  tui_pr(@render.ansi_show_cursor())
  // Clear the prompt line
  tui_pr("\r" + ansi_clear())

  result
}
