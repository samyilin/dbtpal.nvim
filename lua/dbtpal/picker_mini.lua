local M = {}

function M.setup(picker)
    local ok, mini = pcall(require, "mini.pick")
    if not ok then return false end
    picker.register("mini.pick", {
        select = function(opts, callback)
            mini.start {
                source = {
                    name = opts.prompt or "Select",
                    items = vim.tbl_map(function(item)
                        local value = vim.deepcopy(item)
                        value.text = opts.format_item and opts.format_item(item) or item.name or tostring(item)
                        return value
                    end, opts.items or {}),
                    choose = function(item) callback(item) end,
                },
            }
        end,
    })
    return true
end

return M
