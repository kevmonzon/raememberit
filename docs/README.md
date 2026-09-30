# raememberit — the manual

Everything the front page does not say. Start with the first two; the rest is reference.

| | |
|---|---|
| [Getting started](getting-started.md) | install, the first ten minutes, the two habits |
| [How it works](how-it-works.md) | what happens in a session, in a memory's life, and between sessions — with diagrams |
| [Cadence](cadence.md) | what runs by itself, what you run, and when |
| [Commands and hooks](commands.md) | `/recall`, `/learn`, `/memory-reflect`, `/skill-mine`, `/memory-audit`, and the hooks that run around them |
| [Configuration](configuration.md) | every knob, the two tiers, domain tags, the router's modes |
| [Upgrading and uninstalling](upgrading.md) | `status`, `update`, `uninstall`, and exactly what survives each |
| [Troubleshooting](troubleshooting.md) | each warning `status` can show, and its fix |
| [Advanced](advanced.md) | the three install routes, every flag, where the corpus lives and why |
| [Development](development.md) | the test suites, the sanitization gate, building the plugin, CI |
| [Internals](internals.md) | the stage-by-stage lifecycle and every piece of state the kit keeps |

Conventions: `<config>` is your Claude Code configuration directory, `~/.claude` unless
`CLAUDE_CONFIG_DIR` says otherwise. "The memory folder" and "the corpus" are the same thing,
`<config>/memory`. A "memory" is one markdown file in it.
