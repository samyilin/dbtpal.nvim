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

local function has_selector(args)
    for _, arg in ipairs(args or {}) do
        if arg == "--select" or arg == "-s" then return true end
    end
    return false
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

M.run_command = main.run_command

-- Commands
vim.api.nvim_create_user_command("Dbt", function(cmd)
    local args = vim.deepcopy(cmd.fargs)
    local command = table.remove(args, 1)
    if not command then
        vim.notify("Usage: :Dbt <run|test|compile|build|debug|...> [dbt arguments]", vim.log.levels.INFO)
        return
    end
    local model_commands = { run = true, test = true, compile = true, build = true }
    if config.options.use_current_model and model_commands[command] and not has_selector(args) then
        local model = current_model()
        if not model then return end
        vim.list_extend(args, { "--select", model })
    end
    main.run_command(command, args, cmd.bang == 1 and "float" or nil)
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("DbtSelectModels", function() workflows.select_models() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectUpstream", function() workflows.select_upstream() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectDownstream", function() workflows.select_downstream() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtSelectFamily", function() workflows.select_family() end, { nargs = 0 })

local ok, _ = pcall(require, "telescope")
if ok then M.dbt_picker = require("dbtpal.telescope").dbt_picker end
return M
