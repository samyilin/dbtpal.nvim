---@diagnostic disable: need-check-nil
local commands = require "dbtpal.commands"
local graph = require "dbtpal.graph"
local projects = require "dbtpal.projects"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"

before_each(
    function()
        require("dbtpal").setup {
            path_to_dbt_project = "./tests/dbt_project/",
            path_to_dbt_profiles_dir = "./tests/dbt_project/",
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

it("indexes graph nodes and walks lineage", function()
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
    local up = graph.upstream(index, "final")
    check_equal(2, #up)
    check_equal("stg", up[1].name)
    check_equal("raw", up[2].name)
    local down = graph.downstream(index, "raw")
    check_equal(2, #down)
    check_equal("stg", down[1].name)
    check_equal("final", down[2].name)
    local family = graph.family(index, "stg")
    check_equal(2, #family)
    check_equal("models/stg.sql", index.by_name["stg"][1].path)
end)

it("resolves sources by dataset", function()
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
    local entry, alternatives = graph.resolve(index, "orders", "shop")
    check_equal("shop", entry.source_name)
    check_equal(1, alternatives)
    local fallback = graph.resolve(index, "orders")
    check_true(fallback ~= nil, "expected a fallback match")
    local missing, no_alternatives = graph.resolve(index, "missing")
    check_true(missing == nil, "expected no match")
    check_equal(0, no_alternatives)
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

it("parses ref and source calls", function()
    local ref = graph.parse_model_ref "select * from {{ ref('orders') }}"
    check_equal("ref", ref.kind)
    check_equal("orders", ref.name)
    local source = graph.parse_model_ref '{{ source("raw", "orders") }}'
    check_equal("source", source.kind)
    check_equal("orders", source.name)
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
    check_true(projects.detect_dbt_project_dir "tests/dbt_project/models/example", "expected project detection")
    check_equal(vim.fn.getcwd() .. "/tests/dbt_project", require("dbtpal.config").options.path_to_dbt_project)
end)
