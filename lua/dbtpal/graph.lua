---Pure graph operations over dbt manifest-style nodes. No IO here;
---persistence lives in graph_cache.
local M = {}

---Resource types that participate in navigation and listings.
M.resource_types = { model = true, seed = true, snapshot = true, source = true }

---@class dbtpal.GraphEntry
---@field unique_id string
---@field name string?
---@field resource_type string?
---@field package_name string?
---@field source_name string?
---@field fqn string[]?
---@field root_path string?
---@field path string?
---@field deps string[]

---@class dbtpal.GraphIndex
---@field by_name table<string, dbtpal.GraphEntry[]>
---@field nodes table<string, dbtpal.GraphEntry>
---@field dependents table<string, string[]>
---@field layout dbtpal.ProjectLayout?

---Build a name index and dependency edges from raw manifest-style nodes.
---Pure function over data; safe to unit test without dbt.
---@param nodes table<string, table> map of unique_id -> node table
---@return dbtpal.GraphIndex index { by_name = {}, nodes = {} }
function M.build_index(nodes)
    local index = { by_name = {}, nodes = {}, dependents = {} }
    for unique_id, node in pairs(nodes or {}) do
        local entry = {
            unique_id = unique_id,
            name = node.name,
            resource_type = node.resource_type,
            package_name = node.package_name or unique_id:match "^[^.]+%.([^.]+)%.",
            source_name = node.source_name,
            fqn = node.fqn,
            root_path = node.root_path,
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

---A unique ID resolves exactly; a bare name can have several candidates.
---@param index dbtpal.GraphIndex
---@param reference string
---@return dbtpal.GraphEntry[]
function M.matches(index, reference)
    if index.nodes[reference] then return { index.nodes[reference] } end
    local entries = vim.list_extend({}, index.by_name[reference] or {})
    table.sort(entries, function(a, b) return a.unique_id < b.unique_id end)
    return entries
end

---@param entry dbtpal.GraphEntry
---@return string
function M.label(entry)
    local name = entry.name or entry.unique_id or "?"
    if not entry.unique_id then return name end
    if entry.source_name then name = entry.source_name .. "." .. name end
    if entry.package_name then name = entry.package_name .. "." .. name end
    if entry.resource_type ~= "model" then name = entry.resource_type .. ":" .. name end
    return name
end

---Only direct dependencies/dependents of one resource, sorted by identity.
---@param index dbtpal.GraphIndex
---@param id string
---@param direction string
---@return dbtpal.GraphEntry[]
function M.neighbors(index, id, direction)
    local entry = index.nodes[id]
    if not entry then return {} end
    local ids = direction == "up" and entry.deps or (index.dependents[id] or {})
    local items, seen = {}, {}
    for _, next_id in ipairs(ids) do
        if next_id ~= id and not seen[next_id] and index.nodes[next_id] then
            items[#items + 1] = index.nodes[next_id]
            seen[next_id] = true
        end
    end
    table.sort(items, function(a, b) return a.unique_id < b.unique_id end)
    return items
end

---All models in the index, sorted by name.
---@param index dbtpal.GraphIndex
---@return dbtpal.GraphEntry[]
function M.models(index)
    local items = {}
    for _, entry in pairs(index.nodes) do
        if entry.resource_type == "model" then items[#items + 1] = entry end
    end
    table.sort(items, function(a, b)
        if a.name == b.name then return a.unique_id < b.unique_id end
        return a.name < b.name
    end)
    return items
end

---Shortest-path distances from origin over undirected edges.
---@param index dbtpal.GraphIndex
---@param origin string
---@return table<string, integer> map of unique_id -> distance
function M.distances(index, origin)
    local dist = {}
    local queue = {}
    for _, entry in ipairs(M.matches(index, origin)) do
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
---@param names string[]
---@param max integer
---@return string[] crumbs, boolean truncated
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

---Parse a ref() or source() call on a line. Returns nil when absent.
---@param line string
---@return table|nil { kind = "ref"|"source", name = string }
function M.parse_model_ref(line)
    local package_name, model = line:match "ref%s*%(%s*['\"]([%w_.-]+)['\"]%s*,%s*['\"]([%w_.-]+)['\"]"
    if model then return { kind = "ref", name = model, package_name = package_name } end
    local ref = line:match "ref%s*%(%s*['\"]([%w_]+)['\"]"
    if ref then return { kind = "ref", name = ref } end
    local source, name = line:match "source%s*%(%s*['\"]([%w_]+)['\"]%s*,%s*['\"]([%w_]+)['\"]"
    if name then return { kind = "source", source = source, name = name } end
    return nil
end

return M
