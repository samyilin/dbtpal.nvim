---Bidirectional jumps between SQL resources and YAML declarations.
local graph = require "dbtpal.graph"
local graph_cache = require "dbtpal.graph_cache"
local properties = require "dbtpal.properties"
local projects = require "dbtpal.projects"
local picker = require "dbtpal.picker"
local log = require "dbtpal.log"
local context = require "dbtpal.context"

local M = {}

---Order file choices with .sql first: jumps prefer SQL sources over
---YAML/CSV definitions sharing a name. Stable fallback is unique_id.
local function sql_first(a, b)
    local a_sql = a.path ~= nil and a.path:match "%.sql$" ~= nil
    local b_sql = b.path ~= nil and b.path:match "%.sql$" ~= nil
    if a_sql ~= b_sql then return a_sql end
    return (a.unique_id or "") < (b.unique_id or "")
end

local function open_declaration(decl)
    vim.cmd.edit(decl.file)
    vim.api.nvim_win_set_cursor(0, { decl.lnum, 0 })
end

local function relative_label(project, decl)
    local file = decl.file
    if project and file:sub(1, #project + 1) == project .. "/" then file = file:sub(#project + 2) end
    local label = file .. ":" .. decl.lnum
    if decl.dataset then label = label .. " (" .. decl.dataset .. "." .. (decl.name or "?") .. ")" end
    if decl.user_config then label = label .. " (user config)" end
    return label
end

local function pick_declaration(project, matches, prompt)
    local items = {}
    for _, decl in ipairs(matches) do
        items[#items + 1] = { decl = decl, name = relative_label(project, decl) }
    end
    picker.select({
        items = items,
        prompt = prompt,
        format_item = function(item) return item.name end,
    }, function(item)
        if item then open_declaration(item.decl) end
    end)
end

local function resolve_and_open(project, name, source, kind, package_name)
    graph_cache.load(project, function(index, err)
        if err then
            log.error(err)
            return
        end
        local matches = vim.tbl_filter(function(entry)
            if source then return entry.resource_type == "source" and entry.source_name == source end
            return entry.resource_type ~= "source"
                and graph.resource_types[entry.resource_type]
                and (not kind or entry.resource_type == kind)
                and (not package_name or entry.package_name == package_name)
        end, index.by_name[name] or {})
        if #matches == 0 then
            log.warn("Unknown model: " .. name)
            return
        end
        local function open(entry)
            if entry then projects.open_resource(project, entry, index.layout) end
        end
        if #matches == 1 then
            open(matches[1])
        else
            table.sort(matches, sql_first)
            picker.select({
                items = matches,
                prompt = "Definition of " .. name,
                format_item = function(entry) return entry.unique_id end,
            }, open)
        end
    end)
end

---Declarations plus change-aware flow-style reporting. Manifest-known
---files are trusted for jumps via patch_path; the scan still covers
---undocumented files, and the report stays silent unless issues change.
---Warn once per manifest state for flow-config models missing from the
---cached graph. Reads only the on-disk cache: verification must never
---spawn dbt from a jump path. Without a cache it defers silently.
local verified = {}

local function verify_flow_models(project, decls)
    local layout = projects.layout(project)
    local stat = vim.uv.fs_stat(vim.fs.joinpath(layout.target, "manifest.json"))
    local mtime = stat and (stat.mtime.sec + stat.mtime.nsec / 1e9) or 0
    local state = verified[project]
    if not state or state.mtime ~= mtime then
        state = { mtime = mtime, warned = {} }
        verified[project] = state
    end
    local user_decls = vim.tbl_filter(function(decl) return decl.user_config end, decls)
    if #user_decls == 0 then return end
    local index = graph_cache.cached(project)
    if not index then return end
    for _, decl in ipairs(user_decls) do
        if not state.warned[decl.name] then
            state.warned[decl.name] = true
            if #(index.by_name[decl.name] or {}) == 0 then
                log.warn("dbtpal: yaml_flow_files model '" .. decl.name .. "' is not in the graph")
            end
        end
    end
end

local function open_matches(project, matches, prompt, empty_msg)
    if #matches == 1 then
        open_declaration(matches[1])
    elseif #matches > 1 then
        pick_declaration(project, matches, prompt)
    else
        log.warn(empty_msg)
    end
end

local function scan_declarations(project)
    local layout = projects.layout(project)
    local decls, issues = properties.scan_with_report(project, layout.target)
    decls, issues = properties.apply_flow_config(project, decls, issues)
    verify_flow_models(project, decls)
    properties.report(project, issues)
    return decls
end

---Jump from source('dataset', 'table') to its YAML declaration.
---Falls back to the graph when no declaration is found.
local function goto_source_declaration(project, dataset, name)
    local matches =
        properties.find(scan_declarations(project), { kinds = { sources = true }, dataset = dataset, name = name })
    if #matches == 1 then
        open_declaration(matches[1])
    elseif #matches > 1 then
        pick_declaration(project, matches, "Declaration of " .. dataset .. "." .. name)
    else
        resolve_and_open(project, name, dataset)
    end
end

---Jump from a model buffer to its YAML declaration. Content search covers
---both generic schema.yml files and per-dataset table.yml layouts.
local function goto_model_declaration(project)
    local model = context.current_model()
    if not model then
        log.warn "No ref() or source() call on the current line and no current model"
        return
    end
    open_matches(
        project,
        properties.find(
            scan_declarations(project),
            { kinds = { models = true, seeds = true, snapshots = true }, name = model }
        ),
        "Declaration of " .. model,
        "No YAML declaration found for " .. model
    )
end

---List resources selecting from a source, jumping to the chosen one.
local function show_source_dependents(project, dataset, name)
    graph_cache.load(project, function(index, err)
        if err then
            log.error(err)
            return
        end
        local ids = {}
        for _, entry in ipairs(index.by_name[name] or {}) do
            if entry.resource_type == "source" and (not dataset or entry.source_name == dataset) then
                for _, dep in ipairs(index.dependents[entry.unique_id] or {}) do
                    ids[#ids + 1] = dep
                end
            end
        end
        local items, seen = {}, {}
        for _, id in ipairs(ids) do
            local entry = index.nodes[id]
            if entry and entry.path and not seen[id] then
                items[#items + 1] = entry
                seen[id] = true
            end
        end
        table.sort(items, sql_first)
        if #items == 0 then
            log.info("Nothing known selects from " .. (dataset and (dataset .. ".") or "") .. name)
            return
        end
        picker.select({ items = items, prompt = "Used by", format_item = graph.label }, function(item)
            if item then projects.open_resource(project, item, index.layout) end
        end)
    end)
end

---Jump from inside a YAML properties buffer: model/seed/snapshot entries
---resolve to their files; source tables list their dependents; a dataset
---header lists its tables first.
local function goto_from_yaml(project)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local target = properties.declaration_at(lines, cursor)
    if not target then
        log.warn "No dbt declaration at the cursor"
        return
    end
    if target.kind == "sources" and target.name then
        show_source_dependents(project, target.dataset, target.name)
        return
    end
    if target.kind == "sources" then
        local tables = {}
        for _, decl in ipairs(properties.parse(lines)) do
            if not decl.header and decl.kind == "sources" and decl.dataset == target.dataset and decl.name then
                tables[#tables + 1] = decl
            end
        end
        if #tables == 0 then
            log.warn("No tables declared for source " .. target.dataset)
        elseif #tables == 1 then
            show_source_dependents(project, target.dataset, tables[1].name)
        else
            picker.select({ items = tables, prompt = target.dataset .. " tables" }, function(item)
                if item then show_source_dependents(project, target.dataset, item.name) end
            end)
        end
        return
    end
    if not target.name then
        log.warn "No dbt declaration at the cursor"
        return
    end
    resolve_and_open(project, target.name, nil, target.kind:sub(1, -2))
end

---Open the YAML declaration parallel to a walk center: source tables
---resolve to their table entry, other resources to their declaration.
function M.goto_declaration(project, entry)
    if not entry or not entry.name then
        log.warn "No resource under the cursor"
        return
    end
    local matches
    if entry.resource_type == "source" then
        matches = properties.find(
            scan_declarations(project),
            { kinds = { sources = true }, dataset = entry.source_name, name = entry.name }
        )
    else
        matches = properties.find(
            scan_declarations(project),
            { kinds = { models = true, seeds = true, snapshots = true }, name = entry.name }
        )
    end
    open_matches(project, matches, "Declaration of " .. entry.name, "No YAML declaration found for " .. entry.name)
end

function M.goto_model(project)
    local filetype = vim.bo.filetype
    if filetype == "yaml" or filetype == "yml" then
        goto_from_yaml(project)
        return
    end
    local ref = graph.parse_model_ref(vim.api.nvim_get_current_line())
    if ref and ref.kind == "ref" then
        resolve_and_open(project, ref.name, nil, nil, ref.package_name)
    elseif ref and ref.kind == "source" then
        goto_source_declaration(project, ref.source, ref.name)
    else
        goto_model_declaration(project)
    end
end

return M
