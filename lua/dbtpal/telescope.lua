local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local themes = require "telescope.themes"

local config = require "dbtpal.config"
local commands = require "dbtpal.commands"
local projects = require "dbtpal.projects"
local log = require "dbtpal.log"
local display = require "dbtpal.display"

local M = {}

M.dbt_models = function(tbl, opts)
    opts = opts or themes.get_dropdown {}

    pickers
        .new(opts, {
            prompt_title = "dbt",
            finder = finders.new_table {

                results = tbl,
                entry_maker = function(entry)
                    local res = vim.fn.json_decode(entry)

                    if res == nil then return {} end

                    return {
                        value = res.unique_id,
                        display = res.name,
                        ordinal = res.unique_id,
                        path = config.options.path_to_dbt_project .. "/" .. res.original_file_path,
                    }
                end,
            },

            sorter = conf.file_sorter(),
        })
        :find()
end

M.dbt_picker = function(opts)
    local cmd = "ls"
    local args = { "--resource-type=model", "--output=json", "--quiet" }

    if config.options.path_to_dbt_project == "" then
        local bpath = vim.fn.expand "%:p:h"
        if projects.detect_dbt_project_dir(bpath) == false then
            log.error "Couldn't detect a dbt project from this buffer. Try setting the dbt project directory manually"
            return
        end
    end

    local dbt_path, cmd_args = commands.build_path_args(cmd, args)
    vim.system(vim.list_extend({ dbt_path }, cmd_args), { text = true }, function(result)
        local response = vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
        local stderr = vim.split(result.stderr or "", "\n", { plain = true, trimempty = true })
        local code = result.code
        if code == 0 then
            log.trace(response)
            vim.schedule(function() M.dbt_models(response, opts) end)
        else
            table.insert(response, "Failed to run dbt command. Exit Code: " .. code .. "\n")
            local a = table.concat(cmd_args, " ") or ""
            local err = string.format("dbt command failed: %s %s\n\n", dbt_path, a)
            table.insert(response, "------------\n")
            table.insert(response, err)
            vim.list_extend(response, stderr)
            vim.schedule(function() display.popup(response) end)
        end
    end)
end

return M
