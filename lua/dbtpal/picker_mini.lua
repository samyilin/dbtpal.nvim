local M = {}

function M.setup(picker)
    local ok, mini = pcall(require, "mini.pick")
    if not ok then return false end
    picker.register("mini.pick", {
        action_key = "<C-o>",
        select = function(opts, callback)
            local start_opts = {
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
            if opts.on_action then
                start_opts.mappings = {
                    item_action = {
                        char = "<C-o>",
                        func = function()
                            local matches = mini.get_picker_matches()
                            local current = matches and matches.current
                            if not current then return end
                            mini.stop()
                            vim.schedule(function() opts.on_action(current) end)
                        end,
                    },
                }
            end
            mini.start(start_opts)
        end,
    })
    return true
end

return M
