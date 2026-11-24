# CLAUDE.md

Rules for working in this repo.

- Luau only, with strict types (`--!strict` at the top of every script).
- One mechanic per request. Finish it, test it, stop.
- Read a script before editing it.
- Game logic, RNG and settlement run on the server. The client only displays.
- Keep game math in pure modules with no Roblox APIs and no theme-specific assumptions, so a new setting can reuse the same engine.
- Don't assume the game is dice-only.
- Ask for errors only. Never log per frame. Don't publish.
