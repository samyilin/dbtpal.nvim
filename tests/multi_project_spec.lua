---@diagnostic disable: need-check-nil
local config = require "dbtpal.config"
local projects = require "dbtpal.projects"
local context = require "dbtpal.context"
local execute = require "dbtpal.execute"
local cache = require "dbtpal.graph_cache"
local graph = require "dbtpal.graph"
local properties = require "dbtpal.properties"
local picker = require "dbtpal.picker"
local workflows = require "dbtpal.workflows"
local fixture = vim.fn.getcwd() .. "/tests/fixtures/dbt.sh"

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

local function write(file, lines)
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.fn.writefile(lines, file)
end

local function with_projects(callback)
    local root = vim.fn.resolve(vim.fn.tempname()) .. " with spaces"
    local a, b = root .. "/a", root .. "/b"
    local cwd, buf = vim.fn.getcwd(), vim.api.nvim_get_current_buf()
    local options = vim.deepcopy(config.options)
    for _, project in ipairs { a, b } do
        write(project .. "/dbt_project.yml", { "name: " .. vim.fs.basename(project) })
        write(project .. "/models/orders.sql", { "select 1" })
        write(project .. "/models/flow.yml", { "models: [{name: orders}]" })
    end
    local ok, err = xpcall(function()
        config.setup {
            path_to_dbt = "/bin/sh",
            pre_cmd_args = { fixture },
            path_to_dbt_profiles_dir = "",
            include_log_level = false,
        }
        vim.cmd.edit(a .. "/models/orders.sql")
        callback(a, b, root)
    end, debug.traceback)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_set_current_dir(cwd)
    for _, current in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(current):sub(1, #root) == root then
            vim.api.nvim_buf_delete(current, { force = true })
        end
    end
    for _, project in ipairs { a, b } do
        for _, prefix in ipairs { "graph-", "yaml-" } do
            vim.fn.delete(
                vim.fs.joinpath(vim.fn.stdpath "cache", "dbtpal", prefix .. vim.fn.sha256(project) .. ".json")
            )
        end
    end
    vim.fn.delete(root, "rf")
    config.setup(options)
    if not ok then error(err) end
end

before_each(function() config.setup { include_log_level = false } end)

it("resolves relative paths after cwd changes and Oil project directories", function()
    with_projects(function(a, b)
        vim.api.nvim_set_current_dir(a)
        check_equal(a, projects.resolve "models/orders.sql")
        vim.api.nvim_set_current_dir(b)
        check_equal(b, projects.resolve "models/orders.sql")
        check_equal(a, projects.resolve("oil://" .. a .. "/"))
        vim.cmd.edit("oil://" .. b .. "/")
        check_equal(b, context.project_for_buffer())
        vim.cmd.edit "fugitive:///repo/.git//0/models/orders.sql"
        check_true(context.project_for_buffer() == nil)
    end)
end)

it("discovers newly created and nested project markers without stale hits", function()
    with_projects(function(a, _, root)
        local fresh, nested = root .. "/fresh", a .. "/nested"
        write(fresh .. "/models/new.sql", { "select 1" })
        check_true(projects.resolve(fresh .. "/models/new.sql") == nil)
        write(fresh .. "/dbt_project.yml", { "name: fresh" })
        check_equal(fresh, projects.resolve(fresh .. "/models/new.sql"))
        write(nested .. "/models/new.sql", { "select 1" })
        check_equal(a, projects.resolve(nested .. "/models/new.sql"))
        write(nested .. "/dbt_project.yml", { "name: nested" })
        check_equal(nested, projects.resolve(nested .. "/models/new.sql"))
        vim.fn.delete(nested .. "/dbt_project.yml")
        check_equal(a, projects.resolve(nested .. "/models/new.sql"))
    end)
end)

it("pins a relative configured project across cwd and buffer changes", function()
    with_projects(function(a, b, root)
        vim.api.nvim_set_current_dir(root)
        config.setup { path_to_dbt_project = "./a/", include_log_level = false }
        vim.api.nvim_set_current_dir(b)
        vim.cmd.edit(b .. "/models/orders.sql")
        check_equal(a, context.project_for_buffer())
        check_equal(a, context.project_for_buffer())
    end)
end)

it("keeps gf paths local to each project's buffer", function()
    with_projects(function(a, b)
        local a_buf = vim.api.nvim_get_current_buf()
        vim.cmd.edit(b .. "/models/orders.sql")
        for _, entry in ipairs { { a_buf, a, b }, { 0, b, a } } do
            vim.api.nvim_buf_call(entry[1], function()
                local path = vim.opt_local.path:get()
                check_true(vim.tbl_contains(path, entry[2] .. "/models/**"))
                check_true(not vim.tbl_contains(path, entry[3] .. "/models/**"))
            end)
        end
        check_equal("", config.options.path_to_dbt_project)
    end)
end)

it("captures the buffer project in independent public execute calls", function()
    with_projects(function(a, b)
        local results = {}
        require("dbtpal").execute("args", {}, function(result) results.a = result end)
        vim.cmd.edit(b .. "/models/orders.sql")
        require("dbtpal").execute("args", {}, function(result) results.b = result end)
        require("dbtpal").execute("args", {}, function(result) results.explicit = result end, { project = a })
        check_true(vim.wait(3000, function() return results.a and results.b and results.explicit end))
        for key, project in pairs { a = a, b = b, explicit = a } do
            check_equal(0, results[key].code)
            check_equal("args\n--project-dir\n" .. project .. "\n", results[key].stdout)
        end
    end)
end)

it("isolates live resource listings and graph fallback caches", function()
    with_projects(function(a, b, root)
        vim.api.nvim_set_current_dir(root)
        local listed, loaded = {}, {}
        require("dbtpal").list_resources({}, function(items, err)
            listed.a, listed.a_err = items, err
        end)
        cache.load("./a", function(index, err)
            loaded.a, loaded.a_err = index, err
        end)
        vim.cmd.edit(b .. "/models/orders.sql")
        require("dbtpal").list_resources({}, function(items, err)
            listed.b, listed.b_err = items, err
        end)
        cache.load(b, function(index, err)
            loaded.b, loaded.b_err = index, err
        end)
        vim.api.nvim_set_current_dir(b)
        check_true(vim.wait(3000, function() return listed.a and listed.b and loaded.a and loaded.b end))
        for name, project in pairs { a = a, b = b } do
            check_true(listed[name .. "_err"] == nil and loaded[name .. "_err"] == nil)
            check_equal("model." .. name .. ".orders", listed[name][1].unique_id)
            check_equal(project, loaded[name].layout.root)
            check_same({ "model." .. name .. ".orders" }, vim.tbl_keys(cache.cached(project).nodes))
        end
    end)
end)

it("publishes command failures against the project captured before a buffer switch", function()
    with_projects(function(a, b)
        config.options.use_quickfix = true
        local completed = false
        with_stubs({
            { require "dbtpal.display", "popup", function() completed = true end },
        }, function()
            require("dbtpal").run_command("test", {}, "notify")
            vim.cmd.edit(b .. "/models/orders.sql")
            check_true(vim.wait(3000, function() return completed end))
        end)
        local entries = vim.fn.getqflist()
        check_equal(1, #entries)
        check_equal(a .. "/models/properties.yml", vim.api.nvim_buf_get_name(entries[1].bufnr))
    end)
end)

it("retains the picker project through delayed fallback and output selection", function()
    with_projects(function(a, b)
        local pending, executed
        local row = { unique_id = "model.a.orders", name = "orders", resource_type = "model", package_name = "a" }
        with_stubs({
            { cache, "load", function(_, callback) pending = callback end },
            { picker, "select_many", function(opts, callback) callback(opts.items) end },
            { vim.ui, "select", function(items, _, callback) callback(items[1]) end },
            {
                execute,
                "run",
                function(command, _, callback, opts)
                    check_equal(a, opts and opts.project)
                    if command == "ls" then
                        callback { code = 0, stdout = vim.json.encode(row), stderr = "" }
                    else
                        executed = command
                    end
                end,
            },
        }, function()
            workflows.select_models()
            vim.cmd.edit(b .. "/models/orders.sql")
            pending(nil, "no graph")
            check_equal("run", executed)
        end)
    end)
end)

it("retains the walk project when choosing a start after switching buffers", function()
    with_projects(function(a, b)
        local pending, loads = nil, 0
        local index = graph.build_index { ["model.a.orders"] = { name = "orders", resource_type = "model" } }
        vim.bo.filetype = "text"
        with_stubs({
            {
                cache,
                "load",
                function(project, callback)
                    loads = loads + 1
                    check_equal(a, project)
                    callback(index)
                end,
            },
            {
                picker,
                "select",
                function(opts, callback)
                    if opts.prompt == "Walk from" then pending = function() callback(opts.items[1]) end end
                end,
            },
        }, function()
            workflows.walk()
            vim.cmd.edit(b .. "/models/orders.sql")
            pending()
            check_equal(2, loads)
        end)
    end)
end)

it("keeps individual and tagged walk actions in their original project", function()
    with_projects(function(a, b)
        local index = graph.build_index {
            ["model.a.orders"] = { name = "orders", resource_type = "model" },
            ["model.a.child"] = {
                name = "child",
                resource_type = "model",
                depends_on = { nodes = { "model.a.orders" } },
            },
        }
        for _, tagged in ipairs { false, true } do
            vim.cmd.edit(a .. "/models/orders.sql")
            local picks, actions, executed = 0, 0, false
            with_stubs({
                { cache, "load", function(_, callback) callback(index) end },
                {
                    picker,
                    "select",
                    function(opts, callback)
                        picks = picks + 1
                        local field = picks == 1 and "unique_id" or (picks == 2 and "tagged" or "operate_all")
                        for _, item in ipairs(opts.items) do
                            if item[field] then return callback(item) end
                        end
                        error "walk choice missing"
                    end,
                },
                {
                    vim.ui,
                    "select",
                    function(_, opts, callback)
                        if opts.prompt == "Show dbt output?" then
                            vim.cmd.edit(b .. "/models/orders.sql")
                            callback "Notify only"
                        else
                            actions = actions + 1
                            callback(tagged and actions == 1 and "tag" or "run")
                        end
                    end,
                },
                {
                    execute,
                    "run",
                    function(_, _, _, opts)
                        check_equal(a, opts.project)
                        executed = true
                    end,
                },
            }, function() workflows.walk "model.a.orders" end)
            check_true(executed)
        end
    end)
end)

it("scopes absolute YAML mappings and cwd fallbacks to the selected project", function()
    with_projects(function(a, b)
        config.options.yaml_flow_files = { [a .. "/models/flow.yml"] = "alpha", [b .. "/models/flow.yml"] = "beta" }
        local a_decls = properties.apply_flow_config(a, {}, {})
        local b_decls = properties.apply_flow_config(b, {}, {})
        check_equal(1, #a_decls)
        check_equal("alpha", a_decls[1].name)
        check_equal(1, #b_decls)
        check_equal("beta", b_decls[1].name)
        write(a .. "/models/only_a.yml", { "models: [{name: alpha}]" })
        vim.api.nvim_set_current_dir(a)
        config.options.yaml_flow_files = { ["models/only_a.yml"] = "alpha", ["../a/models/flow.yml"] = "alpha" }
        check_equal(0, #properties.apply_flow_config(b, {}, {}))
    end)
end)

it("skips independent nested YAML projects while retaining installed packages", function()
    with_projects(function(a, _, root)
        local nested, package_dir = a .. "/nested", a .. "/dbt_packages/dep"
        for _, project in ipairs { nested, package_dir } do
            write(project .. "/dbt_project.yml", { "name: " .. vim.fs.basename(project) })
            write(project .. "/models/schema.yml", { "models:", "  - name: orders" })
            write(project .. "/models/flow.yml", { "models: [{name: orders}]" })
        end
        local decls, issues = properties.scan_with_report(a)
        check_equal(1, #decls)
        check_equal(package_dir .. "/models/schema.yml", decls[1].file)
        check_equal(2, #issues)
        config.options.yaml_flow_files =
            { [nested .. "/models/flow.yml"] = "nested", [package_dir .. "/models/flow.yml"] = "dep" }
        decls = properties.apply_flow_config(a, {}, {})
        check_equal(1, #decls)
        check_equal("dep", decls[1].name)
        local linked = root .. "/local_dependency"
        write(linked .. "/dbt_project.yml", { "name: local_dependency" })
        write(linked .. "/models/schema.yml", { "models:", "  - name: linked" })
        check_true(vim.uv.fs_symlink(linked, a .. "/dbt_packages/linked", { dir = true }))
        check_equal(2, #properties.scan(a))
    end)
end)

it("does not clear another project's test or YAML quickfix report", function()
    with_projects(function(a, b)
        config.options.use_quickfix = true
        local quickfix = require "dbtpal.quickfix"
        local failure = { code = 1, stdout = "Failure in test orders (models/flow.yml)", stderr = "" }
        quickfix.publish("test", failure, a)
        quickfix.publish("test", { code = 0 }, b)
        check_equal(1, #vim.fn.getqflist())
        quickfix.publish("test", { code = 0 }, a)
        check_equal(0, #vim.fn.getqflist())
        properties.report(a, { { file = a .. "/models/flow.yml", lnum = 1 } })
        properties.report(b, {})
        check_equal(1, #vim.fn.getqflist())
        properties.report(a, {})
        check_equal(0, #vim.fn.getqflist())
    end)
end)
