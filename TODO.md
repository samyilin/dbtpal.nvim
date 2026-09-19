# TODO

- One-way DAG export for web visualization: dump the cached graph (plus
  metadata: project, dataset/source, tags, resource type, file path) as
  JSON alongside a self-contained D3 HTML page. View-only, no
  click-back into Neovim (browser-to-editor IPC is fragile and out of
  scope). Prerequisite: persist node `tags` in the graph cache payload.

- Validate `goto_model()` on `source()` jumps and cross-package models in a
  real project with genuine dbt artifacts. `demo/` covers the shapes
  (packaged `ref()`, manifest sources) but not real-artifact parity.
- Validate dataset-disambiguated `source()` jumps and source traversal in a
  source-heavy work layout (same table under multiple datasets).
  `demo/dataset/` covers the two-dataset shape.
- Validate bidirectional `goto_model()` YAML handling outside a
  per-dataset `table.yml` layout in real projects. `demo/models/schema.yml`
  covers the shared-file shape (multi-model, nesting, reordered keys);
  workplace validation is still outstanding.
- Evaluate full YAML parsing (block flow style across lines, aliases/merge
  keys, computed names). Single-line flow mappings are now detected and
  reported (quickfix or cache file), and `yaml_flow_files` covers known
  files; a real parser remains a dependency decision, deliberately
  deferred to keep the plugin dependency-free.

- Improve `DbtSelectModels` compile output: when multiple models are selected,
  offer access to each generated SQL artifact instead of showing only dbt's
  aggregate command output (`demo/target/` can host mock compiled artifacts
  as fixtures). Keep `Notify only` and execution output behavior
  unchanged for `run`, `test`, and `build`.
- Record new demo GIFs for the `:Dbt` command and picker workflows
  (`demo/` is ready-made subject matter).
