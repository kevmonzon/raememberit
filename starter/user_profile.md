---
name: user-profile
description: Who {{USER}} is — role, stack, and standing preferences. Replace every line of this file; it ships as a prompt, not as content.
metadata:
  type: user
---

Replace all of this. It is injected into **every** context, so keep it short and keep it true.

- **Role:** <what you do, and what you are accountable for>
- **Stack:** <the languages, frameworks and tools you actually work in daily>
- **Environment:** <OS, shell, package manager — the things that change how commands must be written>
- **Standing preferences:** <two or three things you would otherwise have to repeat weekly>

Anything that only matters for one project belongs in `project/`, not here. Anything that is a rule
about *how work should be done* belongs in `feedback/`. This file is for what is true about you
regardless of the task.
