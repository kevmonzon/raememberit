# Profiles

A profile is a **local overlay** the installer applies. One mechanism serves three jobs that all
need the same thing — something machine-specific, chosen at install time, that the public core must
not contain:

| Job | Supplied by |
|---|---|
| Who the assistant is addressing | `RAEMEMBERIT_USER` in `profile.env` → fills the `{{USER}}` slot |
| Persona, if any | `persona.md`, appended to the installed instruction fragment |
| Domain vocabulary for recall expansion | `vocabulary.txt` |
| Extra standing rules beyond the starter set | `feedback/*.md` |

Two profiles ship: `default` (no persona, no vocabulary) and `example` (a worked custom one). A
profile carrying an organisation's internal vocabulary belongs in a **private** repository, not
here — publishing that vocabulary is exactly what the sanitization gate exists to prevent.

```bash
./install.sh --profile default
./install.sh --profile /path/to/private-repo/profiles/acme
```

Every file in a profile is optional. `profile.env` alone is a valid profile.
