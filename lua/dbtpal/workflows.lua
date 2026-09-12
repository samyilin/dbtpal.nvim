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
local walk_loop

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

local graph_resource_types = { model = true, seed = true, snapshot = true, source = true }

local function filter_graph_items(items, model)
    return vim.tbl_filter(
        function(item) return item.name ~= model and graph_resource_types[item.resource_type] end,
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

---Pure step computation for the picker walk. Returns labeled neighbors.
function M.walk_neighbors(index, center)
    local items = {}
    for _, entry in ipairs(graph.upstream(index, center)) do
        items[#items + 1] = {
            direction = "up",
            name = entry.name,
            resource_type = entry.resource_type,
            path = entry.path,
            unique_id = entry.unique_id,
        }
    end
    for _, entry in ipairs(graph.downstream(index, center)) do
        items[#items + 1] = {
            direction = "down",
            name = entry.name,
            resource_type = entry.resource_type,
            path = entry.path,
            unique_id = entry.unique_id,
        }
    end
    return filter_graph_items(items, center)
end

local function walk_format(item)
    if item.back then return item.name end
    return (item.direction == "up" and "↑ " or "↓ ") .. item.name
end

local function walk_act(project, index, item, center, trail)
    local entry = item
    vim.ui.select({ "step into", "open", "run", "test", "compile", "build" }, {
        prompt = item.name .. " action",
    }, function(action)
        if not action then return end
        if action == "step into" then
            trail[#trail + 1] = center
            walk_loop(project, index, item.name, trail)
            return
        end
        if action == "open" then
            if not entry.path then
                log.warn("No file path for " .. item.name)
                return
            end
            vim.cmd.edit(vim.fs.joinpath(project, entry.path))
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
end

walk_loop = function(project, index, center, trail)
    local neighbors = M.walk_neighbors(index, center)
    if #neighbors == 0 then
        log.info(center .. " has no further neighbours")
        local entries = index.by_name[center] or {}
        walk_act(project, index, entries[1] or { name = center }, center, trail)
        return
    end
    local choices = {}
    if #trail > 0 then choices[#choices + 1] = { back = true, name = ".. back to " .. trail[#trail] } end
    vim.list_extend(choices, neighbors)
    picker.select(
        { items = choices, prompt = center .. " (" .. #trail .. " steps)", format_item = walk_format },
        function(item)
            if not item then return end
            if item.back then
                local prev = table.remove(trail)
                walk_loop(project, index, prev, trail)
                return
            end
            walk_act(project, index, item, center, trail)
        end
    )
end

local function walk_begin(name)
    local project = require_project()
    if not project then return end
    graph.load(project, function(index, err)
        if err then
            log.error(err)
            return
        end
        if not index.by_name[name] then
            log.warn(name .. " is not a known model")
            return
        end
        walk_loop(project, index, name, {})
    end)
end

function M.walk(start)
    if start and start ~= "" then
        walk_begin(start)
        return
    end
    local model = context.current_model()
    if model then
        walk_begin(model)
        return
    end
    local project = require_project()
    if not project then return end
    resources.list({ resource_type = "model" }, function(items, err)
        if err then
            log.error(err.stderr ~= "" and err.stderr or "Unable to list dbt models")
            return
        end
        picker.select({ items = items, prompt = "Walk from" }, function(item)
            if not item then return end
            walk_begin(item.name)
        end)
    end)
end

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
        local entry, alternatives = graph.resolve(index, ref.name, ref.source)
        if not entry then
            log.warn("Unknown model: " .. ref.name)
            return
        end
        if alternatives > 0 then log.info("Multiple matches for " .. ref.name .. "; opening the best match") end
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
