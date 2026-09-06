local M = {}

function M.setup(picker)
    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then return false end
    local finders = require "telescope.finders"
    local conf = require("telescope.config").values

    picker.register("telescope", {
        select = function(opts, callback)
            pickers
                .new(opts, {
                    prompt_title = opts.prompt or "Select",
                    finder = finders.new_table {
                        results = opts.items or {},
                        entry_maker = function(item)
                            return {
                                value = item,
                                display = opts.format_item and opts.format_item(item) or item.name or tostring(item),
                                ordinal = item.name or tostring(item),
                            }
                        end,
                    },
                    sorter = conf.generic_sorter(opts),
                    attach_mappings = function(prompt_bufnr, map)
                        local actions = require "telescope.actions"
                        local state = require "telescope.actions.state"
                        map("i", "<CR>", function()
                            local selection = state.get_selected_entry()
                            actions.close(prompt_bufnr)
                            callback(selection and selection.value or nil)
                        end)
                        return true
                    end,
                })
                :find()
        end,
    })
    return true
end

return M
