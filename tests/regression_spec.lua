---@diagnostic disable: need-check-nil
local config = require "dbtpal.config"
local execute = require "dbtpal.execute"
local main = require "dbtpal.main"
local graph = require "dbtpal.graph"
local properties = require "dbtpal.properties"
local project_root = vim.fn.getcwd()
local fixture = project_root .. "/tests/fixtures/dbt.sh"

-- Always restore stubs, including when an assertion fails.
local function with_stubs(stubs, callback)
    local originals = {}
    for i, stub in ipairs(stubs) do
        originals[i] = stub[1][stub[2]]
        stub[1][stub[2]] = stub[3]
    end
    local ok, err = xpcall(callback, debug.traceback)
    for i, stub in ipairs(stubs) do
        stub[1][stub[2]] = originals[i]
    end
    if not ok then error(err) end
end

before_each(
    function()
        config.setup {
            path_to_dbt = "/bin/sh",
            pre_cmd_args = { fixture },
            path_to_dbt_project = project_root .. "/tests/dbt_project",
            path_to_dbt_profiles_dir = "",
            include_project_dir = false,
            include_log_level = false,
        }
    end
)

it("preserves default paths and the caller's table in partial setup", function()
    local opts = { output = "stream" }
    config.setup(opts)
    check_equal("", config.options.path_to_dbt_project)
    check_equal(vim.fn.expand "~/.dbt", config.options.path_to_dbt_profiles_dir)
    check_same({ output = "stream" }, opts)
    local root = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(root .. "/proj/models", "p")
    vim.fn.writefile({ "name: proj" }, root .. "/proj/dbt_project.yml")
    local ok, err = xpcall(function()
        config.setup { path_to_dbt_project = "oil://" .. root .. "/proj", extended_path_search = false }
        check_equal(root .. "/proj", config.options.path_to_dbt_project)
        local count = #vim.api.nvim_get_autocmds { group = "dbtPal" }
        config.setup { path_to_dbt_project = "oil://" .. root .. "/proj", extended_path_search = false }
        check_equal(count, #vim.api.nvim_get_autocmds { group = "dbtPal" })
        config.setup { path_to_dbt_project = root .. "/no-such-dir", extended_path_search = false }
        check_equal("", config.options.path_to_dbt_project)
    end, debug.traceback)
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end)

it("validates float styling on setup", function()
    config.setup { float_border = "rounded", float_width = 40, float_height = 0.5 }
    check_equal("rounded", config.options.float_border)
    check_equal(40, config.options.float_width)
    check_equal(0.5, config.options.float_height)
    -- Intentionally invalid input: exercises the runtime validation fallback.
    ---@diagnostic disable-next-line: assign-type-mismatch
    config.setup { float_border = "bevel", float_width = -1, float_height = "tall" }
    check_equal("double", config.options.float_border)
    check_equal(0.8, config.options.float_width)
    check_equal(0.8, config.options.float_height)
end)

it("validates output and warns on removed options", function()
    local warnings = {}
    with_stubs({
        { require "dbtpal.log", "warn", function(msg) warnings[#warnings + 1] = msg end },
    }, function()
        -- Intentionally invalid input: exercises the runtime validation fallback.
        ---@diagnostic disable-next-line: assign-type-mismatch
        config.setup { output = "loud", output_mode = "float", stream_output = true }
        check_equal("float", config.options.output)
    end)
    check_equal(3, #warnings)
end)

it("opens floating output with configured dimensions", function()
    config.setup { float_width = 40, float_height = 0.5 }
    local display = require "dbtpal.display"
    local win, buf = display.popup { "hello" }
    check_equal("dbtpalConsole", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"))
    local cfg = vim.api.nvim_win_get_config(win)
    check_equal(40, cfg.width)
    check_equal(math.ceil(vim.o.lines * 0.5 - 4), cfg.height)
    vim.api.nvim_win_close(win, true)
end)

it("uses the configured version command and compares 1.10 correctly", function()
    local commands = require "dbtpal.commands"
    local calls, argv = 0, nil
    config.options.path_to_dbt = "docker"
    config.options.pre_cmd_args = { "exec", "dbt-container", "dbt" }
    config.options.include_log_level = true
    with_stubs({
        {
            vim,
            "system",
            function(args)
                calls, argv = calls + 1, args
                return { wait = function() return { code = 0, stdout = "Core:\n  - installed: 1.10.2\n" } end }
            end,
        },
    }, function()
        for _ = 1, 2 do
            local _, args = commands.build_path_args("run", {})
            check_true(vim.tbl_contains(args, "--log-level=INFO"))
        end
        check_equal(1, calls)
        check_same({ "docker", "exec", "dbt-container", "dbt", "--version" }, argv)
        config.options.pre_cmd_args[2] = "other-container"
        commands.build_path_args("run", {})
        check_equal(2, calls)
    end)
end)

it("skips --profiles-dir when the directory is missing", function()
    config.options.path_to_dbt_profiles_dir = "/dbtpal-no-such-profiles-dir"
    local warnings = {}
    with_stubs({
        { require "dbtpal.log", "warn", function(msg) warnings[#warnings + 1] = msg end },
    }, function()
        for _ = 1, 2 do
            local _, args = require("dbtpal.commands").build_path_args("run", {})
            check_true(not vim.tbl_contains(args, "--profiles-dir"))
        end
    end)
    check_equal(1, #warnings)
    config.options.path_to_dbt_profiles_dir = project_root .. "/tests/dbt_project"
    local _, args = require("dbtpal.commands").build_path_args("run", {})
    check_true(vim.tbl_contains(args, "--profiles-dir"))
end)

it("keeps explicit CLI flags and selectors without appending defaults", function()
    config.options.include_project_dir = true
    local _, args = require("dbtpal.commands").build_path_args("run", {
        "--project-dir=/override",
        "--profiles-dir",
        "/profiles",
    })
    check_same({ fixture, "run", "--project-dir=/override", "--profiles-dir", "/profiles" }, args)
    local captured
    with_stubs(
        { { main, "run_command", function(cmd, command_args, mode) captured = { cmd, command_args, mode } end } },
        function()
            vim.bo.filetype = "text"
            for _, selector in ipairs { "--select=orders", "--selector=daily", "-sorders" } do
                vim.cmd("Dbt run " .. selector)
                check_same({ "run", { selector } }, captured)
            end
        end
    )
end)

it("streams before exit and retains independent stdout and stderr", function()
    local result, job
    local chunks = { stdout = {}, stderr = {} }
    local system = vim.system
    local fast_event = false
    -- Give the fixture a handshake pipe so it cannot exit before its first
    -- chunk has been delivered to the consumer. Production jobs need no stdin.
    with_stubs({
        {
            vim,
            "system",
            function(argv, opts, callback)
                opts.stdin = true
                return system(argv, opts, callback)
            end,
        },
    }, function()
        job = execute.run("stream", {}, function(value) result = value end, {
            on_chunk = function(data, stream)
                fast_event = fast_event or vim.in_fast_event()
                chunks[stream][#chunks[stream] + 1] = data
                if stream == "stdout" and data:find("first", 1, true) then
                    job:write "continue\n"
                    job:write(nil)
                end
            end,
        })
    end)
    if not vim.wait(3000, function() return result ~= nil end) then
        job:kill(9)
        error "streaming did not deliver output before exit"
    end
    check_equal(0, result.code)
    check_equal(false, fast_event)
    check_equal("first\nsecond: continue\n", result.stdout)
    check_equal("stderr tail", result.stderr)
    check_equal(result.stdout, table.concat(chunks.stdout))
    check_equal(result.stderr, table.concat(chunks.stderr))
end)

it("retains failure details in notify mode and quickfix in streaming mode", function()
    local display = require "dbtpal.display"
    local popup, finished
    local chunks = {}
    config.options.use_quickfix = true
    with_stubs({
        { display, "popup", function(lines) popup = table.concat(lines, "\n") end },
        {
            display,
            "stream",
            function()
                return {
                    push = function(data) chunks[#chunks + 1] = data end,
                    finish = function() finished = true end,
                }
            end,
        },
    }, function()
        main.run_command("test", {}, "notify")
        check_true(vim.wait(3000, function() return popup ~= nil end))
        check_true(popup:find("stdout progress", 1, true))
        check_true(popup:find("stderr details", 1, true))
        popup = nil
        config.options.output = "stream"
        main.run_command("test", {}, "stream")
        check_true(vim.wait(3000, function() return finished end))
        check_true(popup == nil, "streaming should not open a second float")
        local output = table.concat(chunks)
        check_true(output:find("stdout progress", 1, true))
        check_true(output:find("stderr details", 1, true))
        local qf = vim.fn.getqflist()
        check_equal(1, #qf)
        check_equal(1, qf[1].lnum)
        check_equal(
            config.options.path_to_dbt_project .. "/models/properties.yml",
            vim.api.nvim_buf_get_name(qf[1].bufnr)
        )
        require("dbtpal.quickfix").publish(
            "test",
            { code = 0, stdout = "", stderr = "" },
            config.options.path_to_dbt_project
        )
        check_equal(0, #vim.fn.getqflist())
    end)
end)

it("reports missing executables through the normal completion callback", function()
    config.options.path_to_dbt = "/dbtpal-missing-executable"
    local result
    execute.run("debug", {}, function(value) result = value end)
    check_true(vim.wait(3000, function() return result ~= nil end))
    check_equal(127, result.code)
    check_true(result.stderr ~= "")
end)

it("resolves package paths and custom target directories", function()
    local projects = require "dbtpal.projects"
    local root = vim.fn.resolve(vim.fn.tempname())
    local project = root .. "/project"
    vim.fn.mkdir(project .. "/models", "p")
    vim.fn.mkdir(project .. "/artifacts", "p")
    vim.fn.mkdir(project .. "/third_party/dep/models", "p")
    vim.fn.writefile(
        { "name: project", "target-path: artifacts", "packages-install-path: third_party" },
        project .. "/dbt_project.yml"
    )
    vim.fn.writefile({ "name: dep" }, project .. "/third_party/dep/dbt_project.yml")
    vim.fn.writefile({ "select 1" }, project .. "/models/orders.sql")
    vim.fn.writefile({ "select 1" }, project .. "/third_party/dep/models/helper.sql")
    local ok, err = xpcall(function()
        local layout = projects.layout(project)
        check_equal(project .. "/artifacts", layout.target)
        check_equal(project .. "/third_party", layout.packages)
        check_equal(
            project .. "/third_party/dep/models/helper.sql",
            projects.resource_path(project, { path = "models/helper.sql", package_name = "dep" }, layout)
        )
        check_equal(
            project .. "/models/orders.sql",
            projects.resource_path(project, { path = "models/orders.sql", package_name = "project" }, layout)
        )
        check_true(
            projects.resource_path(project, { path = "models/gone.sql", package_name = "missing" }, layout) == nil,
            "missing packages must not fall back to root files"
        )
    end, debug.traceback)
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end)

it("routes picker operations through the same live output path", function()
    local display = require "dbtpal.display"
    local picker = require "dbtpal.picker"
    local model = { name = "orders", resource_type = "model", unique_id = "model.project.orders" }
    local finished, chunks = false, {}
    config.options.output = "stream"
    with_stubs({
        {
            require "dbtpal.graph_cache",
            "load",
            function(_, callback) callback(graph.build_index { [model.unique_id] = model }) end,
        },
        { picker, "select_many", function(opts, callback) callback(opts.items) end },
        {
            vim.ui,
            "select",
            function(items, _, callback) callback(items[1] == "run" and "test" or "Open full output") end,
        },
        {
            display,
            "stream",
            function()
                return {
                    push = function(data) chunks[#chunks + 1] = data end,
                    finish = function() finished = true end,
                }
            end,
        },
    }, function()
        require("dbtpal.workflows").select_models()
        check_true(vim.wait(3000, function() return finished end))
        check_true(table.concat(chunks):find("stdout progress", 1, true))
        check_true(table.concat(chunks):find("stderr details", 1, true))
    end)
end)

it("ignores source columns, scalar contents, and unrelated YAML sections", function()
    local lines = {
        "sources: # shared properties",
        "  - name: raw",
        "    tables:",
        "      - name: orders",
        "        columns:",
        "          - name: id",
        "        description: |",
        "          - name: example_not_a_table",
        "unit_tests:",
        "  - name: test_orders",
        "models: [{name: flow_style}]",
    }
    local tables = properties.find(properties.parse(lines), { kinds = { sources = true } })
    check_equal(1, #tables)
    check_equal("orders", tables[1].name)
    check_equal("orders", properties.declaration_at(lines, 6).name)
    check_true(properties.declaration_at(lines, 10) == nil)
    check_true(properties.declaration_at(lines, 11) == nil)
end)

it("filters walk listings without removing dependency edges", function()
    local index = graph.build_index {
        ["model.external.helper"] = { name = "helper", resource_type = "model", package_name = "external" },
        ["model.project.orders"] = {
            name = "orders",
            resource_type = "model",
            package_name = "project",
            depends_on = { nodes = { "model.external.helper" } },
        },
    }
    config.options.exclude_packages = { "external" }
    check_equal(0, #require("dbtpal.workflows").walk_neighbors(index, "orders"))
    local upstream = graph.neighbors(index, "model.project.orders", "up")
    check_equal(1, #upstream)
    check_equal("model.external.helper", upstream[1].unique_id)
end)

local function with_project(callback)
    local root = vim.fn.tempname()
    local project = root .. "/project"
    local cwd = vim.fn.getcwd()
    local original_buf = vim.api.nvim_get_current_buf()
    vim.fn.mkdir(project .. "/models", "p")
    vim.fn.mkdir(project .. "/dataset", "p")
    vim.fn.mkdir(project .. "/target", "p")
    root = vim.fn.resolve(root)
    project = root .. "/project"
    local function write(path, lines) vim.fn.writefile(lines, project .. "/" .. path) end
    write("dbt_project.yml", { "name: project", "version: '1.0'" })
    write("models/orders.sql", { "select 1", "select * from {{ source('raw', 'orders') }}" })
    write("models/schema.yml", { "models:", "  - name: orders", "    columns:", "      - name: id" })
    write("dataset/orders.yml", {
        "sources:",
        "  - name: raw",
        "    tables:",
        "      - name: orders",
        "        columns:",
        "          - name: id",
    })
    write("dataset/shop.yml", { "sources:", "  - name: shop", "    tables:", "      - name: orders" })
    write("target/ignored.yml", { "models:", "  - name: orders" })
    write("target/manifest.json", {
        vim.json.encode {
            nodes = {
                ["model.project.orders"] = {
                    name = "orders",
                    resource_type = "model",
                    original_file_path = "models/orders.sql",
                    depends_on = { nodes = { "source.project.raw.orders" } },
                },
                ["test.project.not_null"] = {
                    name = "not_null",
                    resource_type = "test",
                    original_file_path = "models/schema.yml",
                    depends_on = { nodes = { "source.project.raw.orders" } },
                },
            },
            sources = {
                ["source.project.raw.orders"] = {
                    name = "orders",
                    resource_type = "source",
                    source_name = "raw",
                    original_file_path = "dataset/orders.yml",
                },
                ["source.project.shop.orders"] = {
                    name = "orders",
                    resource_type = "source",
                    source_name = "shop",
                    original_file_path = "dataset/shop.yml",
                },
            },
        },
    })
    local ok, err = xpcall(function()
        vim.api.nvim_set_current_dir(root)
        config.setup { path_to_dbt_project = "./project/", include_log_level = false }
        callback(project)
    end, debug.traceback)
    vim.api.nvim_set_current_buf(original_buf)
    vim.api.nvim_set_current_dir(cwd)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf):sub(1, #root) == root then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    local key = vim.fn.sha256(vim.fs.normalize(vim.fn.fnamemodify(project, ":p")))
    vim.fn.delete(vim.fs.joinpath(vim.fn.stdpath "cache", "dbtpal", "graph-" .. key .. ".json"))
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
end

it("loads sources from manifests and keeps dataset fallback exact", function()
    with_project(function(project)
        local cache = require "dbtpal.graph_cache"
        for _ = 1, 2 do
            local index, err
            cache.load(project, function(value, failure)
                index, err = value, failure
            end)
            check_true(err == nil)
            check_true(index.nodes["source.project.raw.orders"] ~= nil)
            local raw = vim.tbl_filter(
                function(entry) return entry.resource_type == "source" and entry.source_name == "raw" end,
                graph.matches(index, "orders")
            )
            check_equal(1, #raw)
            check_equal("source.project.raw.orders", raw[1].unique_id)
            check_equal(2, #index.dependents["source.project.raw.orders"])
            check_equal(
                0,
                #vim.tbl_filter(
                    function(entry) return entry.source_name == "missing" end,
                    graph.matches(index, "orders")
                ),
                "never fall back to another dataset"
            )
        end
    end)
end)

it("jumps both ways in shared and per-table YAML layouts with relative project paths", function()
    with_project(function(project)
        local workflows = require "dbtpal.workflows"
        vim.cmd.edit(project .. "/models/orders.sql")
        vim.bo.filetype = "sql"
        workflows.goto_model()
        check_equal(project .. "/models/schema.yml", vim.api.nvim_buf_get_name(0))
        check_equal(2, vim.api.nvim_win_get_cursor(0)[1])
        vim.bo.filetype = "yaml"
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        workflows.goto_model()
        check_equal(project .. "/models/orders.sql", vim.api.nvim_buf_get_name(0))
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        workflows.goto_model()
        check_equal(project .. "/dataset/orders.yml", vim.api.nvim_buf_get_name(0))
        check_equal(4, vim.api.nvim_win_get_cursor(0)[1])
        vim.bo.filetype = "yaml"
        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        with_stubs({
            {
                require "dbtpal.picker",
                "select",
                function(opts, callback)
                    check_equal(2, #opts.items)
                    check_equal("model.project.orders", opts.items[1].unique_id)
                    check_equal("test.project.not_null", opts.items[2].unique_id)
                    callback(opts.items[1])
                end,
            },
        }, function() workflows.goto_model() end)
        check_equal(project .. "/models/orders.sql", vim.api.nvim_buf_get_name(0))
    end)
end)

it("falls back to the graph with an exact dataset qualifier", function()
    with_project(function(project)
        local workflows = require "dbtpal.workflows"
        vim.cmd.edit(project .. "/models/orders.sql")
        vim.bo.filetype = "sql"
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        with_stubs({
            {
                require "dbtpal.properties",
                "scan",
                function() return {} end,
            },
        }, function() workflows.goto_model() end)
        check_equal(project .. "/dataset/orders.yml", vim.api.nvim_buf_get_name(0))
    end)
end)

it("lists SQL files before YAML definitions", function()
    local index = graph.build_index {
        ["test.proj.aardvark"] = {
            name = "orders",
            resource_type = "test",
            original_file_path = "models/schema.yml",
            depends_on = { nodes = { "source.proj.raw.orders" } },
        },
        ["model.proj.zebra"] = {
            name = "orders",
            resource_type = "model",
            original_file_path = "models/zebra.sql",
            depends_on = { nodes = { "source.proj.raw.orders" } },
        },
        ["source.proj.raw.orders"] = {
            name = "orders",
            resource_type = "source",
            source_name = "raw",
            depends_on = { nodes = {} },
        },
    }
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(
        buf,
        0,
        -1,
        false,
        { "sources:", "  - name: raw", "    tables:", "      - name: orders" }
    )
    vim.bo[buf].filetype = "yaml"
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    with_stubs({
        { require "dbtpal.graph_cache", "load", function(_, callback) callback(index) end },
        {
            require "dbtpal.picker",
            "select",
            function(opts, callback)
                check_equal(2, #opts.items)
                check_equal("model.proj.zebra", opts.items[1].unique_id)
                callback(opts.items[1])
            end,
        },
    }, function() require("dbtpal.workflows").goto_model() end)
    vim.api.nvim_buf_delete(buf, { force = true })
end)

it("prefers SQL snapshots over CSV seeds for ref jumps", function()
    local index = graph.build_index {
        ["seed.proj.thing"] = {
            name = "thing",
            resource_type = "seed",
            original_file_path = "seeds/thing.csv",
            depends_on = { nodes = {} },
        },
        ["snapshot.proj.thing"] = {
            name = "thing",
            resource_type = "snapshot",
            original_file_path = "snapshots/thing.sql",
            depends_on = { nodes = {} },
        },
    }
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "select * from {{ ref('thing') }}" })
    vim.bo[buf].filetype = "sql"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    with_stubs({
        { require "dbtpal.graph_cache", "load", function(_, callback) callback(index) end },
        {
            require "dbtpal.picker",
            "select",
            function(opts, callback)
                check_equal(2, #opts.items)
                check_equal("snapshot.proj.thing", opts.items[1].unique_id)
                callback(nil)
            end,
        },
    }, function() require("dbtpal.workflows").goto_model() end)
    vim.api.nvim_buf_delete(buf, { force = true })
end)

it("offers the current node's YAML declaration while walking", function()
    with_project(function(project)
        local calls = 0
        with_stubs({
            {
                require "dbtpal.picker",
                "select",
                function(opts, callback)
                    calls = calls + 1
                    if calls == 1 then
                        for _, item in ipairs(opts.items) do
                            if item.unique_id == "model.project.orders" then return callback(item) end
                        end
                        error "model candidate missing"
                    end
                    local yml = vim.tbl_filter(function(item) return item.yml end, opts.items)
                    check_equal(1, #yml)
                    callback(yml[1])
                end,
            },
        }, function() require("dbtpal.workflows").walk "orders" end)
        check_equal(2, calls)
        check_equal(project .. "/models/schema.yml", vim.api.nvim_buf_get_name(0))
    end)
end)

it("opens source table declarations from walk centers", function()
    with_project(function(project)
        local index
        require("dbtpal.graph_cache").load(project, function(value) index = value end)
        check_true(index ~= nil)
        require("dbtpal.goto").goto_declaration(project, index.nodes["source.project.raw.orders"])
        check_equal(project .. "/dataset/orders.yml", vim.api.nvim_buf_get_name(0))
        check_equal(4, vim.api.nvim_win_get_cursor(0)[1])
    end)
end)

it("warns once for flow-config models missing from the graph", function()
    with_project(function(project)
        vim.fn.writefile({ "models: [{name: ghost}]" }, project .. "/dataset/flow.yml")
        require("dbtpal.config").options.yaml_flow_files = { [project .. "/dataset/flow.yml"] = "ghost" }
        require("dbtpal.graph_cache").load(project, function() end)
        vim.cmd.edit(project .. "/models/ghost.sql")
        vim.bo.filetype = "sql"
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local warnings = 0
        with_stubs({
            {
                require "dbtpal.log",
                "warn",
                function(msg)
                    if msg:find("yaml_flow_files", 1, true) then warnings = warnings + 1 end
                end,
            },
        }, function()
            require("dbtpal.workflows").goto_model()
            require("dbtpal.workflows").goto_model()
        end)
        check_equal(1, warnings)
        check_equal(project .. "/dataset/flow.yml", vim.api.nvim_buf_get_name(0))
    end)
end)
