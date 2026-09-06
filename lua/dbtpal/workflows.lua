local execute = require "dbtpal.execute"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"

local M = {}

function M.select_models()
    resources.list({ resource_type = "model" }, function(items, err)
        if err then
            log.error(err.stderr ~= "" and err.stderr or "Unable to list dbt models")
            return
        end
        picker.select_many({ items = items, prompt = "Select dbt models" }, function(selected)
            if #selected == 0 then return end
            vim.ui.select(
                { "run", "test", "compile", "build" },
                { prompt = "Select dbt operation" },
                function(operation)
                    if not operation then return end
                    local selected_ids = selectors.from_resources(selected)
                    execute.run(operation, { "--select", table.concat(selected_ids, " ") }, function(result)
                        if result.code ~= 0 then log.error(result.stderr ~= "" and result.stderr or result.stdout) end
                    end)
                end
            )
        end)
    end)
end

return M
