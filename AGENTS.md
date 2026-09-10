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
