# dbtpal primitives

This document defines the implementation boundary for picker-independent dbt
workflows. The backend uses the documented `dbt` CLI and must not import
Python dbt or Fusion internals.

## Primitive contract

### Buffer and project context

```lua
dbt.current_model()
dbt.require_model_buffer()
dbt.project_for_buffer()
```

These functions reject non-file, Oil, terminal, help, and non-SQL buffers when
a current model is required. Project detection must normalize ordinary paths
and `oil://` URIs.

### Command execution

```lua
dbt.execute(command, args, callback)
```

The executor:

- uses the configured executable;
- uses `vim.system()`;
- passes arguments as a list, never a shell string;
- adds project/profile options once;
- returns stdout, stderr, and exit code;
- emits start/completion notifications;
- sends failures to the existing dbtpal popup.

### Resource discovery

```lua
dbt.list_resources(opts, callback)
```

This invokes `dbt ls --output json` and returns normalized entries:

```lua
{
  unique_id,
  name,
  resource_type,
  original_file_path,
  path,
}
```

Missing optional fields must be tolerated. Malformed JSON and nonzero exits
are errors, not silent empty results.

### Selector construction

The selector layer supports:

```text
model       current model
+model      upstream dependencies
model+      downstream dependents
+model+     family
tag:name    tag selection
path:dir    path selection
```

Resource selection must quote/escape through argument lists rather than shell
concatenation.

### Picker boundary

The core returns resources and accepts selected resources. It must not import
Telescope, mini.pick, or another UI library. Picker adapters may implement:

```lua
picker.select(opts, callback)
picker.select_many(opts, callback)
```

The first feature will use multi-model selection followed by a dbt operation.

The initial backend is a dependency-free `vim.ui.select` implementation. It
supports single selection directly and multi-selection by repeatedly choosing
resources until `Done` is selected. Telescope and mini.pick can be added as
adapters without changing the resource or execution APIs.

## Python dbt and Fusion compatibility

The shared compatibility surface is the CLI:

```text
dbt ls
dbt run
dbt test
dbt compile
dbt build
dbt debug
```

The implementation must not depend on Python dbt APIs, Fusion Rust APIs, or
undocumented artifact internals. Python dbt and Fusion may still differ in
adapter support, Python models, packages, flags, artifacts, and `dbt ls`
behavior. These differences must be surfaced as command errors.

Resource normalization must tolerate field additions and missing optional
fields. Source-map and compiled-SQL mapping are explicitly out of scope for
these primitives.

## Test matrix

### Pure tests

- selector construction for model, upstream, downstream, family, tag, and path;
- resource normalization with complete and partial JSON rows;
- malformed JSON and empty results;
- list argument preservation, including JSON passed through Lua;
- duplicate project/profile argument prevention.

### Neovim integration tests

- native `vim.system()` invocation and exit-code handling;
- start/completion notifications;
- popup output on failure;
- non-SQL/current-buffer warnings;
- Oil URI project detection;
- picker callbacks and cancellation.

### Real dbt smoke tests

Use the locked DuckDB Jaffle Shop project for:

```text
dbt ls --output json
dbt compile
dbt test
dbt run/build with a selector
upstream/downstream/family selectors
invalid selectors and failed commands
```

### Fusion smoke tests

When a compatible Fusion project is available, repeat only the CLI boundary:

```text
dbt --version
dbt ls --output json
dbt compile
dbt test
one selector-based command
```

Full adapter/version coverage is deferred until a concrete incompatibility is
observed.
