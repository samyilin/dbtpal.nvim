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

- `selene.toml` chains `lua51` with a checked-in Neovim standard that
  describes the `vim` API shape (plus test globals).
- The standard is pinned to the **minimum supported Neovim version**
  (currently 0.12.5), not the developer's local version. Linting against
  the minimum turns newer-only API usage into a lint error instead of a
  user-facing runtime bug.
- The minimum version lives in three places that must move together:
  `plugin/dbtpal.lua` (runtime gate), the Selene standard (lint gate),
  and `README.md` (docs).
- Bumping the minimum is a ritual: upgrade the local binary (or fetch the
  pinned release tarball), regenerate the standard with
  `scripts/generate-selene-std.lua --nvim <0.x.y-binary>`, commit the
  output, update the gate and docs. CI regenerates and fails on diff so
  drift is caught automatically.
- The generator reads `vim.api.nvim_get_api_info()` from the **pinned**
  binary, so developing on a newer Neovim (e.g. 0.14) never pollutes the
  standard: anything newer than the minimum simply isn't in it. The
  metadata's `deprecated` flags become Selene `deprecated` entries.
