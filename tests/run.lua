local failures = 0

local lua_assert = assert
local assertions = {
    equal = function(expected, actual, message)
        if expected ~= actual then
            error(message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)), 2)
        end
    end,
    same = function(expected, actual, message)
        if not vim.deep_equal(expected, actual) then
            error(message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)), 2)
        end
    end,
}
local function check_equal(expected, actual, message)
    if expected ~= actual then
        error(message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)), 2)
    end
end
local function check_same(expected, actual, message)
    if not vim.deep_equal(expected, actual) then
        error(message or ("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)), 2)
    end
end
local function check_true(value, message) lua_assert(value, message or "expected a truthy value") end
_G.check_equal = check_equal
_G.check_same = check_same
_G.check_true = check_true
setmetatable(assertions, { __call = function(_, ...) return lua_assert(...) end })
_G.assert = assertions

function before_each(callback) _G._before_each = callback end
function it(name, callback)
    local ok, err = xpcall(function()
        if _G._before_each then _G._before_each() end
        callback()
    end, debug.traceback)
    if ok then
        print("PASS " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. "\n" .. err)
    end
end
function describe(_, callback) callback() end

dofile "tests/dbtpal_spec.lua"
dofile "tests/syntax_spec.lua"
if failures > 0 then error(failures .. " test(s) failed") end
