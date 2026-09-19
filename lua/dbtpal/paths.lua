local M = {}

---Expand local paths and Oil directory names; reject other virtual URIs.
function M.normalize(path)
    if type(path) ~= "string" then return nil end
    local expanded = vim.fn.expand(path)
    if expanded:match "^oil://" then expanded = expanded:gsub("^oil:/+", "/") end
    if expanded:match "://" then return nil end
    return expanded
end

function M.absolute(path, base)
    if not path:match "^/" and not path:match "^%a:[/\\]" then path = vim.fs.joinpath(base or vim.fn.getcwd(), path) end
    return vim.fs.normalize(path)
end

function M.contains(directory, path) return path == directory or path:sub(1, #directory + 1) == directory .. "/" end

return M
