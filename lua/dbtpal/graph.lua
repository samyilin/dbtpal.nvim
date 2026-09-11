local config = require "dbtpal.config"
local execute = require "dbtpal.execute"

local M = {}

local function cache_path(project_dir)
    local key = project_dir:gsub("[^%w]", "_")
    return vim.fs.joinpath(vim.fn.stdpath "cache", "dbtpal", "graph-" .. key .. ".json")
end

local function manifest_path(project_dir) return vim.fs.joinpath(project_dir, "target", "manifest.json") end

local function file_mtime(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.mtime.sec or 0
end

---Build a name index and dependency edges from raw manifest-style nodes.
---Pure function over data; safe to unit test without dbt.
---@param nodes table map of unique_id -> node table
---@return table index { by_name = {}, nodes = {} }
function M.build_index(nodes)
    local index = { by_name = {}, nodes = {} }
    for unique_id, node in pairs(nodes or {}) do
        local entry = {
            unique_id = unique_id,
            name = node.name,
            resource_type = node.resource_type,
            package_name = node.package_name,
            path = node.original_file_path or node.path,
            deps = (node.depends_on and node.depends_on.nodes) or {},
        }
        index.nodes[unique_id] = entry
        if entry.name then
            index.by_name[entry.name] = index.by_name[entry.name] or {}
            index.by_name[entry.name][#index.by_name[entry.name] + 1] = entry
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
    if direction == "downstream" then
        local dependents = {}
        for id, entry in pairs(index.nodes) do
            for _, dep in ipairs(entry.deps) do
                dependents[dep] = dependents[dep] or {}
                dependents[dep][#dependents[dep] + 1] = id
            end
        end
        local out = {}
        while #queue > 0 do
            local id = table.remove(queue, 1)
            for _, next_id in ipairs(dependents[id] or {}) do
                if not seen[next_id] then
                    seen[next_id] = true
                    queue[#queue + 1] = next_id
                    out[#out + 1] = index.nodes[next_id]
                end
            end
        end
        return out
    end
    local out = {}
    while #queue > 0 do
        local id = table.remove(queue, 1)
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

local function write_cache(project_dir, index, manifest_mtime)
    local path = cache_path(project_dir)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local payload = { built_at = os.time(), manifest_mtime = manifest_mtime or 0, nodes = {} }
    for id, entry in pairs(index.nodes) do
        payload.nodes[id] = {
            name = entry.name,
            resource_type = entry.resource_type,
            package_name = entry.package_name,
            original_file_path = entry.path,
            depends_on = { nodes = entry.deps },
        }
    end
    local fd = vim.uv.fs_open(path, "w", 420)
    if fd then
        vim.uv.fs_write(fd, vim.json.encode(payload))
        vim.uv.fs_close(fd)
    end
end

local function read_cache(project_dir)
    local fd = vim.uv.fs_open(cache_path(project_dir), "r", 420)
    if not fd then return nil end
    local stat = vim.uv.fs_fstat(fd)
    local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
    vim.uv.fs_close(fd)
    if not data then return nil end
    local ok, payload = pcall(vim.json.decode, data)
    if not ok or type(payload) ~= "table" then return nil end
    return payload
end

local function rebuild_from_manifest(project_dir, callback)
    local mpath = manifest_path(project_dir)
    local fd = vim.uv.fs_open(mpath, "r", 420)
    if not fd then
        callback(nil, "no manifest; run a dbt command first")
        return false
    end
    local stat = vim.uv.fs_fstat(fd)
    local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
    vim.uv.fs_close(fd)
    if not data then
        callback(nil, "unable to read manifest")
        return true
    end
    local ok, manifest = pcall(vim.json.decode, data)
    if not ok or type(manifest.nodes) ~= "table" then
        callback(nil, "invalid manifest")
        return true
    end
    local index = M.build_index(manifest.nodes)
    write_cache(project_dir, index, file_mtime(mpath))
    callback(index, nil)
    return true
end

local function rebuild_from_ls(project_dir, callback)
    execute.run("ls", { "--output", "json", "--quiet" }, function(result)
        if result.code ~= 0 then
            callback(nil, result.stderr ~= "" and result.stderr or "dbt ls failed")
            return
        end
        local nodes = {}
        for line in result.stdout:gmatch "[^\r\n]+" do
            local ok, row = pcall(vim.json.decode, line)
            if ok and type(row) == "table" and row.unique_id then
                nodes[row.unique_id] = {
                    name = row.name,
                    resource_type = row.resource_type,
                    package_name = row.package_name,
                    original_file_path = row.original_file_path or row.path,
                    depends_on = row.depends_on or { nodes = {} },
                }
            end
        end
        local index = M.build_index(nodes)
        write_cache(project_dir, index, file_mtime(manifest_path(project_dir)))
        callback(index, nil)
    end)
end

---Load the cached graph, rebuilding when the manifest is newer.
function M.load(project_dir, callback)
    local payload = read_cache(project_dir)
    local mtime = file_mtime(manifest_path(project_dir))
    if payload and (payload.manifest_mtime or 0) >= mtime and mtime > 0 then
        callback(M.build_index(payload.nodes), nil)
        return
    end
    if mtime > 0 then
        rebuild_from_manifest(project_dir, callback)
        return
    end
    if payload then
        callback(M.build_index(payload.nodes), nil)
        return
    end
    rebuild_from_ls(project_dir, callback)
end

function M.refresh(project_dir, callback)
    if file_mtime(manifest_path(project_dir)) > 0 then
        rebuild_from_manifest(project_dir, callback)
    else
        rebuild_from_ls(project_dir, callback)
    end
end

function M.project_dir()
    if config.options.path_to_dbt_project ~= "" then return config.options.path_to_dbt_project end
    return nil
end

return M
