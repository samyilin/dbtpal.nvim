local graph = require "dbtpal.graph"
local graph_cache = require "dbtpal.graph_cache"
local main = require "dbtpal.main"
local config = require "dbtpal.config"
local resources = require "dbtpal.resources"
local selectors = require "dbtpal.selectors"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"
local context = require "dbtpal.context"
local projects = require "dbtpal.projects"
local properties = require "dbtpal.properties"
local goto_nav = require "dbtpal.goto"

local M = {}

local function require_project()
    local project = context.project_for_buffer()
    if not project then log.warn "Could not detect dbt project dir" end
    return project
end

---List models from the graph cache, falling back to live dbt ls.
---Calls back with (items, err).
local function list_models(project, callback)
    graph_cache.load(project, function(index, err)
        if err then
            resources.list({ resource_type = "model", project = project }, function(items, list_err)
                if list_err then
                    callback(nil, list_err.stderr ~= "" and list_err.stderr or "Unable to list dbt models")
                    return
                end
                callback(items, nil)
            end)
            return
        end
        callback(resources.excluding(graph.models(index)), nil)
    end)
end

local walk_loop

---Pure step computation for the picker walk. Returns labeled neighbors.
---Accepts a unique_id or, for compatibility, a bare resource name (which
---unions the direct neighbors of every match).
function M.walk_neighbors(index, center)
    local ids = {}
    if index.nodes[center] then
        ids = { center }
    else
        for _, entry in ipairs(graph.matches(index, center)) do
            ids[#ids + 1] = entry.unique_id
        end
    end
    local items, seen = {}, {}
    for _, id in ipairs(ids) do
        for _, direction in ipairs { "up", "down" } do
            for _, entry in ipairs(graph.neighbors(index, id, direction)) do
                if graph.resource_types[entry.resource_type] and not seen[entry.unique_id .. direction] then
                    seen[entry.unique_id .. direction] = true
                    items[#items + 1] = vim.tbl_extend("force", entry, { direction = direction })
                end
            end
        end
    end
    return resources.excluding(items)
end

local function walk_format(item)
    if item.back or item.yml then return item.name end
    local label = graph.label(item)
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

local function execute_with_output(project, operation, select_value, on_cancel)
    vim.ui.select({ "Notify only", "Open full output" }, {
        prompt = "Show dbt output?",
    }, function(choice)
        if not choice then
            if on_cancel then on_cancel() end
            return
        end
        main.run_command(
            operation,
            { "--select", select_value },
            choice == "Open full output" and (config.options.output == "stream" and "stream" or "float") or "notify",
            project
        )
    end)
end

local function walk_act(project, index, item, center, trail, dist, tagged)
    local tag_label = M.is_tagged(tagged, item) and "untag" or "tag"
    local actions = { tag_label, "open", "run", "test", "compile", "build" }
    if item.unique_id ~= center then table.insert(actions, 1, "step into") end
    vim.ui.select(actions, {
        prompt = graph.label(item) .. " action",
    }, function(action)
        if not action then return end
        if action == "step into" then
            trail[#trail + 1] = center
            walk_loop(project, index, item.unique_id, trail, dist, tagged)
            return
        end
        if action == "tag" or action == "untag" then
            M.toggle_tag(tagged, item)
            walk_loop(project, index, center, trail, dist, tagged)
            return
        end
        if action == "open" then
            projects.open_resource(project, item, index.layout)
            return
        end
        execute_with_output(project, action, selectors.from_resource(item))
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
            tagged_operate(
                project,
                index,
                tagged,
                function() tagged_submenu(project, index, center, trail, dist, tagged) end
            )
            return
        end
        walk_act(project, index, item, center, trail, dist, tagged)
    end)
end

tagged_operate = function(project, index, tagged, on_cancel)
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
                if projects.open_resource(project, entry, index.layout, opened > 0 and "badd" or nil) then
                    opened = opened + 1
                end
            end
            if opened == 0 then log.warn "No tagged models have file paths" end
            return
        end
        execute_with_output(project, operation, table.concat(selectors.from_resources(tagged), " "), on_cancel)
    end)
end

walk_loop = function(project, index, center, trail, dist, tagged)
    local neighbors = M.walk_neighbors(index, center)
    for _, item in ipairs(neighbors) do
        item.dist = dist[item.unique_id]
    end
    local isolated = #neighbors == 0 and #tagged == 0 and #trail == 0
    if isolated then log.info(graph.label(index.nodes[center]) .. " has no further neighbours") end
    local choices = {}
    if #trail > 0 then
        choices[#choices + 1] = { back = true, name = ".. back to " .. graph.label(index.nodes[trail[#trail]]) }
    end
    if #tagged > 0 then choices[#choices + 1] = { tagged = true, name = "★ tagged (" .. #tagged .. ")" } end
    -- The current node's parallel YAML declaration is listed here, never
    -- for upstream/downstream neighbours: it is an attribute, not an edge.
    choices[#choices + 1] = { yml = true, name = "· yaml declaration" }
    vim.list_extend(choices, neighbors)
    local backend = picker.get()
    local crumbs = {}
    local compressed, truncated = graph.compress_trail(vim.list_extend(vim.deepcopy(trail), { center }), 3)
    for _, id in ipairs(compressed) do
        local name = graph.label(index.nodes[id])
        local d = dist[id]
        crumbs[#crumbs + 1] = d == nil and name or (name .. " (+" .. d .. ")")
    end
    local prompt = (truncated and "... > " or "") .. table.concat(crumbs, " > ")
    local function step_into(item)
        if item.yml then
            goto_nav.goto_declaration(project, index.nodes[center])
            return
        end
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
        walk_loop(project, index, item.unique_id, trail, dist, tagged)
    end
    -- Cancelling on an isolated node falls back to the action menu, the
    -- previous behaviour for leaves.
    local function on_cancel()
        if isolated then walk_act(project, index, index.nodes[center], center, trail, dist, tagged) end
    end
    if backend.action_key then
        picker.select({
            items = choices,
            prompt = prompt .. " [" .. backend.action_key .. " actions]",
            format_item = walk_format,
            on_action = function(item)
                if item.back or item.tagged or item.yml then return end
                walk_act(project, index, item, center, trail, dist, tagged)
            end,
        }, function(item)
            if not item then
                on_cancel()
                return
            end
            step_into(item)
        end)
    else
        picker.select({ items = choices, prompt = prompt, format_item = walk_format }, function(item)
            if not item then
                on_cancel()
                return
            end
            if item.back then
                local prev = table.remove(trail)
                walk_loop(project, index, prev, trail, dist, tagged)
                return
            end
            if item.tagged then
                tagged_submenu(project, index, center, trail, dist, tagged)
                return
            end
            if item.yml then
                step_into(item)
                return
            end
            walk_act(project, index, item, center, trail, dist, tagged)
        end)
    end
end

local function walk_begin(project, reference, opts)
    opts = opts or {}
    graph_cache.load(project, function(index, err)
        if err then
            log.error(err)
            return
        end
        local candidates = reference and graph.matches(index, reference) or vim.tbl_values(index.nodes)
        candidates = vim.tbl_filter(
            function(entry)
                return graph.resource_types[entry.resource_type]
                    and (not opts.kind or entry.resource_type == opts.kind)
                    and (not opts.dataset or entry.source_name == opts.dataset)
            end,
            candidates
        )
        if opts.file then
            local local_entries = vim.tbl_filter(function(entry)
                local path = projects.resource_path(project, entry, index.layout)
                return path and vim.fn.resolve(path) == vim.fn.resolve(opts.file)
            end, candidates)
            if #local_entries > 0 then candidates = local_entries end
        end
        if #candidates == 0 then
            log.warn((reference or opts.dataset or "Resource") .. " is not in the graph")
            return
        end
        local function begin(entry)
            if not entry then return end
            local id = entry.unique_id
            walk_loop(project, index, id, {}, graph.distances(index, id), {})
        end
        if #candidates == 1 then
            begin(candidates[1])
        else
            picker.select({ items = candidates, prompt = "Walk from", format_item = graph.label }, begin)
        end
    end)
end

function M.walk(start)
    local project = require_project()
    if not project then return end
    if start and start ~= "" then
        walk_begin(project, start)
        return
    end
    local model = context.current_model()
    local filetype = vim.bo.filetype
    if model and (filetype == "yaml" or filetype == "yml") then
        local decl =
            properties.declaration_at(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(0)[1])
        if decl then
            walk_begin(
                project,
                decl.name,
                { kind = decl.kind:sub(1, -2), dataset = decl.dataset, file = vim.api.nvim_buf_get_name(0) }
            )
            return
        end
    end
    if model then
        walk_begin(project, model, { file = vim.api.nvim_buf_get_name(0), kind = filetype == "csv" and "seed" or nil })
        return
    end
    list_models(project, function(items, err)
        if err then
            log.error(err)
            return
        end
        if #items == 0 then
            log.warn "No models found"
            return
        end
        picker.select({ items = items, prompt = "Walk from", format_item = graph.label }, function(item)
            if not item then return end
            walk_begin(project, item.unique_id)
        end)
    end)
end

function M.goto_model()
    local project = require_project()
    if project then goto_nav.goto_model(project) end
end

function M.refresh_graph()
    local project = require_project()
    if not project then return end
    graph_cache.refresh(project, function(_, err)
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
        picker.select_many(
            { items = items, prompt = "Select dbt models", format_item = graph.label },
            function(selected)
                if #selected == 0 then return end
                vim.ui.select(
                    { "run", "test", "compile", "build" },
                    { prompt = "Select dbt operation" },
                    function(operation)
                        if not operation then return end
                        local selected_ids = selectors.from_resources(selected)
                        execute_with_output(project, operation, table.concat(selected_ids, " "))
                    end
                )
            end
        )
    end)
end

return M
