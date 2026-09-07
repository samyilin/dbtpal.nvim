local M = {}

function M.setup(picker)
    local ok, mini = pcall(require, "mini.pick")
    if not ok then return false end
    picker.register("mini.pick", {
        select = function(opts, callback)
            mini.start {
                source = {
                    name = opts.prompt or "Select",
                    items = opts.items or {},
                    show = function(index)
                        local item = (opts.items or {})[index]
                        if opts.format_item then return opts.format_item(item) end
                        return item.name or tostring(item)
                    end,
                    choose = function(index) callback((opts.items or {})[index]) end,
                },
            }
        end,
    })
    return true
end

return M
