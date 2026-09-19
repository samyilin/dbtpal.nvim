local M = {}

local config = require "dbtpal.config"

---Cells for a dimension: fractions of the total when in (0, 1],
---absolute cell counts otherwise, clamped to the editor.
local function cells(total, value, margin)
    if value > 1 then return math.max(1, math.min(math.ceil(value), total)) end
    return math.max(1, math.ceil(total * value - (margin or 0)))
end

local function open_console(opts)
    local name = "dbtpalConsole"
    local cur = vim.fn.bufnr(name)

    if cur and cur ~= -1 then vim.api.nvim_buf_delete(cur, { force = true }) end

    local columns = vim.o.columns
    local lines = vim.o.lines
    local width = cells(columns, config.options.float_width or 0.8)
    local height = cells(lines, config.options.float_height or 0.8, 4)
    local left = math.ceil((columns - width) * 0.5)
    local top = math.ceil((lines - height) * 0.5 - 1)

    local win_opts = vim.tbl_deep_extend("force", {
        relative = "editor",
        style = "minimal",
        border = config.options.float_border or "double",
        width = width,
        height = height,
        col = left,
        row = top,
    }, opts or {})

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    vim.api.nvim_buf_set_name(buf, name)
    local chan = vim.api.nvim_open_term(buf, { force_crlf = true })

    -- pcall: the user may quit the window mid-stream.
    local push = function(line) pcall(vim.api.nvim_chan_send, chan, line) end
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q<CR>", {})

    return win, buf, push
end

local function popup(data, opts)
    local win, buf, push = open_console(opts)

    for _, line in ipairs(data) do
        push(string.format("%s\r\n", line))
    end

    push "\r\n ---- Press q to quit ----- \r\n"

    return win, buf
end

---Open an empty console for live output. Returns a handle with push(line)
---and finish(), which appends the quit hint once the job is done.
function M.stream(opts)
    local win, buf, push = open_console(opts)
    return {
        win = win,
        buf = buf,
        push = push,
        finish = function() push "\r\n ---- Press q to quit ----- \r\n" end,
    }
end

M.popup = popup
return M
