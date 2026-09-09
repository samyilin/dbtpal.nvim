if vim.fn.has "nvim-0.12" ~= 1 then
    vim.notify("dbtpal requires Neovim 0.12 or later.", vim.log.levels.ERROR)
    return
end

if vim.g.loaded_dbtpal == 1 then return end
vim.g.loaded_dbtpal = 1
