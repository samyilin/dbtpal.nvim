local M = {}

function M.model(name) return name end
function M.upstream(name) return "+" .. name end
function M.downstream(name) return name .. "+" end
function M.family(name) return "+" .. name .. "+" end
function M.tag(name) return "tag:" .. name end
function M.path(name) return "path:" .. name end

---dbt selectors use qualified names, never artifact unique_id strings.
function M.from_resource(resource)
    local selector
    if resource.resource_type == "source" and resource.source_name then
        selector = "source:" .. resource.source_name .. "." .. resource.name
    elseif resource.fqn and #resource.fqn > 0 then
        selector = "fqn:" .. table.concat(resource.fqn, ".")
    else
        selector = resource.name
    end
    if resource.package_name then selector = selector .. ",package:" .. resource.package_name end
    if resource.resource_type then selector = selector .. ",resource_type:" .. resource.resource_type end
    return selector
end

function M.from_resources(resources)
    local result = {}
    for _, resource in ipairs(resources or {}) do
        result[#result + 1] = M.from_resource(resource)
    end
    return result
end

return M
