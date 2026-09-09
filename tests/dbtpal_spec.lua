local commands = require "dbtpal.commands"
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

it("finds the dbt project directory", function()
    assert(projects.detect_dbt_project_dir "tests/dbt_project/models/example")
    assert.are.equal(vim.fn.getcwd() .. "/tests/dbt_project", require("dbtpal.config").options.path_to_dbt_project)
end)
