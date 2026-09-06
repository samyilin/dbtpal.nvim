--[[ this module exposes the interface of lua functions:
define here the lua functions that activate the plugin ]]

local main = require "dbtpal.main"
local config = require "dbtpal.config"

local M = {}

M.config = config
M.setup = config.setup

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
vim.api.nvim_create_user_command("DbtRun", function(cmd) main.run(cmd.args) end, { nargs = "?" })

vim.api.nvim_create_user_command("DbtRunAll", function(cmd) main.run_all(cmd.args) end, { nargs = "?" })

vim.api.nvim_create_user_command("DbtRunModel", function(cmd) main.run_model(cmd.args) end, { nargs = 1 })

vim.api.nvim_create_user_command("DbtTest", function(cmd) main.test(cmd.args) end, { nargs = "?" })

vim.api.nvim_create_user_command("DbtTestAll", function(cmd) main.test_all(cmd.args) end, { nargs = "?" })

vim.api.nvim_create_user_command("DbtTestModel", function(cmd) main.test_model(cmd.args) end, { nargs = 1 })

vim.api.nvim_create_user_command(
    "DbtCompile",
    function(cmd) main.compile(vim.fn.expand "%:t:r", cmd.args) end,
    { nargs = "?" }
)
vim.api.nvim_create_user_command("DbtCompileAll", function(cmd) main.compile(nil, cmd.args) end, { nargs = "?" })
vim.api.nvim_create_user_command("DbtCompileModel", function(cmd) main.compile(cmd.args) end, { nargs = 1 })
vim.api.nvim_create_user_command("DbtCompileFloat", function() main.compile_float() end, { nargs = 0 })

vim.api.nvim_create_user_command(
    "DbtBuild",
    function(cmd) main.build(vim.fn.expand "%:t:r", cmd.args) end,
    { nargs = "?" }
)
vim.api.nvim_create_user_command("DbtBuildAll", function(cmd) main.build(nil, cmd.args) end, { nargs = "?" })
vim.api.nvim_create_user_command("DbtBuildModel", function() main.build(vim.fn.expand "%:t:r") end, { nargs = 0 })
vim.api.nvim_create_user_command("DbtDebugAll", function(cmd) main.run_command("debug", cmd.args) end, { nargs = "?" })

local ok, _ = pcall(require, "telescope")
if ok then M.dbt_picker = require("dbtpal.telescope").dbt_picker end
return M
