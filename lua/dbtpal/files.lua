-- Filetype helpers inspired by jgillies/vim-dbt.
local projects = require "dbtpal.projects"
local config = require "dbtpal.config"
local M = {}

function M.setup()
    local group = vim.api.nvim_create_augroup("dbtPal", { clear = true })
    vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
        group = group,
        pattern = "*.sql",
        callback = function()
            vim.bo.filetype = "sql"
            if config.options.custom_dbt_syntax_enabled then
                vim.b.current_syntax = nil
                vim.cmd "runtime syntax/dbt.vim"
            end
        end,
        desc = "Set SQL filetype and optionally layer dbt syntax",
    })

    if config.options.extended_path_search then
        vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
            group = group,
            pattern = { "*.sql", "*.yml", "*.yaml", "*.md" },
            callback = function(ev)
                vim.api.nvim_buf_call(ev.buf, function()
                    vim.opt_local.suffixesadd:append ".sql"
                    local project = projects.resolve(vim.api.nvim_buf_get_name(ev.buf))
                    if not project then return end
                    local current = vim.opt_local.path:get()
                    for _, suffix in ipairs { "/macros/**", "/models/**" } do
                        local entry = project .. suffix
                        if not vim.tbl_contains(current, entry) then vim.opt_local.path:append(entry) end
                    end
                end)
            end,
            desc = "Look for gf targets within dbt project folders",
        })
    end

    if config.options.protect_compiled_files then
        vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
            group = group,
            pattern = { "*/target/run/*.sql", "*/target/compiled/*.sql" },
            command = "setlocal filetype=dbtCompiledSQL syntax=dbt",
            desc = "Identify compiled dbt SQL buffers",
        })
    end
end

return M
