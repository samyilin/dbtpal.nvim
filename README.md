# dbtpal.nvim

A Neovim plugin for dbt model editing. The little helper I wish I always had.

## Features

- Run dbt through a single pass-through command with floating output
- Pick models and graph neighbours without a mandatory picker dependency
- Async jobs with pop-up command outputs
- Jinja-aware SQL syntax highlighting for dbt models
- Disables accidentally modifying sql files in the target folders
- Jump between SQL resources and YAML declarations with `goto_model()`
- Automatically detect dbt project folder

## Requirements

- Neovim >= 0.12 (`vim.system()` is required)
- [dbt](https://docs.getdbt.com/dbt-cli/installation) >= 1.0.0

Telescope and mini.pick are optional picker backends. There are no
mandatory runtime dependencies.

### dbt Fusion compatibility

The plugin invokes the configured `dbt` executable through Neovim's native
`vim.system()` API and does not call Python dbt APIs. Basic commands should
therefore work with dbt Fusion when the same commands work in a shell:

```sh
dbt --version
dbt compile
dbt build
```

Fusion compatibility is not guaranteed for every project. Adapter support,
Python models, package constraints, CLI flags, artifact formats, and
`dbt ls`-based picker behavior may differ between Python dbt and Fusion. The
configured `path_to_dbt` must point to the intended executable.

### Running dbt in Docker

Point `path_to_dbt` at `docker` and put the `exec` invocation in
`pre_cmd_args`. Arguments go directly to the executable, so resolve the
container name before passing it in; shell substitutions such as `$(...)`
are not evaluated. This recipe uses matching project and profiles paths
on the host and in the container:

```lua
require("dbtpal").setup({
    path_to_dbt = "docker",
    pre_cmd_args = { "exec", "my-dbt-container", "dbt" },
    path_to_dbt_project = "/repo",
    output = "stream",
})
```

```sh
docker run -d --name my-dbt-container --entrypoint sleep \
  -v /repo:/repo -v "$HOME/.dbt:$HOME/.dbt:ro" my-dbt-image infinity
```

The image must provide `dbt` and `sleep`. Both `--project-dir` and
`--profiles-dir` use the mounted paths. The `env` option affects the
Docker client; to set variables inside the container, add `--env`,
`"NAME=value"` after `"exec"` in `pre_cmd_args`. For `:Dbt docs serve`,
publish its port with `docker run -p`; streaming displays its logs while
the server runs. The output window is not an interactive terminal.

## Installation

Install using your favorite plugin manager:

**Using lazy.nvim**

```lua
{
    "samyilin/dbtpal.nvim",
    config = function()
        require("dbtpal").setup({
            -- Path to the dbt executable
            path_to_dbt = "dbt",

            -- Path to the dbt project, if blank, will auto-detect
            -- using currently open buffer
            path_to_dbt_project = "",

            -- Path to dbt profiles directory
            path_to_dbt_profiles_dir = vim.fn.expand("~/.dbt"),

            -- flags to include in dbt command
            include_project_dir = true, -- --project-dir
            include_log_level = true, -- --log-level=INFO

            -- Search for ref/source files in macros and models folders
            extended_path_search = true,

            -- Prevent modifying sql files in target/(compiled|run) folders
            protect_compiled_files = true,

            -- Picker backend: "default", "telescope", or "mini.pick"
            picker_backend = "default",

            -- Hide external packages from model pickers and walk listings
            exclude_packages = {},

            -- Push failed-test locations to the quickfix list
            use_quickfix = false,

            -- Floating window style: named border; width/height are editor
            -- fractions in (0, 1] or absolute cells when greater than 1
            float_border = "double",
            float_width = 0.8,
            float_height = 0.8,

            -- Output: "notify" stays quiet on success, "float" opens output
            -- on exit, "stream" opens at job start with live output
            output = "float",

            -- additional flags to include at the beginning of the rendered dbt command
            pre_cmd_args = {},

            -- additional flags to include at the end of the rendered dbt command
            post_cmd_args = {},
        })

        -- Setup key mappings
        vim.keymap.set("n", "<leader>db", "<cmd>Dbt<cr>")
        vim.keymap.set("n", "<leader>dm", "<cmd>DbtSelectModels<cr>")
        vim.keymap.set("n", "<leader>dw", "<cmd>DbtWalk<cr>")
    end,
}
```

**Using vim.pack**

```lua
vim.pack.add({ { src = "https://github.com/samyilin/dbtpal.nvim" } })

require("dbtpal").setup({
  path_to_dbt = vim.env.DBT_EXECUTABLE or "dbt",
  path_to_dbt_project = "",
  path_to_dbt_profiles_dir = vim.env.DBT_PROFILES_DIR or vim.fn.expand("~/.dbt"),
  picker_backend = "mini.pick",
})

vim.keymap.set("n", "<leader>db", "<cmd>Dbt<cr>")
vim.keymap.set("n", "<leader>dm", "<cmd>DbtSelectModels<cr>")
```

## Commands

A "project directory" is always the dbt directory itself: the nearest
ancestor containing `dbt_project.yml`, so nested projects resolve to the
nearest one. An explicit `path_to_dbt_project` must point at such a
directory (setup warns and falls back to auto-detection otherwise) and
takes precedence for every buffer. Otherwise each buffer resolves to its
own project on use — opening another project's files just works, with no
`setup()` recall. Buffers outside any dbt project warn and abort the
command. Local `oil://` directory names are normalized; other virtual URI
names are excluded from project discovery.

Commands and pickers capture their project when opened, so switching
buffers while a picker or dbt job is pending keeps that operation attached
to its original project. A relative `path_to_dbt_project` is anchored at
`setup()` time. An unnamed buffer uses Neovim's current working directory
for discovery.

Configuration is shared across projects: the executable, profiles, `env`,
CLI arguments, and lookup overrides all come from the same `setup()`.
With empty lookup overrides, each project's `dbt_project.yml` supplies its
own target and package directories. Automatic CLI routing uses the
generated `--project-dir`; disabling `include_project_dir` or supplying
that flag yourself gives control to your CLI arguments or wrapper.

### Dbt

`:Dbt` is a transparent dbt pass-through. Everything after the command name
is forwarded to dbt as an argument list:

```vim
:Dbt run
:Dbt test --select my_model
:Dbt compile --select my_model
:Dbt build --full-refresh
:Dbt debug
```

With no arguments, `:Dbt` shows usage. Output follows `output` (below);
one-off overrides go through the Lua API, e.g.
`require("dbtpal").run_command("run", {"--select", "orders"}, "notify")`.

`run`, `test`, `compile`, and `build` add the current resource name unless an explicit
`--select`/`-s`, `--models`/`-m`, or `--selector` is given. Both
`--select name` and `--select=name` work. SQL/dbt and CSV buffers use the
filename; YAML buffers use the word under the cursor. Other buffers warn
and abort. Use `--select *` for an explicit whole-project run; arguments
use Neovim command escaping, not shell quoting or glob expansion.

With `output = "notify"`, successful commands only notify while
failures still open the detailed floating output. With `output = "stream"`,
floating output opens at job start and shows stdout and stderr as they
arrive. This also applies to picker/walk actions
when you choose **Open full output**. Notify-only mode stays quiet until
completion. Pressing `q` closes the float without cancelling the process.

Style the float with `float_border` (`none`, `single`, `double`,
`rounded`, `solid`, `shadow`), `float_width`, and `float_height`.
Dimensions in (0, 1] scale with the editor; larger values are absolute
cells. Invalid values warn at setup and fall back to defaults.

With `use_quickfix = true`, `test`/`build` test-failure summaries populate
quickfix, including generic tests declared in `.yml`/`.yaml`. Use `:copen`,
`:cnext`, and `:cprev` to navigate. If dbt supplies no line number, the entry
opens line 1 of the reported file. This parses dbt's text summaries, not
JSON logs. A successful rerun clears the matching dbt quickfix list.

### DbtSelectModels

`DbtSelectModels` opens a dependency-free model picker, lets you select one
or more models, and then asks whether to `run`, `test`, `compile`, or
`build` the selection. It then asks whether to show notifications only or
open the complete dbt output.

The selected models are passed to dbt as one `--select` argument using
resource names. `run` and `build` can modify the database; `test` tests
existing relations; `compile` only renders SQL.

### DbtWalk

`DbtWalk` walks the dependency graph one step at a time, staying inside
the picker until you reach your target:

```vim
:DbtWalk
:DbtWalk orders
```

With no argument, the current buffer's model is the starting point (or a
model picker when outside a model buffer). The walk works from model
(SQL/dbt) and seed (CSV) buffers, plus YAML files (schema, sources,
exposures) via the word under the cursor. Each step lists the direct
upstream (`↑`) dependencies and downstream (`↓`) dependents — models,
seeds, snapshots, and sources — plus `.. back`, each annotated with its
shortest-path distance from where the walk started (e.g. `↑ raw (+1)`).
Resources sharing a bare name are listed separately with qualified
labels (`package.name`, `source:dataset.table`); stepping in, tagging,
and run/test/compile/build all track the exact resource, and multi-model
actions select it unambiguously. Each step also offers a `· yaml
declaration` row for the current node only — its parallel YAML
declaration, not an edge — which jumps straight to the properties file.
`Enter` steps into the selected resource; `<C-o>` opens the action menu
(`step into`, `open`, `run`, `test`, `compile`, `build`) for the current
item instead. The prompt shows the breadcrumb trail, `Esc` exits the
whole walk, and the dependency-free picker (which has no action key)
keeps the two-phase menu. The action menu also offers `tag`/`untag` to
collect models across steps; the `★ tagged (n)` entry reviews the
collection and operates on all of them at once (`open all` opens each in
its own buffer, the rest run one combined `--select`). Everything
resolves from the graph cache, so stepping is instant.

### goto_model(), DbtRefreshGraph

`goto_model()` jumps to the model referenced by the `ref()` or
`source()` call on the current line. It is Lua-only by design — bind it
to a key rather than typing a command:

```lua
vim.keymap.set("n", "gd", function() require("dbtpal").goto_model() end)
```

Graph-backed resolution uses `target/manifest.json`, falling back to
`dbt ls`, with a cache refreshed when the manifest changes. The jump is
bidirectional:

- In SQL, `ref()` opens the referenced resource. `source('dataset',
  'table')` prefers the table's YAML declaration, falling back to the
  graph with the same dataset qualifier. Missing datasets never resolve
  to a different dataset with the same table name.
- With no `ref()`/`source()` on the line, a model/seed buffer opens its
  YAML declaration. Both shared `schema.yml` files and per-table layouts
  such as `dataset/table.yml` work: matching is by content, not filename.
- In YAML, a `models:`/`seeds:`/`snapshots:` entry opens its resource
  file. A `sources:` table offers everything selecting from it (models,
  tests, snapshots), SQL files first; a dataset header first offers its
  tables when there is more than one.
  Nested column entries belong to their enclosing resource.
- Multiple matching declarations or resource definitions offer a picker.

YAML lookup scans saved `*.yml`/`*.yaml` files outside the target
directory on each jump. Independent nested dbt projects are excluded;
installed packages remain included. Files recorded by the manifest (`patch_path` and
YAML `original_file_path`s) are trusted for discovery; the scan still
covers the rest, since undocumented resources leave no manifest trace.
The scanner recognizes block-style declarations with a literal `name:`
key, in any key order; a deferred `name:` must precede nested list
content, otherwise the entry is skipped rather than misresolved.
Single-line flow-style mappings (`models: [{name: x}]`) are not parsed;
they are collected into a change-aware report instead — the quickfix
list when `use_quickfix` is set, otherwise a cache file plus a
notification. Map such files in `yaml_flow_files` to silence them (`""`)
or to resolve jumps to a named model (`"model"`); keys resolve against
the project directory, then the working directory. Only files belonging
to the selected project or its installed packages apply; mappings into
other projects are ignored. Missing in-project files warn once per
session. A relative key applies in every project with that file. Use
absolute keys when the two projects need different mappings:

```lua
yaml_flow_files = {
    ["/work/repo-a/models/legacy.yml"] = "orders",
    ["/work/repo-b/models/legacy.yml"] = "", -- silence only in repo-b
}
```

Mapped models are verified against the on-disk graph
cache once per manifest state — verification never runs dbt, and defers
silently without a cache — and resolve with a `(user config)` mark in
picker labels.

File opens resolve against the owning package: manifest paths are joined
to the installed package directory (honoring `packages-install-path`),
and the manifest is read from the configured `target-path`. Both can be
overridden with `path_to_dbt_target` and `path_to_dbt_packages`.

`DbtRefreshGraph` rebuilds the cached graph from existing artifacts;
run dbt first if you need an updated manifest:

```vim
:DbtRefreshGraph
```

## Lua API

```lua
require("dbtpal").setup({ ... })
require("dbtpal").run_command("run", { "--select", "orders" })
require("dbtpal").list_resources({ resource_type = "model" }, callback)
require("dbtpal").select_models()
require("dbtpal").walk()
require("dbtpal").walk("orders")
require("dbtpal").goto_model()
require("dbtpal").refresh_graph()
```

Arguments are structured Lua lists only, never shell strings:

```lua
require("dbtpal").run_command("compile", { "--target", "prod" })
```

Lower-level primitives remain available for integrations:
`require("dbtpal").context`, `require("dbtpal").selectors`,
`require("dbtpal").execute`, and `require("dbtpal").picker`.

`execute(command, args, callback, opts)` invokes the subprocess without
opening UI. The callback receives `{ code, signal, stdout, stderr }` on
Neovim's main loop. Optional `opts.on_chunk(data, stream)` receives live
chunks on the same loop (`stream` is `"stdout"` or `"stderr"`); complete
output is still returned at exit. `run_command()` and `execute()` return
a `vim.SystemObj` on successful launch, which Lua callers can cancel with
`:kill(15)`.

`execute()` and `list_resources()` resolve the current buffer's project
at invocation. Pass `opts.project = "/work/repo-a"` to capture a project
explicitly in an integration. `run_command(command, args, output,
project)` accepts the same override as its optional fourth argument.

## Pickers

Set the backend with `picker_backend` in setup. It defaults to `"default"`
(the dependency-free `vim.ui.select()` backend, with repeated selection
ending in `Done` for multi-select). Set it to `"telescope"` or
`"mini.pick"` only when the corresponding plugin is installed. Cancel with
`<Esc>` or `<C-c>`.

Use `exclude_packages = { "package_name" }` to hide those packages from
model lists and walk listings. Names are dbt's `package_name` values.
Filtering affects the lists, preserving the graph's dependency edges
and explicit reference jumps.

## Primitives

The implementation layers are independent:

- **context**: obtains resource names from SQL/dbt, CSV, and YAML buffers;
  rejects non-file buffers when a resource is required.
- **paths**: normalizes local/Oil paths and rejects other virtual URIs.
- **execute**: uses the configured executable and `vim.system()`; passes
  arguments as a list; adds project/profile options once; returns stdout,
  stderr, and exit code.
- **resources**: runs `dbt ls --output json` and normalizes each row.
  Malformed JSON and nonzero exits are errors, not silent empty results.
- **selectors**: `model`, `+model`, `model+`, `+model+`, `tag:name`, and
  `path:dir`, using resource names rather than artifact `unique_id`
  values. Multi-resource actions qualify ambiguous selections
  (`source:dataset.table`, `fqn:package.model`, `package:`, and
  `resource_type:` intersections) so shared names select exactly.
- **picker**: core returns resources and accepts selections; adapters
  implement `select` and optionally `select_many`.
- **properties**: scans YAML declarations independently of the graph.
- **quickfix**: converts dbt test summaries into navigable locations.

The shared compatibility surface is the dbt CLI. `dbt compile` renders
SQL but does not guarantee executable output; use `run`, `test`, or
`build` to execute or validate relations.

## Configuration

You can override default configuration options by passing a table to
`setup({})`. See the Installation section for an example.

The following options are available:

| Option                   | Description                                                          | Default                |
| ------                   | -----------                                                          | -------                |
| path_to_dbt              | Path to the dbt executable                                           | `dbt`                  |
| path_to_dbt_project      | Path to the dbt project                                              | `""` (auto-detect)     |
| path_to_dbt_profiles_dir | Path to dbt profiles directory                                       | `"~/.dbt"`             |
| path_to_dbt_target       | Override for the manifest directory (reads `target-path` otherwise)  | `""` (auto-detect)     |
| path_to_dbt_packages     | Override for installed packages (reads `packages-install-path`)      | `""` (auto-detect)     |
| extended_path_search     | Search for ref/source files in macros and models folders             | `true`                 |
| protect_compiled_files   | Prevent modifying sql files in target/(compiled\|run) folders        | `true`                 |
| include_project_dir      | Include `--project-dir` flag in dbt command                          | `true`                 |
| include_log_level        | Include `--log-level=INFO` flag in dbt command (only for dbt >= 1.5) | `true`                 |
| picker_backend           | Picker backend: `"default"`, `"telescope"`, or `"mini.pick"`         | `"default"`            |
| exclude_packages           | Package names hidden from model pickers and walk listings              | `{}`                   |
| use_quickfix               | Send failed-test locations to the quickfix list                        | `false`                |
| yaml_flow_files            | Map flow-style YAML files to `""` (silence) or a model name (verified once per manifest; marked user config) | `{}` |
| output                   | `"notify"` quiet on success; `"float"` opens on exit; `"stream"` opens at start, live | `"float"`              |
| float_border               | Floating window border style                                           | `"double"`             |
| float_width                | Float width: editor fraction in (0, 1], else absolute cells            | `0.8`                  |
| float_height               | Float height: editor fraction in (0, 1], else absolute cells           | `0.8`                  |
| custom_dbt_syntax_enabled  | Layer dbt Jinja highlighting over SQL syntax                           | `true`                 |
| env                        | Environment overrides for dbt subprocesses (inherits the host environment) | `{}`                |
| pre_cmd_args             | Additional flags at the beginning of the rendered dbt command        | `{}`                   |
| post_cmd_args            | Additional flags at the end of the rendered dbt command              | `{}`                   |

Generated project/profile/log-level flags are only added when not already
supplied. Log-level support is detected using the configured executable
and `pre_cmd_args`, including Docker wrappers; the result is cached until
that command or `env` configuration changes. Set `include_log_level = false`
to skip the version probe and let dbt choose its logging level. The default
`env = {}` does not suppress dbt's logs.

### SQL syntax

`custom_dbt_syntax_enabled` adds Jinja highlighting on top of SQL. To use
an installed SQL dialect syntax, set its runtime name before opening SQL
buffers, for example `vim.g.dbtpal_sql_base = "sqlbigquery"`. The default
base is `"sql"`. Set `custom_dbt_syntax_enabled = false` to use SQL syntax
without the dbt overlay.

### Misc

Log level can be set with `vim.g.dbtpal_log_level` (must be **before**
`setup()`) or on the command line: `DBTPAL_LOG_LEVEL=info nvim myfile.sql`

## Relationship to upstream

This fork descends from `PedramNavid/dbtpal` and deliberately diverges
in a few places, so some upstream requests are addressed differently
rather than adopted as proposed:

- Upstream/downstream pickers ([#34], [#35]): covered by `DbtWalk`,
  which steps the cached graph in both directions instead of one-shot
  `--select=model±` pickers. There are intentionally no
  `DbtSelectUpstream` / `DbtSelectDownstream` commands.
- Picker speed ([#18]): addressed with a `manifest.json`-backed graph
  cache instead of a `dbt ls` call on every picker open.
- Extra dbt commands ([#31]): covered by the unified `:Dbt`
  pass-through instead of one wrapper per dbt subcommand.
- Directly addressed: `oil://` project dir ([#32]), package filtering
  via `exclude_packages` ([#10]), quickfix via `use_quickfix` ([#9]),
  bidirectional YAML jumps ([#6]), Docker usage (see above, [#15]),
  and live output via `output = "stream"` ([#12]).

[#6]: https://github.com/PedramNavid/dbtpal/issues/6
[#9]: https://github.com/PedramNavid/dbtpal/issues/9
[#10]: https://github.com/PedramNavid/dbtpal/issues/10
[#12]: https://github.com/PedramNavid/dbtpal/issues/12
[#15]: https://github.com/PedramNavid/dbtpal/issues/15
[#18]: https://github.com/PedramNavid/dbtpal/issues/18
[#31]: https://github.com/PedramNavid/dbtpal/pull/31
[#32]: https://github.com/PedramNavid/dbtpal/issues/32
[#34]: https://github.com/PedramNavid/dbtpal/issues/34
[#35]: https://github.com/PedramNavid/dbtpal/pull/35

## Development

Install the repository hooks once with:

```sh
pre-commit install
```

Run them manually with `pre-commit run --all-files`.

The test suite (`make test`) runs directly in headless Neovim and has no
Plenary dependency. `doc/dbtpal.txt` is generated from this README by
panvimdoc; do not edit it by hand.
