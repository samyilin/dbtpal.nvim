# Repo Instructions for AI Contributors

- Before committing any changes, run `make check` to format, test, and lint the code.
- Keep PR titles short and commit messages descriptive.
- Prefer small, focused commits.
- Document any significant decisions in `README.md` or relevant docs.

## Docs workflow (do not lose this)

- `README.md` is the sole source of user documentation.
- `doc/dbtpal.txt` is generated from `README.md` by panvimdoc. Never edit
  it by hand.
- To regenerate locally: install pandoc (>= 3.0), clone
  `https://github.com/kdheepak/panvimdoc`, and run its `panvimdoc.sh`
  with `--project-name dbtpal --input-file README.md` (defaults otherwise
  match CI) from the repo root.
- The `panvimdoc` CI workflow regenerates and auto-commits the txt on
  push; keep its checkout/auto-commit actions current.
- After editing docs, run `:helptags doc` (`doc/tags` is gitignored).

## Selene standard policy

- `selene.toml` chains `lua51` with a checked-in `neovim.toml` stub that
  declares `vim` and test globals as `any`. This silences
  `undefined_variable` for Neovim/test APIs, nothing more.
- A strict generated standard was attempted and **reverted**: on Selene
  0.31.0, standard-library shape enforcement is dead. Verified probes:
  unknown deep fields (`vim.nope`, `string.nope`), wrong argument types
  (`table.insert("nope")`), missing required args (`table.insert()`,
  `vim.api.nvim_buf_set_lines()`), and even `deprecated` entries all
  produce zero diagnostics. Only top-level `undefined_variable` and
  `must_use` fire.
- Do NOT retry a strict generated standard until Selene fixes
  `incorrect_standard_library_use` enforcement. If retried, the design
  stands: generate from `vim.fn.api_info()` of the pinned
  minimum-version binary (0.12.5 tarballs exist for CI), keep the
  standard pinned to the minimum (not the dev binary), and gate
  freshness via a CI regenerate-and-diff job.
- The minimum version lives in two places that must move together:
  `plugin/dbtpal.lua` (runtime gate) and `README.md` (docs).
- LuaLS (not Selene) is the type/API checker for this repo.
