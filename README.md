# dbtpal.nvim

A Neovim plugin for dbt model editing. The little helper I wish I always had.

## Features

- Run dbt through a single pass-through command with floating output
- Pick models and graph neighbours without a mandatory picker dependency
- Async jobs with pop-up command outputs
- Jinja-aware SQL syntax highlighting for dbt models
- Disables accidentally modifying sql files in the target folders
- Jump to `ref` or `source` files using `gf` (go-to-file)
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
            include_profiles_dir = true, -- --profiles-dir
            include_project_dir = true, -- --project-dir
            include_log_level = true, -- --log-level=INFO

            -- Search for ref/source files in macros and models folders
            extended_path_search = true,

            -- Prevent modifying sql files in target/(compiled|run) folders
            protect_compiled_files = true,

            -- Picker backend: "default", "telescope", or "mini.pick"
            picker_backend = "default",

            -- Auto-select the current model for run/test/compile/build
            use_current_model = true,

            -- Output mode: "float" or "notify"
            output_mode = "float",

            -- additional flags to include at the beginning of the rendered dbt command
            pre_cmd_args = {},

            -- additional flags to include at the end of the rendered dbt command
            post_cmd_args = {},
        })

        -- Setup key mappings
        vim.keymap.set("n", "<leader>db", "<cmd>Dbt<cr>")
        vim.keymap.set("n", "<leader>dm", "<cmd>DbtSelectModels<cr>")
        vim.keymap.set("n", "<leader>du", "<cmd>DbtSelectUpstream<cr>")
        vim.keymap.set("n", "<leader>dd", "<cmd>DbtSelectDownstream<cr>")
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

dbtpal has sensible defaults and can auto-detect project directories based
on the currently open buffer when first run.

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

With no arguments, `:Dbt` shows usage. `:Dbt!` forces floating output.

When `use_current_model` is enabled (the default) and no `--select` or
`-s` is given, `run`, `test`, `compile`, and `build` use the model from
the current SQL/dbt buffer. Outside a model buffer the command warns and
aborts. Use `--select '*'` for an explicit whole-project run.

With `output_mode = "notify"`, successful commands only notify while
failures still open the detailed floating output.

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
exposures) via the word under the cursor. Each step lists upstream (`↑`)
and downstream (`↓`) neighbours — models, seeds, snapshots, and sources
— plus `.. back`, each annotated with its shortest-path distance from
where the walk started (e.g. `↑ raw (+1)`).
`Enter` steps into the neighbour directly; `<C-o>` opens the action menu
(`step into`, `open`, `run`, `test`, `compile`, `build`) for the current
item instead. The prompt shows the breadcrumb trail, `Esc` exits the
whole walk, and the dependency-free picker (which has no action key)
keeps the two-phase menu. The action menu also offers `tag`/`untag` to
collect models across steps; the `★ tagged (n)` entry reviews the
collection and operates on all of them at once (`open all` opens each in
its own buffer, the rest run one combined `--select`). Everything
resolves from the graph cache, so stepping is instant.

### DbtGotoModel, DbtRefreshGraph

`goto_model()` jumps to the model referenced by the `ref()` or
`source()` call on the current line. It is Lua-only by design — bind it
to a key rather than typing a command:

```lua
vim.keymap.set("n", "gd", function() require("dbtpal").goto_model() end)
```

Resolution uses a cached dependency graph built from the project's
`target/manifest.json` (falling back to `dbt ls`), so jumps are instant
and exact across packages, seeds, snapshots, and sources. When several
sources share a table name, the `source('dataset', 'table')` dataset
selects the right one. `DbtRefreshGraph` rebuilds the cache:

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

Lower-level modules remain available for integrations:
`require("dbtpal").context`, `require("dbtpal").selectors`,
`require("dbtpal").execute`, and `require("dbtpal").picker`.

## Pickers

Set the backend with `picker_backend` in setup. It defaults to `"default"`
(the dependency-free `vim.ui.select()` backend, with repeated selection
ending in `Done` for multi-select). Set it to `"telescope"` or
`"mini.pick"` only when the corresponding plugin is installed. Cancel with
`<Esc>` or `<C-c>`.

## Primitives

The implementation layers are independent:

- **context**: rejects non-file, Oil, terminal, help, and non-SQL buffers
  when a model is required; normalizes `oil://` URIs.
- **execute**: uses the configured executable and `vim.system()`; passes
  arguments as a list; adds project/profile options once; returns stdout,
  stderr, and exit code.
- **resources**: runs `dbt ls --output json` and normalizes each row.
  Malformed JSON and nonzero exits are errors, not silent empty results.
- **selectors**: `model`, `+model`, `model+`, `+model+`, `tag:name`, and
  `path:dir`, using resource names rather than artifact `unique_id`
  values.
- **picker**: core returns resources and accepts selections; adapters
  implement `select` and optionally `select_many`.

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
| extended_path_search     | Search for ref/source files in macros and models folders             | `true`                 |
| protect_compiled_files   | Prevent modifying sql files in target/(compiled\|run) folders        | `true`                 |
| include_profiles_dir     | Include `--profiles-dir` flag in dbt command                         | `true`                 |
| include_project_dir      | Include `--project-dir` flag in dbt command                          | `true`                 |
| include_log_level        | Include `--log-level=INFO` flag in dbt command (only for dbt >= 1.5) | `true`                 |
| picker_backend           | Picker backend: `"default"`, `"telescope"`, or `"mini.pick"`         | `"default"`            |
| use_current_model        | Auto-select the current model when no selector is given              | `true`                 |
| output_mode              | `"float"` opens output always; `"notify"` stays quiet on success     | `"float"`              |
| pre_cmd_args             | Additional flags at the beginning of the rendered dbt command        | `{}`                   |
| post_cmd_args            | Additional flags at the end of the rendered dbt command              | `{}`                   |

### Misc

Log level can be set with `vim.g.dbtpal_log_level` (must be **before**
`setup()`) or on the command line: `DBTPAL_LOG_LEVEL=info nvim myfile.sql`

## Development

Install the repository hooks once with:

```sh
pre-commit install
```

Run them manually with `pre-commit run --all-files`.

The test suite (`make test`) runs directly in headless Neovim and has no
Plenary dependency. `doc/dbtpal.txt` is generated from this README by
panvimdoc; do not edit it by hand.
