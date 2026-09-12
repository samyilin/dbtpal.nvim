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

local function has_selector(args)
    for _, arg in ipairs(args or {}) do
        if arg == "--select" or arg == "-s" then return true end
    end
    return false
end

M.config = config
M.setup = config.setup
M.context = context
M.selectors = selectors
M.execute = execute.run
M.list_resources = resources.list
M.picker = picker
M.select_models = workflows.select_models
M.goto_model = workflows.goto_model
M.refresh_graph = workflows.refresh_graph
M.walk = workflows.walk
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
        local model = context.require_model_buffer()
        if not model then return end
        vim.list_extend(args, { "--select", model })
    end
    main.run_command(command, args, cmd.bang == 1 and "float" or nil)
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("DbtSelectModels", function() workflows.select_models() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtGotoModel", function() workflows.goto_model() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtRefreshGraph", function() workflows.refresh_graph() end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtWalk", function(cmd) workflows.walk(cmd.args) end, { nargs = "?" })

return M
