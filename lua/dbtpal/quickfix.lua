local config = require "dbtpal.config"
local log = require "dbtpal.log"

local M = {}

---Parse dbt's text test-failure summaries, including generic YAML tests.
function M.parse(lines, project)
    local entries = {}
    for _, line in ipairs(lines or {}) do
        line = line:gsub("\27%[[%d;]*m", "")
        local location = line:match "Failure in test .- %((.-)%)" or line:match "Error in test .- %((.-)%)"
        if location then
            local path, lnum = location:match "^(.*):(%d+)$"
            path = path or location
            if path:match "%.sql$" or path:match "%.ya?ml$" then
                if not path:match "^/" and not path:match "^%a:[/\\]" then path = vim.fs.joinpath(project, path) end
                entries[#entries + 1] = { filename = path, lnum = tonumber(lnum) or 1, text = line, type = "E" }
            end
        end
    end
    return entries
end

function M.publish(command, result, project)
    if not config.options.use_quickfix or (command ~= "test" and command ~= "build") then return end
    result = result or {}
    local title = "dbt " .. command
    local entries = M.parse(vim.split((result.stdout or "") .. "\n" .. (result.stderr or ""), "\n"), project)
    if #entries > 0 then
        vim.fn.setqflist({}, " ", { title = title, items = entries })
        log.info(#entries .. " failure(s) sent to quickfix; use :copen to view")
    elseif result.code == 0 and vim.fn.getqflist({ title = 1 }).title == title then
        vim.fn.setqflist({}, "r", { title = title, items = {} })
    end
end

return M
