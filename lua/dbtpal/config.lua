local log = require "dbtpal.log"
local paths = require "dbtpal.paths"
local M = {}

---@class dbtpal.Config
---All fields optional: setup() merges partial input over defaults, and
---M.options starts empty before the first setup() call.
---@field path_to_dbt string?
---@field path_to_dbt_project string?
---@field path_to_dbt_profiles_dir string?
---@field path_to_dbt_target string?
---@field path_to_dbt_packages string?
---@field include_project_dir boolean?
---@field include_log_level boolean?
---@field custom_dbt_syntax_enabled boolean?
---@field extended_path_search boolean?
---@field protect_compiled_files boolean?
---@field picker_backend string?
---@field output string?
---@field exclude_packages string[]?
---@field use_quickfix boolean?
---@field yaml_flow_files table<string, string>?
---@field float_border string?
---@field float_width number?
---@field float_height number?
---@field pre_cmd_args string[]?
---@field post_cmd_args string[]?
---@field env table<string, string>?

---@type dbtpal.Config
M.defaults = {
    path_to_dbt = "dbt",
    path_to_dbt_project = "",
    path_to_dbt_profiles_dir = vim.fn.expand "~/.dbt",
    -- Local artifact/package lookup overrides; empty reads dbt_project.yml.
    path_to_dbt_target = "",
    path_to_dbt_packages = "",

    include_project_dir = true,
    include_log_level = true,

    custom_dbt_syntax_enabled = true,
    extended_path_search = true,
    protect_compiled_files = true,
    picker_backend = "default",
    -- Output presentation: "notify" stays quiet on success, "float" opens
    -- output on exit, "stream" opens at job start with live output.
    output = "float",

    -- Package names (dbt ls `package_name`) hidden from model pickers
    -- and graph walk listings, e.g. { "dbt_utils", "snowplow" }.
    exclude_packages = {},

    -- Push failed-test locations to the quickfix list after test runs.
    use_quickfix = false,

    -- YAML files the block scanner cannot interpret (e.g. flow style).
    -- Keys are project-relative or absolute paths. A "" value silences
    -- the file in the unparsed-YAML report; a model name synthesizes a
    -- declaration for jumps, e.g. { ["models/legacy.yml"] = "orders" }.
    yaml_flow_files = {},

    -- Floating output style. Width/height are fractions of the editor
    -- when in (0, 1], or absolute cells when greater than 1.
    float_border = "double",
    float_width = 0.8,
    float_height = 0.8,

    pre_cmd_args = {},
    post_cmd_args = {},

    env = {},
}

---@type dbtpal.Config
M.options = {}

local float_borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true }

local valid_outputs = { notify = true, float = true, stream = true }

---Validate float style on load: unknown values warn and fall back.
local function validate_float(border, width, height)
    if not float_borders[border] then
        log.warn "dbtpal: unknown float_border, using default"
        border = M.defaults.float_border
    end
    local function valid_dim(value, fallback)
        if type(value) ~= "number" or value <= 0 then
            log.warn "dbtpal: float dimensions must be positive numbers, using default"
            return fallback
        end
        return value
    end
    return border, valid_dim(width, M.defaults.float_width), valid_dim(height, M.defaults.float_height)
end

---@param options? dbtpal.Config
function M.setup(options)
    M.options = vim.tbl_deep_extend("force", M.defaults, options or {})
    M.options.float_border, M.options.float_width, M.options.float_height =
        validate_float(M.options.float_border, M.options.float_width, M.options.float_height)
    for _, key in ipairs { "output_mode", "stream_output", "include_profiles_dir", "use_current_model" } do
        if options and options[key] ~= nil then
            log.warn("dbtpal: config option " .. key .. " was removed; see README for the replacement")
        end
    end
    if type(M.options.output) ~= "string" or not valid_outputs[M.options.output] then
        log.warn "dbtpal: unknown output, using default"
        M.options.output = M.defaults.output
    end
    local project = paths.normalize(M.options.path_to_dbt_project)
    if not project then log.warn "Ignoring non-filesystem path_to_dbt_project, using auto-detection" end
    M.options.path_to_dbt_project = project or ""
    if M.options.path_to_dbt_project ~= "" then
        M.options.path_to_dbt_project = paths.absolute(M.options.path_to_dbt_project)
        local marker = vim.fs.joinpath(M.options.path_to_dbt_project, "dbt_project.yml")
        if vim.fn.filereadable(marker) ~= 1 then
            log.warn "path_to_dbt_project has no dbt_project.yml; using auto-detection"
            M.options.path_to_dbt_project = ""
        end
    end
    M.options.path_to_dbt_profiles_dir = paths.normalize(M.options.path_to_dbt_profiles_dir)
        or M.defaults.path_to_dbt_profiles_dir
    require("dbtpal.files").setup()
end

return M
