local config = require "dbtpal.config"
local context = require "dbtpal.context"
local execute = require "dbtpal.execute"
local quickfix = require "dbtpal.quickfix"
local log = require "dbtpal.log"
local display = require "dbtpal.display"

local M = {}

function M.run_command(cmd, args, output, project)
    project = project or context.project_for_buffer()
    if not project then
        log.warn "Could not detect dbt project dir; set path_to_dbt_project or open a file in a dbt project"
        return
    end
    project = vim.fs.normalize(vim.fn.fnamemodify(project, ":p"))
    local mode = output or config.options.output
    local float_mode = mode == "float" or mode == "stream"
    local streaming = mode == "stream" and display.stream() or nil
    if args == "" then args = nil end
    local run_opts = streaming and { on_chunk = streaming.push } or {}
    run_opts.project = project
    return execute.run(cmd, args, function(result)
        local response = vim.split(result.stdout .. "\n" .. result.stderr, "\n", { trimempty = true })
        if result.code ~= 0 then
            local status = "dbt " .. cmd .. " failed (exit " .. result.code .. ")"
            response[#response + 1] = status
            log.warn(status)
            if streaming then streaming.push("\r\n" .. status .. "\r\n") end
        end
        quickfix.publish(cmd, result, project)
        if streaming then
            streaming.finish()
        elseif float_mode or result.code ~= 0 then
            display.popup(response)
        end
    end, run_opts)
end

return M
