local execute = require "dbtpal.execute"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"
local display = require "dbtpal.display"
local config = require "dbtpal.config"

local M = {}

local function graph_picker(direction)
    local model = vim.fn.expand "%:t:r"
    local selector = require("dbtpal.selectors")[direction](model)
    resources.list({ resource_type = "model", selector = selector }, function(items, err)
        if err then
            log.error(err.stderr ~= "" and err.stderr or "Unable to list dbt models")
            return
        end
        picker.select({ items = items, prompt = "Select " .. direction .. " model" }, function(item)
            if not item then return end
            vim.ui.select({ "open", "run", "test", "compile", "build", "refresh" }, {
                prompt = item.name .. " action",
            }, function(action)
                if not action then return end
                if action == "refresh" then return graph_picker(direction) end
                if action == "open" then
                    local root = config.options.path_to_dbt_project
                    vim.cmd.edit(vim.fs.joinpath(root, item.path))
                    return
                end
                execute.run(action, { "--select", item.unique_id }, function(result)
                    if result.code ~= 0 then log.error(result.stderr ~= "" and result.stderr or result.stdout) end
                end)
            end)
        end)
    end)
end

M.select_upstream = function() graph_picker "upstream" end
M.select_downstream = function() graph_picker "downstream" end
M.select_family = function() graph_picker "family" end

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
                    vim.ui.select(
                        { "Notify only", "Open full output" },
                        { prompt = "Show dbt output?" },
                        function(output_mode)
                            if not output_mode then return end
                            local selected_ids = selectors.from_resources(selected)
                            execute.run(operation, { "--select", table.concat(selected_ids, " ") }, function(result)
                                if result.code ~= 0 then
                                    log.error(result.stderr ~= "" and result.stderr or result.stdout)
                                elseif output_mode == "Open full output" then
                                    display.popup(vim.split(result.stdout, "\n", { trimempty = true }))
                                end
                            end)
                        end
                    )
                end
            )
        end)
    end)
end

return M
