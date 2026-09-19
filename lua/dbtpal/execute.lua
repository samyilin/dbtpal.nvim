local commands = require "dbtpal.commands"
local config = require "dbtpal.config"
local log = require "dbtpal.log"

local M = {}

---Run a dbt command. opts.on_chunk(data, stream) and callback(result)
---run on the main loop. Streaming also preserves the complete result.
function M.run(command, args, callback, opts)
    local dbt_path, cmd_args = commands.build_path_args(command, args or {})
    local chunks = { stdout = {}, stderr = {} }
    local on_chunk = opts and opts.on_chunk
    local function reader(stream)
        if not on_chunk then return nil end
        return function(err, data)
            if err then chunks.stderr[#chunks.stderr + 1] = tostring(err) .. "\n" end
            if not data then return end
            chunks[stream][#chunks[stream] + 1] = data
            vim.schedule(function() on_chunk(data, stream) end)
        end
    end
    log.info("dbt " .. command .. " started")
    local function on_exit(result)
        vim.schedule(function()
            if result.code == 0 then log.info("dbt " .. command .. " completed") end
            callback {
                code = result.code,
                signal = result.signal,
                stdout = result.stdout or table.concat(chunks.stdout),
                stderr = result.stderr or table.concat(chunks.stderr),
            }
        end)
    end
    local ok, job = pcall(vim.system, vim.list_extend({ dbt_path }, cmd_args), {
        text = true,
        env = config.options.env,
        stdout = reader "stdout",
        stderr = reader "stderr",
    }, on_exit)
    if not ok then
        if on_chunk then vim.schedule(function() on_chunk(tostring(job) .. "\n", "stderr") end) end
        on_exit { code = 127, signal = 0, stderr = tostring(job) }
        return nil
    end
    return job
end

return M
