---@diagnostic disable: need-check-nil
local commands = require "dbtpal.commands"
local graph = require "dbtpal.graph"
local properties = require "dbtpal.properties"
local projects = require "dbtpal.projects"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"

before_each(
    function()
        require("dbtpal").setup {
            path_to_dbt_project = "./tests/dbt_project/",
            path_to_dbt_profiles_dir = "./tests/dbt_project/",
            include_log_level = false,
        }
    end
)

it("can be required", function() require "dbtpal" end)

it("builds dbt commands", function()
    local path, args = commands.build_path_args("compile", { "--select", "my_model" })
    check_equal("dbt", path)
    check_same({
        "compile",
        "--select",
        "my_model",
        "--profiles-dir",
        "./tests/dbt_project/",
        "--project-dir",
        "./tests/dbt_project/",
    }, args)
end)

it("builds graph selectors", function()
    check_equal("+orders", selectors.upstream "orders")
    check_equal("orders+", selectors.downstream "orders")
    check_equal("+orders+", selectors.family "orders")
    check_equal("tag:daily", selectors.tag "daily")
    check_equal("path:models/staging", selectors.path "models/staging")
end)

it("matches unique ids exactly and labels qualified names", function()
    local index = graph.build_index {
        ["model.proj.orders"] = {
            name = "orders",
            resource_type = "model",
            original_file_path = "models/orders.sql",
            depends_on = { nodes = {} },
        },
        ["model.pkg.orders"] = {
            name = "orders",
            resource_type = "model",
            original_file_path = "models/orders.sql",
            depends_on = { nodes = {} },
        },
        ["source.proj.raw.orders"] = {
            name = "orders",
            resource_type = "source",
            source_name = "raw",
            original_file_path = "models/sources.yml",
            depends_on = { nodes = {} },
        },
    }
    local exact = graph.matches(index, "model.proj.orders")
    check_equal(1, #exact)
    check_equal("model.proj.orders", exact[1].unique_id)
    local bare = graph.matches(index, "orders")
    check_equal(3, #bare)
    check_equal("model.pkg.orders", bare[1].unique_id)
    check_equal("proj.orders", graph.label(index.nodes["model.proj.orders"]))
    check_equal("source:proj.raw.orders", graph.label(index.nodes["source.proj.raw.orders"]))
end)

it("lists only direct walk neighbors", function()
    local workflows = require "dbtpal.workflows"
    local index = graph.build_index {
        ["model.proj.a"] = {
            name = "a",
            resource_type = "model",
            original_file_path = "models/a.sql",
            depends_on = { nodes = {} },
        },
        ["model.proj.b"] = {
            name = "b",
            resource_type = "model",
            original_file_path = "models/b.sql",
            depends_on = { nodes = { "model.proj.a" } },
        },
        ["model.proj.c"] = {
            name = "c",
            resource_type = "model",
            original_file_path = "models/c.sql",
            depends_on = { nodes = { "model.proj.b" } },
        },
    }
    local neighbors = workflows.walk_neighbors(index, "model.proj.b")
    check_equal(2, #neighbors)
    check_equal("up", neighbors[1].direction)
    check_equal("a", neighbors[1].name)
    check_equal("down", neighbors[2].direction)
    check_equal("c", neighbors[2].name)
    local ends = workflows.walk_neighbors(index, "model.proj.c")
    check_equal(1, #ends)
    check_equal("b", ends[1].name)
end)

it("builds qualified dbt selectors", function()
    check_equal(
        "source:raw.orders,package:proj,resource_type:source",
        selectors.from_resource { name = "orders", resource_type = "source", source_name = "raw", package_name = "proj" }
    )
    check_equal(
        "fqn:proj.orders,package:proj,resource_type:model",
        selectors.from_resource {
            name = "orders",
            resource_type = "model",
            package_name = "proj",
            fqn = { "proj", "orders" },
        }
    )
    check_equal("orders", selectors.from_resource { name = "orders" })
end)

it("normalizes dbt resources", function()
    local resource = resources.normalize {
        unique_id = "model.project.orders",
        name = "orders",
        resource_type = "model",
        original_file_path = "models/orders.sql",
        package_name = "project",
    }
    check_equal("model.project.orders", resource.unique_id)
    check_equal("models/orders.sql", resource.path)
    check_equal("model", resource.resource_type)
end)

it("indexes graph nodes and links direct edges", function()
    local index = graph.build_index {
        ["seed.proj.raw"] = {
            name = "raw",
            resource_type = "seed",
            package_name = "proj",
            original_file_path = "seeds/raw.csv",
            depends_on = { nodes = {} },
        },
        ["model.proj.stg"] = {
            name = "stg",
            resource_type = "model",
            package_name = "proj",
            original_file_path = "models/stg.sql",
            depends_on = { nodes = { "seed.proj.raw" } },
        },
        ["model.proj.final"] = {
            name = "final",
            resource_type = "model",
            package_name = "proj",
            original_file_path = "models/final.sql",
            depends_on = { nodes = { "model.proj.stg" } },
        },
    }
    local up = graph.neighbors(index, "model.proj.final", "up")
    check_equal(1, #up)
    check_equal("stg", up[1].name)
    local down = graph.neighbors(index, "seed.proj.raw", "down")
    check_equal(1, #down)
    check_equal("stg", down[1].name)
    check_equal(1, #index.dependents["model.proj.stg"])
    check_equal("models/stg.sql", index.by_name["stg"][1].path)
end)

it("resolves sources by dataset without cross-dataset fallback", function()
    local index = graph.build_index {
        ["source.proj.billing.orders"] = {
            name = "orders",
            resource_type = "source",
            source_name = "billing",
            original_file_path = "models/sources.yml",
            depends_on = { nodes = {} },
        },
        ["source.proj.shop.orders"] = {
            name = "orders",
            resource_type = "source",
            source_name = "shop",
            original_file_path = "models/sources.yml",
            depends_on = { nodes = {} },
        },
    }
    local shop = vim.tbl_filter(
        function(entry) return entry.resource_type == "source" and entry.source_name == "shop" end,
        graph.matches(index, "orders")
    )
    check_equal(1, #shop)
    check_equal("shop", shop[1].source_name)
    check_equal(2, #graph.matches(index, "orders"))
    check_equal(0, #graph.matches(index, "missing"))
end)

it("labels walk neighbors by direction", function()
    local workflows = require "dbtpal.workflows"
    local index = graph.build_index {
        ["seed.proj.raw"] = {
            name = "raw",
            resource_type = "seed",
            original_file_path = "seeds/raw.csv",
            depends_on = { nodes = {} },
        },
        ["model.proj.stg"] = {
            name = "stg",
            resource_type = "model",
            original_file_path = "models/stg.sql",
            depends_on = { nodes = { "seed.proj.raw" } },
        },
        ["model.proj.final"] = {
            name = "final",
            resource_type = "model",
            original_file_path = "models/final.sql",
            depends_on = { nodes = { "model.proj.stg" } },
        },
    }
    local neighbors = workflows.walk_neighbors(index, "stg")
    check_equal(2, #neighbors)
    check_equal("up", neighbors[1].direction)
    check_equal("raw", neighbors[1].name)
    check_equal("down", neighbors[2].direction)
    check_equal("final", neighbors[2].name)
end)

it("measures undirected distances from an origin", function()
    local index = graph.build_index {
        ["seed.proj.raw"] = {
            name = "raw",
            resource_type = "seed",
            original_file_path = "seeds/raw.csv",
            depends_on = { nodes = {} },
        },
        ["model.proj.stg"] = {
            name = "stg",
            resource_type = "model",
            original_file_path = "models/stg.sql",
            depends_on = { nodes = { "seed.proj.raw" } },
        },
        ["model.proj.final"] = {
            name = "final",
            resource_type = "model",
            original_file_path = "models/final.sql",
            depends_on = { nodes = { "model.proj.stg" } },
        },
    }
    local dist = graph.distances(index, "stg")
    check_equal(0, dist["model.proj.stg"])
    check_equal(1, dist["seed.proj.raw"])
    check_equal(1, dist["model.proj.final"])
end)

it("compresses breadcrumb trails", function()
    local crumbs, truncated = graph.compress_trail({ "a", "b", "a" }, 3)
    check_same({ "a" }, crumbs)
    check_equal(false, truncated)
    local long, cut = graph.compress_trail({ "a", "b", "c", "d" }, 3)
    check_same({ "b", "c", "d" }, long)
    check_equal(true, cut)
    local short, kept = graph.compress_trail({ "a", "b" }, 3)
    check_same({ "a", "b" }, short)
    check_equal(false, kept)
end)

it("toggles tagged models", function()
    local workflows = require "dbtpal.workflows"
    local tagged = {}
    check_equal(true, workflows.toggle_tag(tagged, { unique_id = "model.p.a", name = "a" }))
    check_equal(true, workflows.is_tagged(tagged, { unique_id = "model.p.a", name = "a" }))
    check_equal(false, workflows.toggle_tag(tagged, { unique_id = "model.p.a", name = "a" }))
    check_equal(false, workflows.is_tagged(tagged, { unique_id = "model.p.a", name = "a" }))
    check_equal(0, #tagged)
end)

it("lists models sorted by name", function()
    local index = graph.build_index {
        ["model.proj.zebra"] = {
            name = "zebra",
            resource_type = "model",
            original_file_path = "models/zebra.sql",
            depends_on = { nodes = {} },
        },
        ["model.proj.apple"] = {
            name = "apple",
            resource_type = "model",
            original_file_path = "models/apple.sql",
            depends_on = { nodes = {} },
        },
        ["seed.proj.raw"] = {
            name = "raw",
            resource_type = "seed",
            original_file_path = "seeds/raw.csv",
            depends_on = { nodes = {} },
        },
    }
    local models = graph.models(index)
    check_equal(2, #models)
    check_equal("apple", models[1].name)
    check_equal("zebra", models[2].name)
end)

it("parses ref and source calls", function()
    local ref = graph.parse_model_ref "select * from {{ ref('orders') }}"
    check_equal("ref", ref.kind)
    check_equal("orders", ref.name)
    local source = graph.parse_model_ref '{{ source("raw", "orders") }}'
    check_equal("source", source.kind)
    check_equal("orders", source.name)
    local packaged = graph.parse_model_ref "{{ ref('package_name', 'orders') }}"
    check_equal("package_name", packaged.package_name)
    check_equal("orders", packaged.name)
    check_true(graph.parse_model_ref "select 1" == nil, "expected no ref")
end)

it("resolves model names from yaml buffers", function()
    local context = require "dbtpal.context"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "models:", "  - name: orders" })
    vim.bo[buf].filetype = "yaml"
    vim.api.nvim_win_set_cursor(0, { 2, 11 })
    check_equal("orders", context.current_model())
    vim.bo[buf].filetype = "lua"
    check_true(context.current_model() == nil, "expected no model")
end)

it("finds the dbt project directory", function()
    require("dbtpal.config").options.path_to_dbt_project = ""
    check_true(projects.detect_dbt_project_dir "tests/dbt_project/models/example", "expected project detection")
    check_equal(vim.fn.getcwd() .. "/tests/dbt_project", require("dbtpal.config").options.path_to_dbt_project)
end)

it("never clobbers a configured project dir", function()
    local config = require "dbtpal.config"
    config.options.path_to_dbt_project = "/manual/project"
    check_true(
        projects.detect_dbt_project_dir "tests/dbt_project/models/example",
        "expected true for configured project"
    )
    check_equal("/manual/project", config.options.path_to_dbt_project)
    check_equal(vim.fn.getcwd() .. "/tests/dbt_project", projects.find_project_dir "tests/dbt_project/models/example")
end)

it("strips oil:// URIs from paths", function()
    check_equal("/proj/models", projects.normalize_path "oil:///proj/models")
    check_equal("/proj/models", projects.normalize_path "/proj/models")
    check_true(projects.normalize_path "fugitive:///repo/.git//0/models/a.sql" == nil, "expected nil for fugitive URI")
    require("dbtpal.config").options.path_to_dbt_project = ""
    check_true(projects.detect_dbt_project_dir "fugitive:///repo/.git//0/models" == false, "expected no detection")
end)

it("excludes configured packages from resources", function()
    local config = require "dbtpal.config"
    config.options.exclude_packages = { "external" }
    local items = {
        { name = "orders", package_name = "my_project" },
        { name = "util", package_name = "external" },
    }
    local kept = resources.excluding(items)
    check_equal(1, #kept)
    check_equal("orders", kept[1].name)
    config.options.exclude_packages = {}
    check_equal(2, #resources.excluding(items))
end)

it("parses test failures into quickfix entries", function()
    local entries = require("dbtpal.quickfix").parse({
        "Failure in test not_null_orders (tests/not_null_orders.sql)",
        "Failure in test unique_ids (tests/unique_ids.sql:3)",
        "Done. PASS=1",
    }, "/proj")
    check_equal(2, #entries)
    check_equal("/proj/tests/not_null_orders.sql", entries[1].filename)
    check_equal("/proj/tests/unique_ids.sql", entries[2].filename)
    check_equal(3, entries[2].lnum)
end)

it("parses model declarations from properties YAML", function()
    local decls = properties.parse {
        "models:",
        "  - name: orders",
        "    description: All orders",
        "  - name: customers",
        "seeds:",
        "  - name: raw_seed",
    }
    check_equal(3, #decls)
    check_equal("models", decls[1].kind)
    check_equal("orders", decls[1].name)
    check_equal(2, decls[1].lnum)
    check_equal("seeds", decls[3].kind)
    check_equal("raw_seed", decls[3].name)
end)

it("ignores nested names inside model entries", function()
    local decls = properties.parse {
        "models:",
        "  - name: orders",
        "    columns:",
        "      - name: order_id",
        "    unit_tests:",
        "      - name: test_orders",
    }
    check_equal(1, #decls)
    check_equal("orders", decls[1].name)
end)

it("finds entries with reordered name keys", function()
    local decls = properties.parse {
        "models:",
        "  - description: All orders",
        "    name: orders",
        "sources:",
        "  - description: Shared data",
        "    name: raw",
        "    tables:",
        "      - description: Raw orders",
        "        name: orders",
    }
    check_equal(3, #decls)
    check_equal("orders", decls[1].name)
    check_equal("models", decls[1].kind)
    check_equal("raw", decls[2].dataset)
    check_equal("orders", decls[3].name)
    check_equal("raw", decls[3].dataset)
    local missing = properties.parse {
        "models:",
        "  - description: Nested lists cancel deferred names",
        "    columns:",
        "      - name: order_id",
        "    name: orders",
    }
    check_equal(0, #missing)
end)

it("parses source datasets and tables from properties YAML", function()
    local decls = properties.parse {
        "sources:",
        "  - name: billing",
        "    tables:",
        "      - name: orders",
        "      - name: invoices",
        "  - name: shop",
        "    tables:",
        "      - name: orders",
    }
    local tables = properties.find(decls, { kinds = { sources = true } })
    check_equal(3, #tables)
    check_equal("billing", tables[1].dataset)
    check_equal("orders", tables[1].name)
    check_equal(4, tables[1].lnum)
    local dupes = properties.find(decls, { kinds = { sources = true }, dataset = "shop", name = "orders" })
    check_equal(1, #dupes)
    check_equal(8, dupes[1].lnum)
    local missing = properties.find(decls, { kinds = { sources = true }, dataset = "billing", name = "nope" })
    check_equal(0, #missing)
end)

it("excludes artifact directories from declaration scans", function()
    local root = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(root .. "/models", "p")
    vim.fn.mkdir(root .. "/artifacts", "p")
    vim.fn.writefile({ "models:", "  - name: orders" }, root .. "/models/schema.yml")
    vim.fn.writefile({ "models:", "  - name: generated" }, root .. "/artifacts/schema.yml")
    local ok, err = xpcall(function()
        local excluded = properties.scan(root, root .. "/artifacts")
        check_equal(1, #excluded)
        check_equal("orders", excluded[1].name)
        check_equal(2, #properties.scan(root))
    end, debug.traceback)
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end)

it("detects single-line flow-style locations only", function()
    local issues = properties.detect_flow {
        "models: [{name: orders}]",
        "  - name: customers",
        '  description: "see [name: x] for details"',
        "  # models: [{name: commented}]",
        "  description: |",
        "    models: [{name: scalar}]",
        "sources:",
        "  - name: raw",
    }
    check_equal(1, #issues)
    check_equal(1, issues[1].lnum)
end)

it("resolves manifest-recorded YAML files", function()
    local known = properties.manifest_yaml "demo"
    local root = vim.fs.normalize(vim.fn.fnamemodify("demo", ":p"))
    for _, rel in ipairs {
        "models/schema.yml",
        "dataset/billing.yml",
        "dataset/shop.yml",
        "seeds/seeds.yml",
        "dbt_packages/snowplow_utils/models/utils.yml",
    } do
        check_true(known[vim.fs.joinpath(root, rel)] ~= nil, "expected manifest YAML: " .. rel)
    end
    check_equal(0, #vim.tbl_keys(properties.manifest_yaml "tests/dbt_project"))
end)

it("silences and synthesizes configured flow files", function()
    local config = require "dbtpal.config"
    local root = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(root .. "/models", "p")
    vim.fn.writefile({ "models: [{name: legacy}]" }, root .. "/models/flow.yml")
    vim.fn.writefile({ "models:", "  - name: orders" }, root .. "/models/schema.yml")
    local ok, err = xpcall(function()
        config.options.yaml_flow_files = {
            [root .. "/models/flow.yml"] = "legacy",
            [root .. "/models/missing.yml"] = "",
        }
        local decls, issues = properties.scan_with_report(root)
        check_equal(1, #issues)
        decls, issues = properties.apply_flow_config(root, decls, issues)
        check_equal(0, #issues)
        local synth = properties.find(decls, { kinds = { models = true }, name = "legacy" })
        check_equal(1, #synth)
        check_equal(1, synth[1].lnum)
        check_equal(true, synth[1].user_config)
        check_equal(1, #properties.find(decls, { kinds = { models = true }, name = "orders" }))
    end, debug.traceback)
    config.options.yaml_flow_files = {}
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end)

it("resolves flow file keys against the working directory", function()
    local config = require "dbtpal.config"
    -- Key is repo-relative, not project-relative: the project join misses
    -- (demo/demo/...) and the working-directory join must hit.
    config.options.yaml_flow_files = { ["demo/models/schema.yml"] = "orders" }
    local decls, issues = properties.scan_with_report "demo"
    decls, issues = properties.apply_flow_config("demo", decls, issues)
    config.options.yaml_flow_files = {}
    local found = properties.find(decls, { kinds = { models = true }, name = "orders" })
    check_equal(1, #found)
    check_true(found[1].user_config == true)
end)

it("tags scanned issues with manifest coverage", function()
    local root = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(root .. "/models", "p")
    vim.fn.mkdir(root .. "/target", "p")
    vim.fn.writefile({ "models:", "  - name: orders", "  - name: [{name: weird}]" }, root .. "/models/schema.yml")
    vim.fn.writefile({ "models: [{name: legacy}]" }, root .. "/models/flow.yml")
    vim.fn.writefile({
        vim.json.encode {
            nodes = {
                ["model.proj.orders"] = { name = "orders", package_name = "proj", patch_path = "models/schema.yml" },
            },
        },
    }, root .. "/target/manifest.json")
    local ok, err = xpcall(function()
        local _, issues = properties.scan_with_report(root)
        local known = {}
        for _, issue in ipairs(issues) do
            known[issue.file] = issue.known
        end
        check_equal(2, #issues)
        check_equal(true, known[root .. "/models/schema.yml"])
        check_equal(false, known[root .. "/models/flow.yml"])
    end, debug.traceback)
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end)

it("covers the demo project fixtures", function()
    local decls = properties.scan "demo"
    local billing = properties.find(decls, { kinds = { sources = true }, dataset = "billing", name = "orders" })
    check_equal(1, #billing)
    local shop = properties.find(decls, { kinds = { sources = true }, dataset = "shop", name = "orders" })
    check_equal(1, #shop)
    local models = properties.find(decls, { kinds = { models = true }, name = "orders" })
    check_equal(1, #models)
    local packaged = properties.find(decls, { kinds = { models = true }, name = "page_views" })
    check_equal(1, #packaged)
    local manifest = vim.json.decode(table.concat(vim.fn.readfile "demo/target/manifest.json", "\n"))
    local index = graph.build_index(vim.tbl_extend("force", manifest.nodes, manifest.sources))
    check_true(index.nodes["source.demo_project.billing.orders"] ~= nil)
    check_true(index.nodes["source.demo_project.shop.orders"] ~= nil)
    check_true(index.nodes["model.snowplow_utils.page_views"] ~= nil)
    check_equal(1, #index.dependents["source.demo_project.billing.orders"])
    local customers = index.nodes["model.demo_project.customers"]
    check_true(vim.tbl_contains(customers.deps, "model.snowplow_utils.page_views"))
end)

it("locates the declaration enclosing the cursor", function()
    local lines = {
        "models:",
        "  - name: orders",
        "    description: All orders",
        "  - name: customers",
    }
    local target = properties.declaration_at(lines, 3)
    check_equal("orders", target.name)
    check_equal("models", target.kind)
    check_true(properties.declaration_at(lines, 1) == nil, "expected no declaration above the block")
end)
