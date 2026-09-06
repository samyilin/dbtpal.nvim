local execute = require "dbtpal.execute"

local M = {}

function M.normalize(row)
    if type(row) ~= "table" then return nil end
    return {
        unique_id = row.unique_id,
        name = row.name,
        resource_type = row.resource_type,
        original_file_path = row.original_file_path or row.path,
        path = row.original_file_path or row.path,
        package_name = row.package_name,
    }
end

function M.list(opts, callback)
    opts = opts or {}
    local args = { "--output", "json", "--quiet" }
    if opts.resource_type then args = vim.list_extend(args, { "--resource-type", opts.resource_type }) end
    if opts.selector then args = vim.list_extend(args, { "--select", opts.selector }) end
    execute.run("ls", args, function(result)
        if result.code ~= 0 then
            callback(nil, result)
            return
        end
        local resources = {}
        for line in result.stdout:gmatch "[^\r\n]+" do
            local ok, row = pcall(vim.json.decode, line)
            if not ok or type(row) ~= "table" then
                callback(nil, { code = 1, stderr = "invalid JSON from dbt ls" })
                return
            end
            local resource = M.normalize(row)
            if not resource then
                callback(nil, { code = 1, stderr = "invalid resource from dbt ls" })
                return
            end
            resources[#resources + 1] = resource
        end
        callback(resources, nil)
    end)
end

return M
