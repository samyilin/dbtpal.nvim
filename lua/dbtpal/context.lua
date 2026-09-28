local projects = require "dbtpal.projects"

local M = {}

function M.current_model()
    local filetype = vim.bo.filetype
    if vim.bo.buftype ~= "" then return nil end
    if filetype == "sql" or filetype == "dbt" or filetype == "csv" then
        local name = vim.fn.expand "%:t:r"
        return name ~= "" and name or nil
    end
    if filetype == "yaml" or filetype == "yml" then
        local word = vim.fn.expand "<cword>"
        return word ~= "" and word or nil
    end
    return nil
end

function M.require_model_buffer()
    local model = M.current_model()
    if not model then
        vim.notify("This command requires a dbt model buffer", vim.log.levels.WARN)
        return nil
    end
    return model
end

function M.project_for_buffer() return projects.resolve() end

return M
