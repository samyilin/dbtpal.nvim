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
    assert.are.equal("dbt", path)
    assert.are.same({
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
    assert.are.equal("+orders", selectors.upstream "orders")
    assert.are.equal("orders+", selectors.downstream "orders")
    assert.are.equal("+orders+", selectors.family "orders")
    assert.are.equal("tag:daily", selectors.tag "daily")
    assert.are.equal("path:models/staging", selectors.path "models/staging")
end)

it("normalizes dbt resources", function()
    local resource = resources.normalize {
        unique_id = "model.project.orders",
        name = "orders",
        resource_type = "model",
        original_file_path = "models/orders.sql",
        package_name = "project",
    }
    assert.are.equal("model.project.orders", resource.unique_id)
    assert.are.equal("models/orders.sql", resource.path)
    assert.are.equal("model", resource.resource_type)
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
    assert.are.equal(2, #up)
    assert.are.equal("stg", up[1].name)
    assert.are.equal("raw", up[2].name)
    local down = graph.downstream(index, "raw")
    assert.are.equal(2, #down)
    assert.are.equal("stg", down[1].name)
    assert.are.equal("final", down[2].name)
    local family = graph.family(index, "stg")
    assert.are.equal(2, #family)
    assert.are.equal("models/stg.sql", index.by_name["stg"][1].path)
end)

it("parses ref and source calls", function()
    local ref = graph.parse_model_ref "select * from {{ ref('orders') }}"
    assert.are.equal("ref", ref.kind)
    assert.are.equal("orders", ref.name)
    local source = graph.parse_model_ref '{{ source("raw", "orders") }}'
    assert.are.equal("source", source.kind)
    assert.are.equal("orders", source.name)
    assert(graph.parse_model_ref "select 1" == nil)
end)

it("resolves model names from yaml buffers", function()
    local context = require "dbtpal.context"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "models:", "  - name: orders" })
    vim.bo[buf].filetype = "yaml"
    vim.api.nvim_win_set_cursor(0, { 2, 11 })
    assert.are.equal("orders", context.current_model())
    vim.bo[buf].filetype = "lua"
    assert(context.current_model() == nil)
end)

it("finds the dbt project directory", function()
    assert(projects.detect_dbt_project_dir "tests/dbt_project/models/example")
    assert.are.equal(vim.fn.getcwd() .. "/tests/dbt_project", require("dbtpal.config").options.path_to_dbt_project)
end)
