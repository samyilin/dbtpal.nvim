local M = {}

function M.model(name) return name end
function M.upstream(name) return "+" .. name end
function M.downstream(name) return name .. "+" end
function M.family(name) return "+" .. name .. "+" end
function M.tag(name) return "tag:" .. name end
function M.path(name) return "path:" .. name end

function M.from_resources(resources)
    local result = {}
    for _, resource in ipairs(resources or {}) do
        result[#result + 1] = resource.unique_id or resource.name
    end
    return result
end

return M
