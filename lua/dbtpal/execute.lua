local commands = require "dbtpal.commands"
local log = require "dbtpal.log"

local M = {}

function M.run(command, args, callback)
    local dbt_path, cmd_args = commands.build_path_args(command, args or {})
    log.info("dbt " .. command .. " started")
    return vim.system(vim.list_extend({ dbt_path }, cmd_args), { text = true }, function(result)
        vim.schedule(function()
            if result.code == 0 then log.info("dbt " .. command .. " completed") end
            callback {
                code = result.code,
                signal = result.signal,
                stdout = result.stdout or "",
                stderr = result.stderr or "",
            }
        end)
    end)
end

return M
