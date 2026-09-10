local config = require "dbtpal.config"
local projects = require "dbtpal.projects"
local commands = require "dbtpal.commands"
local log = require "dbtpal.log"
local display = require "dbtpal.display"

local M = {}

M.run_command = function(cmd, args, output_mode) return M._create_job(cmd, args, output_mode) end

M._create_job = function(cmd, args, output_mode)
    log.info("dbt " .. cmd .. " started")
    if config.options.path_to_dbt_project == "" then
        local bpath = vim.fn.expand "%:p:h"
        if projects.detect_dbt_project_dir(bpath) == false then
            log.warn(
                "Could not detect dbt project dir, try setting it manually "
                    .. "or make sure this file is in a dbt project folder"
            )
            return
        end
    end

    local onexit = function(data, code)
        if (output_mode or config.options.output_mode) == "float" or code ~= 0 then display.popup(data) end
    end
    if args == "" then args = nil end
    local dbt_path, cmd_args = commands.build_path_args(cmd, args)
    local job = vim.system(vim.list_extend({ dbt_path }, cmd_args), { text = true }, function(result)
        local response = vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
        local stderr = vim.split(result.stderr or "", "\n", { plain = true, trimempty = true })
        local code = result.code
        if code == 1 then
            log.warn "dbt command encounted a handled error, see popup for details"
        elseif code >= 2 then
            table.insert(response, "Failed to run dbt command. Exit Code: " .. code .. "\n")
            local a = table.concat(cmd_args, " ") or ""
            local err = string.format("dbt command failed: %s %s\n\n", dbt_path, a)
            table.insert(response, "------------\n")
            table.insert(response, err)
            vim.list_extend(response, stderr)
        end
        if code == 0 then log.info("dbt " .. cmd .. " completed") end
        vim.schedule(function() onexit(response, code) end)
    end)
    return job
end

return M
