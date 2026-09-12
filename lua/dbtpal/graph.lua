---Pure graph operations over dbt manifest-style nodes. No IO here;
---persistence lives in graph_cache.
local M = {}

---Build a name index and dependency edges from raw manifest-style nodes.
---Pure function over data; safe to unit test without dbt.
---@param nodes table map of unique_id -> node table
---@return table index { by_name = {}, nodes = {} }
function M.build_index(nodes)
    local index = { by_name = {}, nodes = {}, dependents = {} }
    for unique_id, node in pairs(nodes or {}) do
        local entry = {
            unique_id = unique_id,
            name = node.name,
            resource_type = node.resource_type,
            package_name = node.package_name,
            source_name = node.source_name,
            path = node.original_file_path or node.path,
            deps = (node.depends_on and node.depends_on.nodes) or {},
        }
        index.nodes[unique_id] = entry
        if entry.name then
            index.by_name[entry.name] = index.by_name[entry.name] or {}
            index.by_name[entry.name][#index.by_name[entry.name] + 1] = entry
        end
    end
    for id, entry in pairs(index.nodes) do
        for _, dep in ipairs(entry.deps) do
            index.dependents[dep] = index.dependents[dep] or {}
            index.dependents[dep][#index.dependents[dep] + 1] = id
        end
    end
    return index
end

local function walk(index, names, direction)
    local seen = {}
    local queue = {}
    for _, name in ipairs(names) do
        for _, entry in ipairs(index.by_name[name] or {}) do
            if not seen[entry.unique_id] then
                seen[entry.unique_id] = true
                queue[#queue + 1] = entry.unique_id
            end
        end
    end
    local out = {}
    local head = 1
    if direction == "downstream" then
        while head <= #queue do
            local id = queue[head]
            head = head + 1
            for _, next_id in ipairs(index.dependents[id] or {}) do
                if not seen[next_id] then
                    seen[next_id] = true
                    queue[#queue + 1] = next_id
                    out[#out + 1] = index.nodes[next_id]
                end
            end
        end
        return out
    end
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        local entry = index.nodes[id]
        if entry then
            for _, dep_id in ipairs(entry.deps) do
                if not seen[dep_id] and index.nodes[dep_id] then
                    seen[dep_id] = true
                    queue[#queue + 1] = dep_id
                    out[#out + 1] = index.nodes[dep_id]
                end
            end
        end
    end
    return out
end

function M.upstream(index, name) return walk(index, { name }, "upstream") end

function M.downstream(index, name) return walk(index, { name }, "downstream") end

---All models in the index, sorted by name.
function M.models(index)
    local items = {}
    for _, entry in pairs(index.nodes) do
        if entry.resource_type == "model" then items[#items + 1] = entry end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

---Resolve a name to index entries, preferring a matching source dataset.
---@return table|nil entry, integer alternatives
function M.resolve(index, name, source)
    local entries = index.by_name[name] or {}
    if #entries == 0 then return nil, 0 end
    if source then
        for _, entry in ipairs(entries) do
            if entry.source_name == source then return entry, #entries - 1 end
        end
    end
    return entries[1], #entries - 1
end

---Shortest-path distances from origin over undirected edges.
---@return table map of unique_id -> distance
function M.distances(index, origin)
    local dist = {}
    local queue = {}
    for _, entry in ipairs(index.by_name[origin] or {}) do
        if dist[entry.unique_id] == nil then
            dist[entry.unique_id] = 0
            queue[#queue + 1] = entry.unique_id
        end
    end
    local head = 1
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        local entry = index.nodes[id]
        local next_ids = {}
        if entry then vim.list_extend(next_ids, entry.deps) end
        vim.list_extend(next_ids, index.dependents[id] or {})
        for _, next_id in ipairs(next_ids) do
            if index.nodes[next_id] and dist[next_id] == nil then
                dist[next_id] = dist[id] + 1
                queue[#queue + 1] = next_id
            end
        end
    end
    return dist
end

---Collapse cycles and cap length for breadcrumb display. Display-only;
---the real back-stack is untouched.
---@return table crumbs, boolean truncated
function M.compress_trail(names, max)
    local out = {}
    for _, name in ipairs(names) do
        local pos = nil
        for i, existing in ipairs(out) do
            if existing == name then
                pos = i
                break
            end
        end
        if pos then
            while #out > pos do
                table.remove(out)
            end
        else
            out[#out + 1] = name
        end
    end
    local truncated = false
    while #out > max do
        table.remove(out, 1)
        truncated = true
    end
    return out, truncated
end

function M.family(index, name)
    local seen = {}
    local out = {}
    for _, entry in ipairs(M.upstream(index, name)) do
        if not seen[entry.unique_id] then
            seen[entry.unique_id] = true
            out[#out + 1] = entry
        end
    end
    for _, entry in ipairs(M.downstream(index, name)) do
        if not seen[entry.unique_id] then
            seen[entry.unique_id] = true
            out[#out + 1] = entry
        end
    end
    return out
end

---Parse a ref() or source() call on a line. Returns nil when absent.
---@return table|nil { kind = "ref"|"source", name = string }
function M.parse_model_ref(line)
    local ref = line:match "ref%s*%(%s*['\"]([%w_]+)['\"]"
    if ref then return { kind = "ref", name = ref } end
    local source, name = line:match "source%s*%(%s*['\"]([%w_]+)['\"]%s*,%s*['\"]([%w_]+)['\"]"
    if name then return { kind = "source", source = source, name = name } end
    return nil
end

return M
