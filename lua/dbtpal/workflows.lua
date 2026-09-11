local execute = require "dbtpal.execute"
local graph = require "dbtpal.graph"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"
local display = require "dbtpal.display"
local context = require "dbtpal.context"

local M = {}

local graph_picker

local function require_project()
    local project = graph.project_dir() or context.project_for_buffer()
    if not project then log.warn "Could not detect dbt project dir" end
    return project
end

local function graph_actions(items, direction, project)
    picker.select({ items = items, prompt = "Select " .. direction .. " model" }, function(item)
        if not item then return end
        vim.ui.select({ "open", "run", "test", "compile", "build", "refresh" }, {
            prompt = item.name .. " action",
        }, function(action)
            if not action then return end
            if action == "refresh" then return graph_picker(direction) end
            if action == "open" then
                vim.cmd.edit(vim.fs.joinpath(project, item.path))
                return
            end
            vim.ui.select({ "Notify only", "Open full output" }, {
                prompt = "Show dbt output?",
            }, function(output_mode)
                if not output_mode then return end
                execute.run(action, { "--select", item.name }, function(result)
                    if result.code ~= 0 then
                        log.error(result.stderr ~= "" and result.stderr or result.stdout)
                    elseif output_mode == "Open full output" then
                        display.popup(vim.split(result.stdout, "\n", { trimempty = true }))
                    end
                end)
            end)
        end)
    end)
end

local function filter_graph_items(items, model)
    return vim.tbl_filter(
        function(item)
            return item.name ~= model
                and (item.resource_type == "model" or item.resource_type == "seed" or item.resource_type == "snapshot")
        end,
        items
    )
end

graph_picker = function(direction)
    local model = context.require_model_buffer()
    if not model then return end
    local project = require_project()
    if not project then return end
    graph.load(project, function(index, err)
        if err then
            log.warn "Graph cache unavailable, falling back to dbt ls"
            local selector = selectors[direction](model)
            resources.list({ selector = selector }, function(items, list_err)
                if list_err then
                    log.error(list_err.stderr ~= "" and list_err.stderr or "Unable to list dbt models")
                    return
                end
                items = filter_graph_items(items, model)
                if #items == 0 then
                    log.info("No " .. direction .. " models found for " .. model)
                    return
                end
                graph_actions(items, direction, project)
            end)
            return
        end
        local items = filter_graph_items(graph[direction](index, model), model)
        if #items == 0 then
            log.info("No " .. direction .. " models found for " .. model)
            return
        end
        graph_actions(items, direction, project)
    end)
end

M.select_upstream = function() graph_picker "upstream" end
M.select_downstream = function() graph_picker "downstream" end
M.select_family = function() graph_picker "family" end

function M.goto_model()
    local project = require_project()
    if not project then return end
    local ref = graph.parse_model_ref(vim.api.nvim_get_current_line())
    if not ref then
        log.warn "No ref() or source() call on the current line"
        return
    end
    graph.load(project, function(index, err)
        if err then
            log.error(err)
            return
        end
        local entries = index.by_name[ref.name] or {}
        if #entries == 0 then
            log.warn("Unknown model: " .. ref.name)
            return
        end
        if #entries > 1 then log.info("Multiple matches for " .. ref.name .. "; opening the first") end
        local entry = entries[1]
        if not entry.path then
            log.warn("No file path for " .. ref.name)
            return
        end
        vim.cmd.edit(vim.fs.joinpath(project, entry.path))
    end)
end

function M.refresh_graph()
    local project = require_project()
    if not project then return end
    graph.refresh(project, function(_, err)
        if err then
            log.error(err)
        else
            log.info "dbt graph cache refreshed"
        end
    end)
end

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
