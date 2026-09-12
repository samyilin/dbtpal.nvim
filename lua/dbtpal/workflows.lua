local execute = require "dbtpal.execute"
local graph = require "dbtpal.graph"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"
local display = require "dbtpal.display"
local context = require "dbtpal.context"

local M = {}

local walk_loop

local function require_project()
    local project = graph.project_dir() or context.project_for_buffer()
    if not project then log.warn "Could not detect dbt project dir" end
    return project
end

---List models from the graph cache, falling back to live dbt ls.
---Calls back with (items, err).
local function list_models(project, callback)
    graph.load(project, function(index, err)
        if err then
            resources.list({ resource_type = "model" }, function(items, list_err)
                if list_err then
                    callback(nil, list_err.stderr ~= "" and list_err.stderr or "Unable to list dbt models")
                    return
                end
                callback(items, nil)
            end)
            return
        end
        callback(graph.models(index), nil)
    end)
end

local graph_resource_types = { model = true, seed = true, snapshot = true, source = true }

local function filter_graph_items(items, model)
    return vim.tbl_filter(
        function(item) return item.name ~= model and graph_resource_types[item.resource_type] end,
        items
    )
end

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
    local label = item.name
    if item.direction ~= nil then label = (item.direction == "up" and "↑ " or "↓ ") .. label end
    if item.dist ~= nil then label = label .. " (+" .. item.dist .. ")" end
    return label
end

---Toggle an entry in the tagged set. Returns true when now tagged.
function M.toggle_tag(tagged, entry)
    local key = entry.unique_id or entry.name
    for i, existing in ipairs(tagged) do
        if (existing.unique_id or existing.name) == key then
            table.remove(tagged, i)
            return false
        end
    end
    tagged[#tagged + 1] = entry
    return true
end

function M.is_tagged(tagged, entry)
    local key = entry.unique_id or entry.name
    for _, existing in ipairs(tagged) do
        if (existing.unique_id or existing.name) == key then return true end
    end
    return false
end

local function execute_with_output(operation, select_value, on_cancel)
    vim.ui.select({ "Notify only", "Open full output" }, {
        prompt = "Show dbt output?",
    }, function(output_mode)
        if not output_mode then
            if on_cancel then on_cancel() end
            return
        end
        execute.run(operation, { "--select", select_value }, function(result)
            if result.code ~= 0 then
                log.error(result.stderr ~= "" and result.stderr or result.stdout)
            elseif output_mode == "Open full output" then
                display.popup(vim.split(result.stdout, "\n", { trimempty = true }))
            end
        end)
    end)
end

local function walk_act(project, index, item, center, trail, dist, tagged)
    local tag_label = M.is_tagged(tagged, item) and "untag" or "tag"
    vim.ui.select({ "step into", tag_label, "open", "run", "test", "compile", "build" }, {
        prompt = item.name .. " action",
    }, function(action)
        if not action then return end
        if action == "step into" then
            trail[#trail + 1] = center
            walk_loop(project, index, item.name, trail, dist, tagged)
            return
        end
        if action == "tag" or action == "untag" then
            M.toggle_tag(tagged, item)
            walk_loop(project, index, center, trail, dist, tagged)
            return
        end
        if action == "open" then
            if not item.path then
                log.warn("No file path for " .. item.name)
                return
            end
            vim.cmd.edit(vim.fs.joinpath(project, item.path))
            return
        end
        execute_with_output(action, item.name)
    end)
end

local tagged_operate

local function tagged_submenu(project, index, center, trail, dist, tagged)
    local choices = { { operate_all = true, name = "● operate on all (" .. #tagged .. ")" } }
    for _, entry in ipairs(tagged) do
        choices[#choices + 1] = entry
    end
    picker.select({ items = choices, prompt = "Tagged", format_item = walk_format }, function(item)
        if not item then
            walk_loop(project, index, center, trail, dist, tagged)
            return
        end
        if item.operate_all then
            tagged_operate(project, tagged, function() tagged_submenu(project, index, center, trail, dist, tagged) end)
            return
        end
        walk_act(project, index, item, center, trail, dist, tagged)
    end)
end

tagged_operate = function(project, tagged, on_cancel)
    if #tagged == 0 then return end
    vim.ui.select({ "open all", "run", "test", "compile", "build" }, {
        prompt = "Operation for " .. #tagged .. " tagged models",
    }, function(operation)
        if not operation then
            if on_cancel then on_cancel() end
            return
        end
        if operation == "open all" then
            local opened = 0
            for _, entry in ipairs(tagged) do
                if entry.path then
                    opened = opened + 1
                    if opened == 1 then
                        vim.cmd.edit(vim.fs.joinpath(project, entry.path))
                    else
                        vim.cmd.badd(vim.fs.joinpath(project, entry.path))
                    end
                end
            end
            if opened == 0 then log.warn "No tagged models have file paths" end
            return
        end
        local names = {}
        for _, entry in ipairs(tagged) do
            names[#names + 1] = entry.name
        end
        execute_with_output(operation, table.concat(names, " "), on_cancel)
    end)
end

walk_loop = function(project, index, center, trail, dist, tagged)
    local neighbors = M.walk_neighbors(index, center)
    for _, item in ipairs(neighbors) do
        item.dist = dist[item.unique_id]
    end
    if #neighbors == 0 and #tagged == 0 then
        log.info(center .. " has no further neighbours")
        local entries = index.by_name[center] or {}
        walk_act(project, index, entries[1] or { name = center }, center, trail, dist, tagged)
        return
    end
    local choices = {}
    if #trail > 0 then choices[#choices + 1] = { back = true, name = ".. back to " .. trail[#trail] } end
    if #tagged > 0 then choices[#choices + 1] = { tagged = true, name = "★ tagged (" .. #tagged .. ")" } end
    vim.list_extend(choices, neighbors)
    local backend = picker.get()
    local crumbs = {}
    local compressed, truncated = graph.compress_trail(vim.list_extend(vim.deepcopy(trail), { center }), 3)
    for _, name in ipairs(compressed) do
        local entries = index.by_name[name] or {}
        local d = entries[1] and dist[entries[1].unique_id] or nil
        crumbs[#crumbs + 1] = d == nil and name or (name .. " (+" .. d .. ")")
    end
    local prompt = (truncated and "... > " or "") .. table.concat(crumbs, " > ")
    local function step_into(item)
        if item.back then
            local prev = table.remove(trail)
            walk_loop(project, index, prev, trail, dist, tagged)
            return
        end
        if item.tagged then
            tagged_submenu(project, index, center, trail, dist, tagged)
            return
        end
        trail[#trail + 1] = center
        walk_loop(project, index, item.name, trail, dist, tagged)
    end
    if backend.action_key then
        picker.select({
            items = choices,
            prompt = prompt .. " [" .. backend.action_key .. " actions]",
            format_item = walk_format,
            on_action = function(item)
                if item.back or item.tagged then return end
                walk_act(project, index, item, center, trail, dist, tagged)
            end,
        }, function(item)
            if not item then return end
            step_into(item)
        end)
    else
        picker.select({ items = choices, prompt = prompt, format_item = walk_format }, function(item)
            if not item then return end
            if item.back then
                local prev = table.remove(trail)
                walk_loop(project, index, prev, trail, dist, tagged)
                return
            end
            if item.tagged then
                tagged_submenu(project, index, center, trail, dist, tagged)
                return
            end
            walk_act(project, index, item, center, trail, dist, tagged)
        end)
    end
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
        walk_loop(project, index, name, {}, graph.distances(index, name), {})
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
    list_models(project, function(items, err)
        if err then
            log.error(err)
            return
        end
        if #items == 0 then
            log.warn "No models found"
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
    local project = require_project()
    if not project then return end
    list_models(project, function(items, err)
        if err then
            log.error(err)
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
                    execute_with_output(operation, table.concat(selected_ids, " "))
                end
            )
        end)
    end)
end

return M
