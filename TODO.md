# TODO

- Record new demo GIFs for the `:Dbt` command and picker workflows.
- Validate `DbtGotoModel` on `source()` jumps and cross-package models in a
  project that has them (Jaffle Shop has neither).

- Improve `DbtSelectModels` compile output: when multiple models are selected,
  offer access to each generated SQL artifact instead of showing only dbt's
  aggregate command output. Keep `Notify only` and execution output behavior
  unchanged for `run`, `test`, and `build`.
- Sanity-check the mini.pick batch workflow and graph actions.
- Thoroughly test graph commands from non-SQL and Oil buffers.
- Test configured dbt executable, profiles directory, and explicit CLI
  arguments.
- Once the public API stabilizes, flesh out `neovim.toml` beyond `any = true`
  so Selene validates Neovim API usage shape, not just global existence.
