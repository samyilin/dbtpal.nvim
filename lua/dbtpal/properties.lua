---Content-based navigation for ordinary block-style dbt properties YAML.
local config = require "dbtpal.config"
local log = require "dbtpal.log"
local projects = require "dbtpal.projects"
local M = {}
local kinds = { models = true, seeds = true, snapshots = true, sources = true }

---@class dbtpal.Declaration
---@field kind string
---@field dataset string?
---@field name string?
---@field header boolean?
---@field lnum integer
---@field end_lnum integer?
---@field file string?
---@field user_config boolean?

---@class dbtpal.DeclSpec
---@field kinds table<string, boolean>?
---@field dataset string?
---@field name string?

local function block_value(value) return value == "" or value:match "^#" end

local function item_name(line)
    local value = line:match "^%s*%-%s+name:%s*(.-)%s*$" or line:match "^%s*name:%s*(.-)%s*$"
    if not value then return nil end
    local name, rest = value:match '^"([%w_.-]+)"%s*(.*)$'
    if not name then
        name, rest = value:match "^'([%w_.-]+)'%s*(.*)$"
    end
    if not name then
        name, rest = value:match "^([%w_.-]+)%s*(.*)$"
    end
    if name and block_value(rest) then return name end
    return nil
end

---Track entity boundaries, not every nested `name:` (columns, tests, etc.).
---Only literal `- name:` entries are indexed; this is not a YAML evaluator.
---@param lines string[]
---@return dbtpal.Declaration[]
function M.parse(lines)
    local decls, active = {}, {}
    local kind, dataset, base_indent, map_indent, tables_indent, table_indent, scalar_indent, pending
    local function close(indent, lnum)
        while #active > 0 and active[#active].indent >= indent do
            local frame = table.remove(active)
            frame.decl.end_lnum = lnum - 1
        end
    end
    local function add(decl, indent, lnum)
        decl.kind, decl.lnum, decl.end_lnum = kind, lnum, #lines
        decls[#decls + 1] = decl
        active[#active + 1] = { decl = decl, indent = indent }
    end
    -- A `- item` line without an inline name waits for a deeper `name:`
    -- key (dbt allows any key order). Nested lists and dedents cancel it,
    -- so a deferred name must precede nested `- ` content; later names
    -- fail safe with no declaration instead of a wrong jump.
    local function complete_pending(name, lnum)
        if not pending then return end
        if pending.role == "table" then
            table_indent = table_indent or pending.indent
            if pending.indent == table_indent then add({ dataset = dataset, name = name }, pending.indent, lnum) end
        elseif pending.role == "entry" then
            if kind == "sources" then
                dataset = name
                add({ dataset = name, header = true }, pending.indent, lnum)
            else
                add({ name = name }, pending.indent, lnum)
            end
        end
        pending = nil
    end
    for i, line in ipairs(lines) do
        local indent = #(line:match "^ *")
        if line:match "%S" and not line:match "^%s*#" and not (scalar_indent and indent > scalar_indent) then
            scalar_indent = nil
            local top, value = line:match "^([%w_]+):%s*(.-)%s*$"
            if top or line:match "^%-%-%-" or line:match "^%.%.%." then
                close(-1, i)
                kind = top and kinds[top] and block_value(value) and top or nil
                dataset, base_indent, tables_indent, table_indent, pending = nil, nil, nil, nil, nil
            elseif kind then
                close(indent, i)
                local prefix = line:match "^(%s*%-%s+)"
                if prefix then
                    pending = nil
                    base_indent = base_indent or indent
                    local name = item_name(line)
                    if indent == base_indent then
                        dataset, tables_indent, table_indent = nil, nil, nil
                        map_indent = #prefix
                        if name then
                            if kind == "sources" then
                                dataset = name
                                add({ dataset = name, header = true }, indent, i)
                            else
                                add({ name = name }, indent, i)
                            end
                        else
                            -- Provisional dataset scope: `tables:` may precede
                            -- the deferred dataset `name:` key.
                            pending = { indent = indent, role = "entry", scope = kind == "sources" }
                        end
                    elseif dataset and tables_indent and indent >= tables_indent then
                        table_indent = table_indent or indent
                        if indent == table_indent then
                            if name then
                                add({ dataset = dataset, name = name }, indent, i)
                            else
                                pending = { indent = indent, role = "table" }
                            end
                        end
                    end
                else
                    if tables_indent and indent <= tables_indent then
                        tables_indent, table_indent = nil, nil
                    end
                    if pending and indent <= pending.indent then pending = nil end
                    local tables = line:match "^%s*tables:%s*(.-)%s*$"
                    if
                        (dataset or (pending and pending.scope))
                        and indent == map_indent
                        and tables
                        and block_value(tables)
                    then
                        tables_indent = indent
                    end
                    if pending and indent > pending.indent then
                        local name = item_name(line)
                        if name then complete_pending(name, i) end
                    end
                end
                -- Ignore YAML-looking examples inside multiline descriptions.
                local field = prefix and line:sub(#prefix + 1) or line:sub(indent + 1)
                if field:match "^[%w_]+:%s*[|>]" then scalar_indent = prefix and #prefix or indent end
            end
        end
    end
    return decls
end

---@param lines string[]
---@param cursor integer
---@return dbtpal.Declaration?
function M.declaration_at(lines, cursor)
    local target
    for _, decl in ipairs(M.parse(lines)) do
        if decl.lnum <= cursor and cursor <= decl.end_lnum then target = decl end
    end
    return target
end

---@param decls dbtpal.Declaration[]
---@param spec dbtpal.DeclSpec
---@return dbtpal.Declaration[]
function M.find(decls, spec)
    return vim.tbl_filter(
        function(decl)
            return not decl.header
                and (not spec.kinds or spec.kinds[decl.kind])
                and (not spec.name or decl.name == spec.name)
                and (not spec.dataset or decl.dataset == spec.dataset)
        end,
        decls
    )
end

---Fresh on-disk scan. Keep absolute paths so relative/trailing-slash project
---settings cannot accidentally be joined to the project directory twice.
---Skips the artifact directory (custom target-path or default target/),
---whose generated YAML would otherwise surface as phantom declarations.
---@param exclude_target string|nil absolute artifact directory to skip
---Shared YAML file walk. Calls back with (file, lines) for each readable
---properties file outside the artifact directory. Returns the normalized
---project root.
local function each_yaml(project, exclude_target, callback)
    project = vim.fs.normalize(vim.fn.fnamemodify(project, ":p"))
    if exclude_target then exclude_target = vim.fs.normalize(vim.fn.fnamemodify(exclude_target, ":p")) end
    for _, pattern in ipairs { "**/*.yml", "**/*.yaml" } do
        for _, file in ipairs(vim.fn.globpath(project, pattern, false, true)) do
            local under_target = file:match "/target/"
            if exclude_target then
                under_target = under_target or file:sub(1, #exclude_target + 1) == exclude_target .. "/"
            end
            if not under_target then
                local ok, lines = pcall(vim.fn.readfile, file)
                if ok then callback(file, lines) end
            end
        end
    end
    return project
end

---@param project string
---@param exclude_target string?
---@return dbtpal.Declaration[]
function M.scan(project, exclude_target)
    local decls = {}
    each_yaml(project, exclude_target, function(file, lines)
        for _, decl in ipairs(M.parse(lines)) do
            if not decl.header then
                decl.file = file
                decls[#decls + 1] = decl
            end
        end
    end)
    return decls
end

---Absolute YAML paths recorded by the manifest (patch_path plus any
---*.yml/*.yaml original_file_path or path), resolved per owning package
---with a project-root fallback. Returns a set. A missing or invalid
---manifest yields an empty set; the filesystem scan stays the fallback.
---@param project string
---@return table<string, boolean> set of absolute paths
function M.manifest_yaml(project)
    local known = {}
    local layout = projects.layout(project)
    local ok, data = pcall(vim.fn.readfile, vim.fs.joinpath(layout.target, "manifest.json"))
    if not ok then return known end
    local ok_decode, manifest = pcall(vim.json.decode, table.concat(data, "\n"))
    if not ok_decode or type(manifest) ~= "table" then return known end
    local function add(node)
        if type(node) ~= "table" then return end
        for _, field in ipairs { "patch_path", "original_file_path", "path" } do
            local value = node[field]
            if type(value) == "string" and value:match "%.ya?ml$" then
                local resolved = projects.manifest_file(layout, node.package_name, value)
                if resolved then known[resolved] = true end
            end
        end
    end
    for _, nodes in ipairs { manifest.nodes, manifest.sources } do
        if type(nodes) == "table" then
            for _, node in pairs(nodes) do
                add(node)
            end
        end
    end
    return known
end

---Strip a trailing # comment, quote-aware (backslash escapes honored).
---Heuristic: unbalanced quotes leave the remainder intact.
local function strip_comment(line)
    local out, quote = {}, nil
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if quote then
            out[#out + 1] = c
            if c == "\\" then
                out[#out + 1] = line:sub(i + 1, i + 1)
                i = i + 1
            elseif c == quote then
                quote = nil
            end
        elseif c == '"' or c == "'" then
            quote = c
            out[#out + 1] = c
        elseif c == "#" then
            break
        else
            out[#out + 1] = c
        end
        i = i + 1
    end
    return table.concat(out)
end

---@class dbtpal.FlowIssue
---@field file string?
---@field lnum integer
---@field text string?
---@field known boolean?

---Heuristic single-line flow-style locations: [...] or {...} regions
---containing a name: key, outside comments and block scalars. Multiline
---flow blocks may be missed and quoted examples misflagged; output feeds
---a user report, never jump targets.
---@param lines string[]?
---@return dbtpal.FlowIssue[]
function M.detect_flow(lines)
    local issues = {}
    local scalar_indent = nil
    for i, line in ipairs(lines or {}) do
        local indent = #(line:match "^ *")
        if line:match "%S" and not line:match "^%s*#" and not (scalar_indent and indent > scalar_indent) then
            scalar_indent = nil
            local code = strip_comment(line)
            local bare = code:gsub([["(.-)"]], '""'):gsub("'(.-)'", "''")
            local region = bare:match "%b[]" or bare:match "%b{}"
            if region and region:find "name:" then
                issues[#issues + 1] = { lnum = i, text = code:match "^%s*(.-)%s*$" }
            end
            local field = code:sub(indent + 1)
            if field:match "^[%w_]+:%s*[|>]" then scalar_indent = indent end
        end
    end
    return issues
end

---Like scan, but also reports heuristic flow-style locations, each tagged
---with manifest_known. Returns decls, issues.
---@param project string
---@param exclude_target string?
---@return dbtpal.Declaration[], dbtpal.FlowIssue[]
function M.scan_with_report(project, exclude_target)
    local known = M.manifest_yaml(project)
    local decls, issues = {}, {}
    each_yaml(project, exclude_target, function(file, lines)
        for _, decl in ipairs(M.parse(lines)) do
            if not decl.header then
                decl.file = file
                decls[#decls + 1] = decl
            end
        end
        for _, issue in ipairs(M.detect_flow(lines)) do
            issue.file = file
            issue.known = known[file] or false
            issues[#issues + 1] = issue
        end
    end)
    return decls, issues
end

local warned_unmatched = {}

---Find the first line mentioning a model outside comments, else line 1.
local function locate_name(file, model)
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok then
        for i, line in ipairs(lines) do
            if strip_comment(line):find(model, 1, true) then return i end
        end
    end
    return 1
end

---Apply yaml_flow_files: "" silences a file's issues; a model name also
---synthesizes a declaration so jumps resolve. Keys are absolute, or
---relative to the project directory first, then to Neovim's working
---directory. Warns once per session for entries matching no file.
---Returns filtered decls, issues.
---@param project string
---@param decls dbtpal.Declaration[]
---@param issues dbtpal.FlowIssue[]
---@return dbtpal.Declaration[], dbtpal.FlowIssue[]
function M.apply_flow_config(project, decls, issues)
    local mapping = config.options.yaml_flow_files or {}
    if next(mapping) == nil then return decls, issues end
    local root = vim.fs.normalize(vim.fn.fnamemodify(project, ":p"))
    local silenced, synthesized = {}, {}
    for key, model in pairs(mapping) do
        local file = nil
        if key:match "^/" or key:match "^%a:[/\\]" then
            file = vim.fs.normalize(key)
        else
            -- Accept keys relative to the project directory or to Neovim's
            -- working directory; first readable hit wins.
            for _, base in ipairs { root, vim.fn.getcwd() } do
                local candidate = vim.fs.normalize(vim.fs.joinpath(base, key))
                if vim.fn.filereadable(candidate) == 1 then
                    file = candidate
                    break
                end
            end
            file = file or vim.fs.normalize(vim.fs.joinpath(root, key))
        end
        if vim.fn.filereadable(file) ~= 1 then
            if not warned_unmatched[file] then
                warned_unmatched[file] = true
                log.warn("dbtpal: yaml_flow_files entry has no such file: " .. key)
            end
        elseif model == "" then
            silenced[file] = true
        elseif type(model) == "string" and model ~= "" then
            silenced[file] = true
            synthesized[#synthesized + 1] =
                { kind = "models", name = model, file = file, lnum = locate_name(file, model), user_config = true }
        end
    end
    if next(silenced) == nil then return decls, issues end
    local kept_decls = vim.tbl_filter(function(decl) return not silenced[decl.file] end, decls)
    for _, synth in ipairs(synthesized) do
        kept_decls[#kept_decls + 1] = synth
    end
    local kept_issues = vim.tbl_filter(function(issue) return not silenced[issue.file] end, issues)
    return kept_decls, kept_issues
end

local function report_path(project)
    local dir = vim.fs.joinpath(vim.fn.stdpath "cache", "dbtpal")
    vim.fn.mkdir(dir, "p")
    return vim.fs.joinpath(
        dir,
        "yaml-" .. vim.fn.sha256(vim.fs.normalize(vim.fn.fnamemodify(project, ":p"))) .. ".json"
    )
end

---Change-aware flow-issue report: quickfix when use_quickfix is set,
---otherwise a cache file plus a notification. Silent when unchanged;
---clears a matching quickfix list once issues resolve.
---@param project string
---@param issues dbtpal.FlowIssue[]?
function M.report(project, issues)
    issues = issues or {}
    local hash = vim.fn.sha256(vim.json.encode(issues))
    local path = report_path(project)
    local cached_hash = nil
    local ok, data = pcall(vim.fn.readfile, path)
    if ok and data then
        local ok_decode, cached = pcall(vim.json.decode, table.concat(data, "\n"))
        if ok_decode and type(cached) == "table" then cached_hash = cached.hash end
    end
    if cached_hash == hash then return end
    vim.fn.writefile({ vim.json.encode { hash = hash, issues = issues } }, path)
    if config.options.use_quickfix then
        if #issues > 0 then
            local items = {}
            for _, issue in ipairs(issues) do
                items[#items + 1] = {
                    filename = issue.file,
                    lnum = issue.lnum,
                    text = "dbtpal: possibly flow-style YAML (not parsed): " .. (issue.text or ""),
                    type = "W",
                }
            end
            vim.fn.setqflist({}, " ", { title = "dbt yaml", items = items })
            log.info(#items .. " YAML location(s) need attention; use :copen to view")
        elseif vim.fn.getqflist({ title = 1 }).title == "dbt yaml" then
            vim.fn.setqflist({}, "r", { title = "dbt yaml", items = {} })
        end
    elseif #issues > 0 then
        log.info("dbtpal: " .. #issues .. " YAML location(s) need attention; details in " .. path)
    end
end

return M
