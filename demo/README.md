# dbtpal demo project

A mock dbt project for validating dbtpal navigation without a dbt binary
and without access to a corporate warehouse. Nothing here executes;
everything is static content plus a mock `target/manifest.json` shaped
like the real artifact (only `.nodes`/`.sources`/`.metadata` are read).

## What's covered

- **Both YAML layouts**: shared `models/schema.yml` (multi-model, columns,
  `unit_tests` nesting, a name-second entry) and per-dataset
  `dataset/billing.yml` + `dataset/shop.yml`.
- **Same table under two datasets**: `billing.orders` and `shop.orders`.
- **Cross-package references**: `customers.sql` refs
  `snowplow_utils.page_views`, resolved via
  `dbt_packages/snowplow_utils/`.
- **Seeds and snapshots**: `raw_regions` seed, `orders_snapshot` snapshot.
- **Manifest parity**: `target/manifest.json` mirrors the files above
  (deps, `fqn`, `source_name`, `package_name`), so graph walks,
  dependents, and file opens work end to end. If you have dbt installed,
  running `dbt parse` will overwrite it with a genuine artifact, which
  is also fine.

Open Neovim in this directory, set
`path_to_dbt_project` to it (or rely on auto-detect), and try
`goto_model()` on `ref()`/`source()` lines, YAML declarations, and
`:DbtWalk`.

## Scale and benchmarking

`demo/generated/` (gitignored) holds machine-generated scale fixtures:

```sh
python3 scripts/generate-demo-scale.py --models 500
nvim --headless --noplugin -u tests/minimal.vim -l scripts/bench-demo.lua demo/generated/scale
```

Measured on this machine (500 models, ~500 declarations):

- `properties.scan`: ~33 ms
- `graph.build_index`: ~0.2 ms
- 10× up/down neighbor lookup: ~0 ms
- full `distances`: ~0.4 ms

Conclusion: synchronous scanning needs no cache at this scale. Revisit
only with evidence from projects an order of magnitude larger.

`tests/dbtpal_spec.lua` pins the curated core (dataset-disambiguated
sources, packaged model, manifest parity) so this directory cannot rot
silently.
