-- Benchmark YAML scanning and graph navigation on a demo project.
-- Usage: nvim --headless --noplugin -u tests/minimal.vim -l scripts/bench-demo.lua [project]
-- Defaults to demo/. Generate large inputs with scripts/generate-demo-scale.py.
local project = (_G.arg and _G.arg[1]) or "demo"

local function timed(label, fn)
    local start = vim.uv.hrtime()
    local result = fn()
    print(string.format("%-28s %8.1f ms", label, (vim.uv.hrtime() - start) / 1e6))
    return result
end

local properties = require "dbtpal.properties"
local graph = require "dbtpal.graph"

local decls = timed("properties.scan", function() return properties.scan(project) end)
print(string.format("%-28s %8d declarations", "scan result", #decls))

local manifest_path = vim.fs.joinpath(project, "target", "manifest.json")
local manifest = vim.json.decode(table.concat(vim.fn.readfile(manifest_path), "\n"))
local index = timed(
    "graph.build_index",
    function() return graph.build_index(vim.tbl_extend("force", manifest.nodes, manifest.sources or {})) end
)

local first_model = (graph.matches(index, "m_00000")[1] or {}).unique_id or "model.demo_project.orders"
timed("walk_neighbors (10x)", function()
    for _ = 1, 10 do
        graph.neighbors(index, first_model, "up")
        graph.neighbors(index, first_model, "down")
    end
end)
timed("distances", function() return graph.distances(index, first_model) end)
