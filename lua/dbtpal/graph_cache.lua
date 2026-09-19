local config = require "dbtpal.config"
local execute = require "dbtpal.execute"
local graph = require "dbtpal.graph"
local projects = require "dbtpal.projects"

local M = {}
local cache_version = 3

local function cache_path(project_dir)
    local key = vim.fn.sha256(vim.fs.normalize(vim.fn.fnamemodify(project_dir, ":p")))
    return vim.fs.joinpath(vim.fn.stdpath "cache", "dbtpal", "graph-" .. key .. ".json")
end

local function manifest_path(layout) return vim.fs.joinpath(layout.target, "manifest.json") end

local function file_mtime(path)
    local stat = vim.uv.fs_stat(path)
    return stat and (stat.mtime.sec + stat.mtime.nsec / 1e9) or 0
end

local function read_file(path)
    local fd = vim.uv.fs_open(path, "r", 420)
    if not fd then return nil end
    local stat = vim.uv.fs_fstat(fd)
    local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
    vim.uv.fs_close(fd)
    return data
end

local function write_cache(project_dir, index, manifest_mtime, layout)
    local path = cache_path(project_dir)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local payload = {
        version = cache_version,
        built_at = os.time(),
        manifest_mtime = manifest_mtime or 0,
        manifest_path = manifest_path(layout),
        project_name = layout.name,
        nodes = {},
    }
    for id, entry in pairs(index.nodes) do
        payload.nodes[id] = {
            name = entry.name,
            resource_type = entry.resource_type,
            package_name = entry.package_name,
            source_name = entry.source_name,
            fqn = entry.fqn,
            root_path = entry.root_path,
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
    if not ok or type(payload) ~= "table" or payload.version ~= cache_version or type(payload.nodes) ~= "table" then
        return nil
    end
    return payload
end

local function rebuild_from_manifest(project_dir, layout, callback)
    local mpath = manifest_path(layout)
    local data = read_file(mpath)
    if data == nil then
        local present = file_mtime(mpath) > 0
        callback(nil, present and "unable to read manifest" or "no manifest; run a dbt command first")
        return
    end
    local ok, manifest = pcall(vim.json.decode, data)
    if not ok or type(manifest) ~= "table" or type(manifest.nodes) ~= "table" then
        callback(nil, "invalid manifest")
        return
    end
    local index = graph.build_index(vim.tbl_extend("force", manifest.nodes, manifest.sources or {}))
    layout.name = (manifest.metadata or {}).project_name or layout.name
    index.layout = layout
    write_cache(project_dir, index, file_mtime(mpath), layout)
    callback(index, nil)
end

local function rebuild_from_ls(project_dir, layout, callback)
    execute.run("ls", {
        "--output",
        "json",
        "--quiet",
        "--output-keys",
        "unique_id",
        "name",
        "resource_type",
        "package_name",
        "source_name",
        "fqn",
        "original_file_path",
        "depends_on",
    }, function(result)
        if result.code ~= 0 then
            callback(nil, result.stderr ~= "" and result.stderr or "dbt ls failed")
            return
        end
        -- dbt ls normally writes a manifest with full lineage metadata.
        if file_mtime(manifest_path(layout)) > 0 then
            rebuild_from_manifest(project_dir, layout, callback)
            return
        end
        local nodes = {}
        for line in result.stdout:gmatch "[^\r\n]+" do
            local ok, row = pcall(vim.json.decode, line)
            if not ok or type(row) ~= "table" or not row.unique_id or not row.name then
                callback(nil, "invalid resource JSON from dbt ls")
                return
            end
            nodes[row.unique_id] = row
        end
        local index = graph.build_index(nodes)
        index.layout = layout
        write_cache(project_dir, index, file_mtime(manifest_path(layout)), layout)
        callback(index, nil)
    end)
end

---Read the on-disk graph cache without rebuilding. Returns the index or
---nil when absent, stale-versioned, or corrupt. Never spawns dbt: used
---for cheap read-only checks where a rebuild must not block the UI.
function M.cached(project_dir)
    local layout = projects.layout(project_dir)
    local payload = read_cache(project_dir)
    if not payload then return nil end
    local index = graph.build_index(payload.nodes)
    index.layout = layout
    return index
end

---Load the cached graph, rebuilding when the manifest is newer.
function M.load(project_dir, callback)
    local layout = projects.layout(project_dir)
    local payload = read_cache(project_dir)
    local mtime = file_mtime(manifest_path(layout))
    if payload and payload.manifest_path == manifest_path(layout) and payload.manifest_mtime == mtime then
        local index = graph.build_index(payload.nodes)
        layout.name = layout.name or payload.project_name
        index.layout = layout
        callback(index, nil)
        return
    end
    if mtime > 0 then
        rebuild_from_manifest(project_dir, layout, callback)
    else
        rebuild_from_ls(project_dir, layout, callback)
    end
end

function M.refresh(project_dir, callback)
    local layout = projects.layout(project_dir)
    if file_mtime(manifest_path(layout)) > 0 then
        rebuild_from_manifest(project_dir, layout, callback)
    else
        rebuild_from_ls(project_dir, layout, callback)
    end
end

function M.project_dir()
    if config.options.path_to_dbt_project ~= "" then return config.options.path_to_dbt_project end
    return nil
end

return M
