local config = require "dbtpal.config"
local execute = require "dbtpal.execute"
local graph = require "dbtpal.graph"

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

local function read_file(path)
    local fd = vim.uv.fs_open(path, "r", 420)
    if not fd then return nil end
    local stat = vim.uv.fs_fstat(fd)
    local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
    vim.uv.fs_close(fd)
    return data
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
            source_name = entry.source_name,
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
    local data = read_file(cache_path(project_dir))
    if not data then return nil end
    local ok, payload = pcall(vim.json.decode, data)
    if not ok or type(payload) ~= "table" then return nil end
    return payload
end

local function rebuild_from_manifest(project_dir, callback)
    local mpath = manifest_path(project_dir)
    local data = read_file(mpath)
    if data == nil then
        local present = file_mtime(mpath) > 0
        callback(nil, present and "unable to read manifest" or "no manifest; run a dbt command first")
        return
    end
    local ok, manifest = pcall(vim.json.decode, data)
    if not ok or type(manifest.nodes) ~= "table" then
        callback(nil, "invalid manifest")
        return
    end
    local index = graph.build_index(manifest.nodes)
    write_cache(project_dir, index, file_mtime(mpath))
    callback(index, nil)
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
                    source_name = row.source_name,
                    original_file_path = row.original_file_path or row.path,
                    depends_on = row.depends_on or { nodes = {} },
                }
            end
        end
        local index = graph.build_index(nodes)
        write_cache(project_dir, index, file_mtime(manifest_path(project_dir)))
        callback(index, nil)
    end)
end

---Load the cached graph, rebuilding when the manifest is newer.
function M.load(project_dir, callback)
    local payload = read_cache(project_dir)
    local mtime = file_mtime(manifest_path(project_dir))
    if payload and mtime > 0 and (payload.manifest_mtime or 0) >= mtime then
        callback(graph.build_index(payload.nodes), nil)
        return
    end
    if mtime > 0 then
        rebuild_from_manifest(project_dir, callback)
        return
    end
    if payload then
        callback(graph.build_index(payload.nodes), nil)
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
