local log = require "dbtpal.log"
local config = require "dbtpal.config"
local graph = require "dbtpal.graph"
local paths = require "dbtpal.paths"

local M = {}

---@class dbtpal.ProjectLayout
---@field root string
---@field name string?
---@field target string
---@field packages string
---@field logs string
---@field package_roots table<string, string>?

M.normalize_path = paths.normalize

---Read literal top-level project settings without evaluating Jinja or YAML
---aliases. Explicit lookup overrides cover templated directory settings.
local function project_settings(project)
    local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(project, "dbt_project.yml"))
    local values = {}
    for _, line in ipairs(ok and lines or {}) do
        local key, value = line:match "^([%w_-]+):%s*(.-)%s*$"
        if key and not value:find("{{", 1, true) then
            local quoted = value:match '^"(.-)"%s*#?.*$' or value:match "^'(.-)'%s*#?.*$"
            value = quoted or value:gsub("%s+#.*$", "")
            if value ~= "" and not value:match "^[&*[{|>]" then values[key] = value end
        end
    end
    return values
end

---@param project string
---@return dbtpal.ProjectLayout
function M.layout(project)
    local root = paths.absolute(project)
    local settings = project_settings(root)
    ---@type string?
    local target = config.options.path_to_dbt_target
    if not target or target == "" then
        local args =
            vim.list_extend(vim.deepcopy(config.options.pre_cmd_args or {}), config.options.post_cmd_args or {})
        for i, arg in ipairs(args) do
            if arg == "--target-path" then target = args[i + 1] end
            target = arg:match "^%-%-target%-path=(.+)$" or target
        end
        target = target ~= "" and target or nil
        target = target
            or (config.options.env or {}).DBT_TARGET_PATH
            or vim.env.DBT_TARGET_PATH
            or settings["target-path"]
    end
    local packages = config.options.path_to_dbt_packages
    if not packages or packages == "" then packages = settings["packages-install-path"] end
    return {
        root = root,
        name = settings.name,
        target = paths.absolute(paths.normalize(target or "target") or "target", root),
        packages = paths.absolute(paths.normalize(packages or "dbt_packages") or "dbt_packages", root),
        logs = paths.absolute(paths.normalize(settings["log-path"] or "logs") or "logs", root),
    }
end

---@param layout dbtpal.ProjectLayout
---@param name string?
---@return string?
local function package_root(layout, name)
    if not name or name == layout.name then return layout.root end
    if not layout.package_roots then
        layout.package_roots = {}
        for _, file in ipairs(vim.fn.globpath(layout.packages, "*/dbt_project.yml", false, true)) do
            local root = vim.fn.fnamemodify(file, ":h")
            local settings = project_settings(root)
            if settings.name then layout.package_roots[settings.name] = root end
        end
    end
    return layout.package_roots[name]
end

---Resolve a manifest-recorded relative path. Unlike resource_path, an
---unknown package falls back to the project root: manifest path formats
---vary (package-relative, project-relative, or absolute) and this helper
---only locates files, never opens them. Returns nil when unreadable.
---@param layout dbtpal.ProjectLayout
---@param package_name string?
---@param relpath string?
---@return string?
function M.manifest_file(layout, package_name, relpath)
    if type(relpath) ~= "string" or relpath == "" then return nil end
    if relpath:match "^/" or relpath:match "^%a:[/\\]" then
        return vim.fn.filereadable(relpath) == 1 and paths.absolute(relpath) or nil
    end
    local roots = {}
    local package = package_root(layout, package_name)
    if package then roots[#roots + 1] = package end
    roots[#roots + 1] = layout.root
    for _, root in ipairs(roots) do
        local path = paths.absolute(relpath, root)
        if vim.fn.filereadable(path) == 1 then return path end
    end
    return nil
end

---Resolve a manifest path relative to its owning installed package. Do not
---fall back to a same-named file in the root project for missing packages.
---@param project string
---@param entry {path: string?, package_name: string?, root_path: string?}
---@param layout dbtpal.ProjectLayout?
---@return string?
function M.resource_path(project, entry, layout)
    if not entry.path then return nil end
    if entry.path:match "^/" or entry.path:match "^%a:[/\\]" then
        return vim.fn.filereadable(entry.path) == 1 and paths.absolute(entry.path) or nil
    end
    layout = layout or M.layout(project)
    local root = package_root(layout, entry.package_name) or entry.root_path
    if not root then return nil end
    local path = paths.absolute(entry.path, root)
    return vim.fn.filereadable(path) == 1 and path or nil
end

---Resolve a graph entry to a local file and open it (or add it with the
---"badd" command). Warns and returns false when no local file exists.
---@param project string
---@param entry dbtpal.GraphEntry
---@param layout dbtpal.ProjectLayout?
---@param command string?
---@return boolean
function M.open_resource(project, entry, layout, command)
    local path = M.resource_path(project, entry, layout)
    if not path then
        log.warn("No local file for " .. graph.label(entry))
        return false
    end
    if command == "badd" then
        vim.cmd.badd(path)
    else
        vim.cmd.edit(path)
    end
    return true
end

---@param fpath string?
---@return string?
local function find_project_dir(fpath)
    if fpath == nil then fpath = vim.fn.expand "%:p:h" end
    fpath = M.normalize_path(fpath)
    if fpath == nil then
        log.debug "Cannot detect dbt project dir from a virtual buffer"
        return nil
    end
    log.debug("Searching for dbt project dir in " .. fpath)
    local path = vim.fn.expand(vim.fn.fnamemodify(fpath, ":p"))
    local dbt_project = vim.fn.findfile("dbt_project.yml", path .. ";")
    if dbt_project == "" then
        log.debug("No dbt project found in " .. path)
        return nil
    end
    local found_path = vim.fn.fnamemodify(dbt_project, ":p:h")
    log.debug("dbt project found in " .. found_path)
    return found_path
end

---Filesystem lookup without changing configuration: path or nil.
M.find_project_dir = find_project_dir

---@param bpath string?
---@return boolean
M.detect_dbt_project_dir = function(bpath)
    log.debug "path_to_dbt is not set, attempting to autofind."
    -- Never clobber a manually configured project: opening a buffer in
    -- another project must not repoint every subsequent dbt command.
    if config.options.path_to_dbt_project ~= "" then return true end
    local found = find_project_dir(bpath)
    if found ~= nil then
        config.options.path_to_dbt_project = found
        return true
    end
    return false
end

return M
