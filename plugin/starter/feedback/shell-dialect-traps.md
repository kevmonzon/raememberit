---
name: shell-dialect-traps
description: A tool's shell may not be the one you write for — on macOS it is often zsh. $PIPESTATUS, word-splitting, `$var:x` modifiers and `timeout` all differ from bash and fail SILENTLY, producing false exit codes or single-file runs.
metadata:
  type: feedback
---

Check which shell actually runs your commands. On macOS it is commonly **zsh**, and four bash
habits misfire there — each one silently.

| Habit | What zsh does | Write instead |
|---|---|---|
| `${PIPESTATUS[0]}` | unset → an empty `exit=` | `$pipestatus[1]`, or redirect to a file and capture `$?` on its own line |
| `cmd $F` with `F="a b"` | **no word-splitting** → one bogus argument, one file processed | an array: `F=(a b)`; from a command, `("${(@f)$(cmd)}")` |
| `"$B:config/x"` | `:c` is parsed as a history modifier and eats text | brace it: `"${B}:config/x"` |
| `timeout 60 cmd` | not present on macOS at all | drop the wrapper, or use the tool's own timeout |

Also: a line beginning `echo ===` errors, because `==` is an equals-expansion — quote separators as
`echo "==="`. And `cmd \| tail; echo "EXIT=$?"` reports tail's status; see
[[verification-tail-masks-failure]].

**Why:** every one of these returns *plausibly* — a blank exit code, a green one-file lint run, a
missing path — so the wrong conclusion looks like evidence.

**How to apply:** when a command's result feeds a claim — an exit code, a file count, a gate verdict
— write it in the dialect that will actually run it, and confirm that reported counts match the
files you meant. Related: [[verify-effect-not-just-wiring]].

Related: [[verify-effect-not-just-wiring]] — a command that silently processed one file instead of
forty produces a green result that measures nothing.
