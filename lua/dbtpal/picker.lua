---@class dbtpal.PickerOpts
---@field items table[]?
---@field prompt string?
---@field format_item (fun(item: table): string?)?
---@field backend string?
---@field on_action (fun(item: table))?

---@class dbtpal.PickerBackend
---@field select fun(opts: dbtpal.PickerOpts, callback: fun(item: table?))
---@field select_many (fun(opts: dbtpal.PickerOpts, callback: fun(selected: table[])))?
---@field action_key string?

local M = { backends = {} }
local config = require "dbtpal.config"

local function builtin_select(opts, callback)
    vim.ui.select(opts.items or {}, {
        prompt = opts.prompt or "Select dbt resource",
        format_item = opts.format_item or function(item) return item.name or tostring(item) end,
    }, callback)
end

local function builtin_select_many(opts, callback)
    local items = vim.deepcopy(opts.items or {})
    local selected = {}
    local chosen = {}

    local function choose_next()
        local choices = { { __done = true, name = "Done" } }
        for _, item in ipairs(items) do
            local already = false
            for _, value in ipairs(selected) do
                if value.unique_id == item.unique_id then already = true end
            end
            if not already then choices[#choices + 1] = item end
        end
        vim.ui.select(choices, {
            prompt = opts.prompt or "Select dbt resources (choose Done when finished)",
            format_item = function(item)
                if item.__done then return item.name end
                local mark = chosen[item.unique_id] and "[x] " or "[ ] "
                return mark .. (opts.format_item and opts.format_item(item) or item.name or tostring(item))
            end,
        }, function(item)
            if not item or item.__done then
                callback(selected)
                return
            end
            selected[#selected + 1] = item
            chosen[item.unique_id] = true
            choose_next()
        end)
    end
    choose_next()
end

---@param name string
---@param backend dbtpal.PickerBackend
function M.register(name, backend) M.backends[name] = backend end

---@param name string?
---@return dbtpal.PickerBackend
function M.get(name)
    name = name or config.options.picker_backend
    if name and M.backends[name] then return M.backends[name] end
    if M.backends.default then return M.backends.default end
    return { select = builtin_select, select_many = builtin_select_many }
end

---@param opts dbtpal.PickerOpts?
---@param callback fun(item: table?)
function M.select(opts, callback) return M.get(opts and opts.backend).select(opts or {}, callback) end

---@param opts dbtpal.PickerOpts?
---@param callback fun(selected: table[])
function M.select_many(opts, callback)
    local backend = M.get(opts and opts.backend)
    return (backend.select_many or builtin_select_many)(opts or {}, callback)
end

M.register("builtin", { select = builtin_select, select_many = builtin_select_many })
M.register("default", M.backends.builtin)

return M
