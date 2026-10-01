local log = require "dbtpal.log"
local config = require "dbtpal.config"

local M = {}

local version_cache = {}

local function supports_log_level()
    local argv = vim.list_extend({ config.options.path_to_dbt }, config.options.pre_cmd_args or {})
    argv[#argv + 1] = "--version"
    local key = vim.json.encode { argv, config.options.env }
    if version_cache.key == key then return version_cache.supported end
    local ok, result = pcall(
        function() return vim.system(argv, { text = true, env = config.options.env }):wait(5000) end
    )
    local major, minor
    if ok and result.code == 0 then
        major, minor = ((result.stdout or "") .. (result.stderr or "")):match "(%d+)%.(%d+)"
    end
    local supported = major ~= nil and (tonumber(major) > 1 or (tonumber(major) == 1 and tonumber(minor) >= 5))
    version_cache = { key = key, supported = supported }
    return supported
end

local function has_flag(args, flag)
    for _, arg in ipairs(args) do
        if arg == flag or arg:sub(1, #flag + 1) == flag .. "=" then return true end
    end
    return false
end

local warned_missing_dirs = {}

---@param project string? Explicit project dir; falls back to global config.
M.build_path_args = function(cmd, args, project)
    log.debug("dbtpal config: " .. vim.inspect(config.options))
    local dbt_path = config.options.path_to_dbt
    local dbt_project = project or config.options.path_to_dbt_project
    local dbt_profile = config.options.path_to_dbt_profiles_dir
    local include_project_dir = config.options.include_project_dir
    local include_log_level = config.options.include_log_level

    local cmd_args = {}

    -- Copy configured arguments before adding generated options. Mutating the
    -- config here duplicates --profiles-dir/--project-dir on every command.
    local pre_cmd_args = vim.deepcopy(config.options.pre_cmd_args or {})
    local post_cmd_args = vim.deepcopy(config.options.post_cmd_args or {})
    if type(args) == "string" then args = vim.split(args, " ") end
    args = args or {}
    local function supplied(flag)
        return has_flag(pre_cmd_args, flag) or has_flag(args, flag) or has_flag(post_cmd_args, flag)
    end

    if dbt_profile and dbt_profile ~= "" and not supplied "--profiles-dir" then
        if vim.fn.isdirectory(dbt_profile) == 1 then
            table.insert(post_cmd_args, "--profiles-dir")
            table.insert(post_cmd_args, dbt_profile)
        elseif not warned_missing_dirs[dbt_profile] then
            -- dbt aborts on a missing --profiles-dir; fail open so its own
            -- resolution (project profiles.yml, DBT_PROFILES_DIR) applies.
            warned_missing_dirs[dbt_profile] = true
            log.warn("dbtpal: profiles dir does not exist, skipping --profiles-dir: " .. dbt_profile)
        end
    end

    if include_project_dir and dbt_project and dbt_project ~= "" and not supplied "--project-dir" then
        table.insert(post_cmd_args, "--project-dir")
        table.insert(post_cmd_args, dbt_project)
    end

    if include_log_level and not supplied "--log-level" and supports_log_level() then
        table.insert(post_cmd_args, "--log-level=INFO")
    end

    vim.list_extend(cmd_args, pre_cmd_args)
    vim.list_extend(cmd_args, { cmd })

    vim.list_extend(cmd_args, args)

    vim.list_extend(cmd_args, post_cmd_args)

    log.debug("Building dbt command: " .. dbt_path .. " " .. table.concat(cmd_args, " "))

    return dbt_path, cmd_args
end

return M
