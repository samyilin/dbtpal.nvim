local function load_model(lines)
    vim.cmd "syntax on"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "sql"
    vim.b.current_syntax = nil
    vim.cmd "runtime syntax/dbt.vim"
    return buf
end

local function groups(line, col)
    local names = {}
    for _, id in ipairs(vim.fn.synstack(line, col)) do
        names[#names + 1] = vim.fn.synIDattr(id, "name")
    end
    return names
end

local function has_at(line, text, group)
    local col = vim.fn.getline(line):find(text, 1, true)
    assert(col, "missing text: " .. text)
    assert.True(vim.tbl_contains(groups(line, col), group), line .. ":" .. text .. " should have " .. group)
end

local function absent_at(line, text, group)
    local col = vim.fn.getline(line):find(text, 1, true)
    assert(col, "missing text: " .. text)
    assert.True(not vim.tbl_contains(groups(line, col), group), line .. ":" .. text .. " should not have " .. group)
end

it("highlights SQL keywords outside templates", function()
    load_model { "select * from {{ ref('x') }} where y = 1" }
    has_at(1, "select", "sqlStatement")
    has_at(1, "from", "sqlKeyword")
    absent_at(1, "from", "jinjaStatement")
end)

it("closes Jinja regions at }} with trailing SQL", function()
    load_model {
        "with a as (",
        "    select * from {{ ref('x') }} where y = 1",
        ")",
        "",
        "select 2",
    }
    has_at(2, "where", "sqlKeyword")
    absent_at(2, "where", "dbtJinjaTemplate")
    has_at(5, "select", "sqlStatement")
    absent_at(5, "select", "dbtJinjaTemplate")
end)

it("does not accumulate template regions across ref lines", function()
    load_model {
        "with a as (",
        "    select * from {{ ref('x') }} where y = 1",
        "),",
        "b as (",
        "    select * from {{ ref('y') }} where z = 2",
        ")",
        "select * from b",
    }
    has_at(5, "select", "sqlStatement")
    absent_at(5, "select", "dbtJinjaTemplate")
    has_at(7, "select", "sqlStatement")
    absent_at(7, "select", "dbtJinjaTemplate")
end)

it("highlights Jinja internals", function()
    load_model { "select * from {{ ref('x') }} where y = {{ v | trim }}" }
    has_at(1, "ref", "dbtJinjaFunction")
    has_at(1, "trim", "jinjaFilter")
    has_at(1, "{{", "dbtJinjaOperator")
end)

it("highlights dbt context objects and config keys", function()
    load_model {
        "{{ config(materialized='table') }}",
        "select {{ target.name }}, {{ run_started_at }}",
    }
    has_at(1, "materialized", "dbtJinjaConfig")
    has_at(2, "target", "dbtJinjaVariable")
    has_at(2, "run_started_at", "dbtJinjaVariable")
end)

it("paints Jinja comments as comments", function()
    load_model { "{#- a comment #}", "select 1" }
    has_at(1, "comment", "jinjaComBlock")
    has_at(2, "select", "sqlStatement")
end)
