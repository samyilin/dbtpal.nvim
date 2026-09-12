# TODO

- One-way DAG export for web visualization: dump the cached graph (plus
  metadata: project, dataset/source, tags, resource type, file path) as
  JSON alongside a self-contained D3 HTML page. View-only, no
  click-back into Neovim (browser-to-editor IPC is fragile and out of
  scope). Prerequisite: persist node `tags` in the graph cache payload.

- Validate `DbtGotoModel` on `source()` jumps and cross-package models in a
  project that has them (Jaffle Shop has neither).
- Validate dataset-disambiguated `source()` jumps and source traversal in a
  source-heavy work layout (same table under multiple datasets).
- Improve `DbtSelectModels` compile output: when multiple models are selected,
  offer access to each generated SQL artifact instead of showing only dbt's
  aggregate command output. Keep `Notify only` and execution output behavior
  unchanged for `run`, `test`, and `build`.
- Record new demo GIFs for the `:Dbt` command and picker workflows.
