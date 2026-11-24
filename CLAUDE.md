# CLAUDE.md

Rules for working in this repo.

- Luau only, with strict types (`--!strict` at the top of every script).
- One mechanic per request. Finish it, test it, stop.
- Read a script before editing it.
- Game logic, RNG and settlement run on the server. The client only displays.
- Keep game math in pure modules with no Roblox APIs and no theme-specific assumptions, so a new setting can reuse the same engine.
- Don't assume the game is dice-only.
- Ask for errors only. Never log per frame. Don't publish.

## Checks

Tools come from Rokit (`rokit install`). Run from the repo root before finishing a change:

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --settings=.luau-lsp/settings.json --platform roblox --sourcemap=sourcemap.json src
selene src
```

Both must report no errors or warnings. `sourcemap.json` is gitignored. `.luau-lsp/globalTypes.d.luau` is the Roblox type definitions file from the luau-lsp repo; refresh it when luau-lsp is upgraded.
