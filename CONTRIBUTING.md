## Contributing

Fork and clone this repo, then point Neovim at the local checkout. With
`vim.pack`:

```lua
vim.pack.add({ { src = vim.fn.expand("~/projects/dbtpal.nvim") } })
```

There are no mandatory runtime dependencies. Telescope and mini.pick are
optional picker backends only.

To reload the plugin during development, restart Neovim; Lua module
caching makes in-session reloads unreliable.

## Test dbt project

A small dbt project lives in `tests/dbt_project/`. It uses the DuckDB
adapter:

```sh
pip install dbt-core dbt-duckdb
dbt compile
dbt run
```

## Demo project

`demo/` is a mock dbt project (no dbt binary or warehouse required) for
manual validation: both YAML layouts, same-table-two-datasets sources,
cross-package refs, seeds, snapshots, and a mock `target/manifest.json`.
See `demo/README.md`. Scale fixtures and benchmarks:

```sh
python3 scripts/generate-demo-scale.py --models 500
nvim --headless --noplugin -u tests/minimal.vim -l scripts/bench-demo.lua demo/generated/scale
```

## Hooks, format, lint, tests

```sh
pre-commit install
pre-commit run --all-files
make test
```

Tests run in headless Neovim (`tests/run.lua`) with no Plenary
dependency. Formatting uses StyLua; linting uses Selene with the
checked-in `selene.toml` / `neovim.toml` standards.

## Docs

Command and API reference lives in `doc/dbtpal.txt` (Neovim help
format). After editing it, regenerate tags with `:helptags doc`
(`doc/tags` is gitignored).
