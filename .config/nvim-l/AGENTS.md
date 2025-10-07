# Repository Guidelines

## Project Structure & Module Organization
- Root: `init.lua` bootstraps Lazy and core settings.
- Plugins: `lua/kickstart/plugins/*.lua` (baseline) and `lua/custom/plugins/*.lua` (local additions). Each file returns a Lazy spec table.
- Config/Utilities: `lua/custom/config/*.lua` for commands and helpers; keep modules focused by feature (e.g., `telescope.lua`, `go.lua`).
- Metadata: `lazy-lock.json` (plugin versions), `.stylua.toml` (formatter), `doc/` (docs), `queries/` (Treesitter), `spell/` (spellfiles).

## Build, Test, and Development Commands
- Run this config: `NVIM_APPNAME=nvim-l nvim` (isolates from your default config).
- Install/Update plugins: `:Lazy sync` or `nvim --headless "+Lazy! sync" +qa`.
- Health check: `:checkhealth` (diagnose missing deps like ripgrep).
- Format Lua: `stylua .` (CI enforces via `.github/workflows/stylua.yml`).
- Source current file: `:source %` (reload changes while iterating).

## Coding Style & Naming Conventions
- Formatter: Stylua, 2-space indent, Unix EOL, prefer single quotes; see `.stylua.toml`.
- Modules: one plugin/feature per file, returned spec table; use lowercase snake_case filenames (e.g., `filetree.lua`).
- Lua style: avoid global state; use `vim.keymap.set`, `vim.opt` and `require(...)` locally inside `config` blocks.

## Testing Guidelines
- Manual verification: open a test project, trigger keymaps/commands added by your change.
- Validate startup: `NVIM_APPNAME=nvim-l nvim --clean` is not used; keep this config’s app name to preserve Lazy data.
- Plugin health: `:Lazy`, `:messages`, `:LspInfo` for diagnostics; fix warnings before opening a PR.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject with scope, e.g., `plugins(telescope): enable fzf extension`.
- PRs: describe motivation, key changes, and user-facing impact; link issues; include screenshots for UI tweaks.
- Status checks: ensure Stylua passes and no startup errors (`:checkhealth` clean).

## Security & Configuration Tips
- Do not commit secrets or machine-specific paths; prefer local overrides in `lua/custom/*`.
- Keep plugin additions minimal and well-justified; prefer lazy-loaded specs to reduce startup time.
