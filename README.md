# MCM - Make Commit Message

A command-line tool that generates well-formed commit messages based on your staged changes and then commits with them.

To use MCM, you need `git` installed and access to an LLM service.

![Demo](demo.gif)

## Key Features

- 🤖 AI-powered commit message generation based on staged changes
- 📏 Adherence to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification for consistency
- 🧠 Context-aware messages that capture the essence of your changes
- 💡 Custom hints to customize AI-generated messages
- 📝 Built-in editor integration for easy review and modification

## Installation

1. Create a configuration file at `$HOME/.config/mcm/config.toml` with your API key:

```toml
api_key = "your_api_key"
```

2. Download the appropriate binary for your system from [releases](https://github.com/darkyzhou/mcm/releases).

## Usage

Run MCM in your git repository after staging your changes by `git add`:

```bash
# Generate a commit message and edit it in the editor:
$ mcm

# You could also provide a hint for the AI to generate a more specific commit message:
$ mcm --hint "make it shorter"
$ mcm --hint "mention also the dependency updates"
$ mcm --hint "the scope should be dns/providers"
```

## Limitations

- Only OpenAI and OpenAI-compatible endpoints are supported.
- Only models and endpoints that supports [Structured Output](https://platform.openai.com/docs/guides/structured-outputs) are supported. For OpenAI endpoint, only the latest `gpt-4o` and `gpt-4o-mini` are supported.

## Roadmap

- [ ] Support more LLM providers like Anthropic, Cloudflare, etc.
- [ ] Support more languages besides English.

## Configuration

MCM uses a TOML configuration file located at `$HOME/.config/mcm/config.toml`. Here are the available configuration options:

```toml
# Required: Your API key for the LLM service
api_key = "your_api_key_here"

# Optional: Base URL for the API (default: "https://api.openai.com/v1")
base_url = "https://api.openai.com/v1"

# Optional: AI model to use (default: "gpt-4o-mini")
model = "gpt-4o-mini"

# Optional: Custom system prompt for the AI (default: see `src/config.zig#default_system_prompt`)
# Currently we force the LLM's output to follow the structure defined in `src/request.zig#llm_json_schema`, maybe we could make it also configurable in the future.
system_prompt = """
The prompt
"""

# Optional: Path to your preferred text editor
# If not specified, MCM checks environment variables `VISUAL` and `EDITOR`.
path_to_editor = "/usr/bin/vi"

# Optional: List of file patterns to ignore when generating commit messages (default: see `src/config.zig#AppConfig`)
# Refer to git-diff documentation for name format
ignored_files = [
  "*.lock*",
  "*-lock.*",
]
```
