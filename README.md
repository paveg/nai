# nai

AI-powered shell command generator built with [MoonBit](https://www.moonbitlang.com/). Type what you want in natural language, get a shell one-liner back.

```
$ nai "find all .mbt files using pattern matching"
rg -g '*.mbt' -l 'match'
```

## Features

- **Natural language → shell command** — describe what you want, get a working one-liner
- **Platform-aware** — detects macOS (BSD) vs Linux (GNU) tools and generates correct flags
- **Project-aware** — recognizes MoonBit, Rust, Go, Node.js, Python projects from cwd
- **Tool-aware** — detects installed tools (rg, fd, jq, docker, etc.) and prefers modern alternatives
- **Shell history context** — uses recent commands to understand your workflow
- **Safety checker** — warns about dangerous commands (`rm -rf /`, fork bombs, etc.)
- **Shell integration** — Ctrl+] to generate commands inline (zsh/bash/fish)
- **Multi-provider** — Ollama (local), OpenAI, Claude API support
- **Pipe-friendly** — commands go to stdout, everything else to stderr

## Install

Requires [MoonBit toolchain](https://www.moonbitlang.com/download/).

```sh
# Clone and install
git clone https://github.com/paveg/nai.git
cd nai
moon install $(pwd)/src/nai

# Verify
nai --version
```

The binary is installed to `~/.moon/bin/nai`. Make sure `~/.moon/bin` is in your PATH.

## Setup

### API Provider

nai auto-detects providers in this order:

1. **Ollama** — checks `localhost:11434` (no API key needed)
2. **OpenAI** — uses `OPENAI_API_KEY` environment variable
3. **Claude** — uses `ANTHROPIC_API_KEY` environment variable

```sh
# Use with OpenAI
export OPENAI_API_KEY="sk-..."

# Or specify provider explicitly
nai --provider openai "list running containers"
nai --provider claude "disk usage by directory"
```

### Shell Integration

```sh
# Generate shell integration script
nai --init zsh    # or: bash, fish

# Add to your shell config as instructed
source ~/.config/nai/nai.zsh
```

Then press **Ctrl+]** anywhere in your terminal to invoke nai inline.

### Config File

Optional. Create `~/.config/nai/config.json`:

```json
{
  "default_provider": "openai",
  "history_depth": 10,
  "keybind": "^]",
  "openai": {
    "model": "gpt-4.1-mini"
  }
}
```

## Usage

```sh
# Basic
nai "find files larger than 100MB"

# Execute the generated command (with confirmation)
nai -e "sort directories by disk usage"

# Explain a command
nai --explain "find . -name '*.rs' -mtime -7"

# Override model
nai -m gpt-4.1 "complex database migration query"

# Disable history context
nai --no-history "list all processes"

# Pipe the command somewhere
nai "search for TODO comments" | pbcopy
```

## How It Works

```
┌─────────────┐    ┌──────────────┐    ┌──────────┐    ┌────────┐
│ Natural      │───→│ Environment  │───→│ LLM API  │───→│ Safety │───→ stdout
│ Language     │    │ Detection    │    │ Request  │    │ Check  │
│ Query        │    │              │    │          │    │        │
└─────────────┘    │ • OS/platform│    │ • Ollama │    │ • Warn │
                   │ • Tools (rg, │    │ • OpenAI │    │ • Block│
                   │   fd, jq...) │    │ • Claude │    │        │
                   │ • Project    │    └──────────┘    └────────┘
                   │ • History    │
                   └──────────────┘
```

The system prompt includes:
- OS and shell type (macOS/Linux, zsh/bash/fish)
- Platform tool variants (BSD find/sed/date vs GNU)
- Available tools and preferences (rg > grep, fd > find)
- Project type and source file extensions
- Recent shell history for workflow context

## Development

```sh
# Build
moon build --target native

# Run tests
moon test --target native

# Run directly
moon run src/nai --target native -- "your query"
```

## Project Structure

```
src/
├── lib/
│   ├── types.mbt        # Core types: CliArgs, Provider, Environment, Config
│   ├── cli.mbt          # Argument parsing
│   ├── env.mbt          # Environment detection + prompt building
│   ├── prompt.mbt       # System prompt construction
│   ├── provider.mbt     # LLM provider configuration
│   ├── safety.mbt       # Dangerous command detection
│   ├── history.mbt      # Shell history parsing (zsh/bash/fish)
│   ├── config.mbt       # Config file loading
│   └── shell_init.mbt   # Shell integration script generation
└── nai/
    └── main.mbt         # Async entry point + IO orchestration
```

## License

MIT
