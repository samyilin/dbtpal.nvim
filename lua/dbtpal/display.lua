local M = {}

local config = require "dbtpal.config"

---Cells for a dimension: fractions of the total when in (0, 1],
---absolute cell counts otherwise, clamped to the editor.
local function cells(total, value, margin)
    if value > 1 then return math.max(1, math.min(math.ceil(value), total)) end
    return math.max(1, math.ceil(total * value - (margin or 0)))
end

---Open the floating console. follow=true keeps the cursor on the last line so
---live streams tail their output; popups stay at the top, like before.
local function open_console(win_overrides, follow)
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
    }, win_overrides or {})

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].undolevels = -1
    -- Wrapping is display-only: every dbt line stays a single buffer line, so
    -- yanking compiled SQL copies the whole line. A terminal buffer hard-wraps
    -- rows at the window width, which truncated long lines on copy.
    vim.wo[win].wrap = true

    -- Last buffer line, 1-based. Output arrives in chunks that can split lines.
    local last = 1
    local function read() return vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or "" end
    local function write(text) vim.api.nvim_buf_set_lines(buf, last - 1, last, false, { text }) end
    -- A carriage return rewrites the current line from column 0 (dbt progress).
    local function apply(text)
        local current = read()
        local first = true
        for _, segment in ipairs(vim.split(text, "\r", { plain = true })) do
            if first then
                current = current .. segment
                first = false
            else
                current = segment .. current:sub(#segment + 1)
            end
        end
        write(current)
    end

    local push = function(text)
        if not text or text == "" or not vim.api.nvim_buf_is_valid(buf) then return end
        -- pcall: the user may quit the window mid-stream.
        pcall(function()
            text = text:gsub("\r\n", "\n")
            for i, part in ipairs(vim.split(text, "\n", { plain = true })) do
                if i > 1 then
                    last = last + 1
                    write ""
                end
                if part ~= "" then apply(part) end
            end
            -- Output is scratch content, not an edit: keep :q working.
            vim.bo[buf].modified = false
            if follow then vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 }) end
        end)
    end

    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q<CR>", {})

    return win, buf, push
end

local function popup(data, opts)
    local win, buf, push = open_console(opts, false)

    for _, line in ipairs(data) do
        push(line .. "\n")
    end

    push "\n ---- Press q to quit ----- \n"

    return win, buf
end

---Open an empty console for live output. Returns a handle with push(line)
---and finish(), which appends the quit hint once the job is done.
function M.stream(opts)
    local win, buf, push = open_console(opts, true)
    return {
        win = win,
        buf = buf,
        push = push,
        finish = function() push "\n ---- Press q to quit ----- \n" end,
    }
end

M.popup = popup
return M
