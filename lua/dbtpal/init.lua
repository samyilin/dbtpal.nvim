--[[ this module exposes the interface of lua functions:
define here the lua functions that activate the plugin ]]

local main = require "dbtpal.main"
local config = require "dbtpal.config"
local context = require "dbtpal.context"
local selectors = require "dbtpal.selectors"
local execute = require "dbtpal.execute"
local resources = require "dbtpal.resources"
local picker = require "dbtpal.picker"
local workflows = require "dbtpal.workflows"
local telescope_picker = require "dbtpal.picker_telescope"
local mini_picker = require "dbtpal.picker_mini"

local M = {}

local function current_model()
    if vim.bo.buftype ~= "" or (vim.bo.filetype ~= "dbt" and vim.bo.filetype ~= "sql") then
        vim.notify("This command requires a dbt model buffer", vim.log.levels.WARN)
        return nil
    end
    return vim.fn.expand "%:t:r"
end

local function selector(args)
    if not args or not args[1] or args[1] == "" then
        vim.notify("A dbt model selector is required", vim.log.levels.WARN)
        return nil
    end
    return args[1]
end

M.config = config
M.setup = config.setup
M.context = context
M.selectors = selectors
M.execute = execute.run
M.list_resources = resources.list
M.picker = picker
M.select_models = workflows.select_models
M.select_upstream = workflows.select_upstream
M.select_downstream = workflows.select_downstream
M.select_family = workflows.select_family
telescope_picker.setup(picker)
mini_picker.setup(picker)

M.run = main.run
M.run_all = main.run_all
M.run_model = main.run_model
M.run_children = main.run_children
M.run_parents = main.run_parents
M.run_family = main.run_family

M.test = main.test
M.test_all = main.test_all
M.test_model = main.test_model

M.compile = main.compile
M.compile_float = main.compile_float
M.build = main.build
M.debug_all = function() return main.run_command "debug" end

M.run_command = main.run_command

-- Commands
vim.api.nvim_create_user_command("DbtRun", function(cmd)
    if current_model() then main.run(cmd.fargs) end
end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtRunAll", function(cmd) main.run_all(cmd.fargs) end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtRunModel", function(cmd)
    local value = selector(cmd.fargs)
    if value then main.run_model(value) end
end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtTest", function(cmd)
    if current_model() then main.test(cmd.fargs) end
end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtTestAll", function(cmd) main.test_all(cmd.fargs) end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtTestModel", function(cmd)
    local value = selector(cmd.fargs)
    if value then main.test_model(value) end
end, { nargs = "*" })

vim.api.nvim_create_user_command("DbtCompile", function(cmd)
    if vim.bo.buftype ~= "" or (vim.bo.filetype ~= "dbt" and vim.bo.filetype ~= "sql") then
        vim.notify("DbtCompile requires a dbt model buffer; use :DbtCompileAll for the project", vim.log.levels.WARN)
        return
    end
    main.compile(vim.fn.expand "%:t:r", cmd.fargs)
end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtCompileAll", function(cmd) main.compile(nil, cmd.fargs) end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtCompileModel", function(cmd)
    local value = selector(cmd.fargs)
    if value then main.compile(value) end
end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtCompileFloat", function() main.compile_float() end, { nargs = 0 })

vim.api.nvim_create_user_command("DbtBuild", function(cmd)
    if current_model() then main.build(vim.fn.expand "%:t:r", cmd.fargs) end
end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtBuildAll", function(cmd) main.build(nil, cmd.fargs) end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtDebugAll", function(cmd) main.run_command("debug", cmd.fargs) end, { nargs = "*" })
vim.api.nvim_create_user_command("DbtSelectModels", function() workflows.select_models() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectUpstream", function() workflows.select_upstream() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectDownstream", function() workflows.select_downstream() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectFamily", function() workflows.select_family() end, { nargs = 0 })

local ok, _ = pcall(require, "telescope")
if ok then M.dbt_picker = require("dbtpal.telescope").dbt_picker end
return M
