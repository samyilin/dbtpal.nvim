local M = {}

local config = require "dbtpal.config"

---Cells for a dimension: fractions of the total when in (0, 1],
---absolute cell counts otherwise, clamped to the editor.
local function cells(total, value, margin)
    if value > 1 then return math.max(1, math.min(math.ceil(value), total)) end
    return math.max(1, math.ceil(total * value - (margin or 0)))
end

---Drop ANSI escape sequences so the scratch buffer shows plain text. dbt
---forces color even when piped, so this is required. A trailing incomplete
---sequence is withheld; the next chunk re-renders the whole line.
local function strip_ansi(text)
    text = text:gsub("\27%[[0-?]*[ -/]*[@-~]", "") -- CSI: SGR, cursor, erase
    text = text:gsub("\27%][^\7\27]*\7", "") -- OSC terminated by BEL
    text = text:gsub("\27%][^\7\27]*\27\\", "") -- OSC terminated by ST
    local esc = text:find("\27", 1, true)
    if esc then text = text:sub(1, esc - 1) end
    return text
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

    -- Last buffer line, 1-based. Output arrives in chunks that can split lines
    -- and even split an ANSI sequence, so keep the raw current line and
    -- re-render it as chunks complete.
    local last = 1
    local raw = ""
    local function write(text) vim.api.nvim_buf_set_lines(buf, last - 1, last, false, { text }) end

    -- A carriage return rewrites the visible line from column 0 (dbt progress).
    local function render(line)
        local current = ""
        local first = true
        for _, segment in ipairs(vim.split(strip_ansi(line), "\r", { plain = true })) do
            if first then
                current = segment
                first = false
            else
                current = segment .. current:sub(#segment + 1)
            end
        end
        return current
    end

    local push = function(text)
        if not text or text == "" or not vim.api.nvim_buf_is_valid(buf) then return end
        -- pcall: the user may quit the window mid-stream.
        pcall(function()
            text = text:gsub("\r\n", "\n")
            local parts = vim.split(text, "\n", { plain = true })
            for i, part in ipairs(parts) do
                raw = raw .. part
                write(render(raw))
                if i < #parts then
                    last = last + 1
                    raw = ""
                    write ""
                end
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
