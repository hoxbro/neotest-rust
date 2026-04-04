-- Derived from plenary.busted — modified to run multiple files without
-- exiting after each one.

local function get_trace(_, level, msg)
    local function trimTrace(info)
        local index = info.traceback:find("\n%s*%[C]")
        info.traceback = info.traceback:sub(1, index)
        return info
    end
    level = level or 3

    local thisdir = vim.fn.fnamemodify(debug.getinfo(1, "Sl").source, ":h")
    local info = debug.getinfo(level, "Sl")
    while
        info.what == "C"
        or info.short_src:match("luassert[/\\].*%.lua$")
        or (info.source:sub(1, 1) == "@" and thisdir == vim.fn.fnamemodify(info.source, ":h"))
    do
        level = level + 1
        info = debug.getinfo(level, "Sl")
    end

    info.traceback = debug.traceback("", level)
    info.message = msg

    return trimTrace(info)
end

-- Shadow print so output is reliably flushed
print = function(...)
    for _, v in ipairs({ ... }) do
        io.stdout:write(tostring(v))
        io.stdout:write("\t")
    end
    io.stdout:write("\r\n")
end

local mod = {}

local results = {}
local current_description = {}
local current_before_each = {}
local current_after_each = {}

local add_description = function(desc)
    table.insert(current_description, desc)
    return vim.deepcopy(current_description)
end

local pop_description = function()
    current_description[#current_description] = nil
end

local add_new_each = function()
    current_before_each[#current_description] = {}
    current_after_each[#current_description] = {}
end

local clear_last_each = function()
    current_before_each[#current_description] = nil
    current_after_each[#current_description] = nil
end

local call_inner = function(desc, func)
    local desc_stack = add_description(desc)
    add_new_each()
    local ok, msg = xpcall(func, function(m)
        local trace = get_trace(nil, 3, m)
        return trace.message .. "\n" .. trace.traceback
    end)
    clear_last_each()
    pop_description()
    return ok, msg, desc_stack
end

local color_table = {
    yellow = 33,
    green = 32,
    red = 31,
}

local color_string = function(color, str)
    return string.format("%s[%sm%s%s[%sm", string.char(27), color_table[color] or 0, str, string.char(27), 0)
end

local SUCCESS = color_string("green", "Success")
local FAIL = color_string("red", "Fail")
local PENDING = color_string("yellow", "Pending")

local HEADER = string.rep("=", 40)

local indent = function(msg, spaces)
    spaces = spaces or 4
    local prefix = string.rep(" ", spaces)
    return prefix .. msg:gsub("\n", "\n" .. prefix)
end

local run_each = function(tbl)
    for _, v in ipairs(tbl) do
        for _, w in ipairs(v) do
            if type(w) == "function" then
                w()
            end
        end
    end
end

mod.format_results = function(res)
    print("")
    print(color_string("green", "Success: "), #res.pass)
    print(color_string("red", "Failed : "), #res.fail)
    print(color_string("red", "Errors : "), #res.errs)
    print(HEADER)
end

mod.describe = function(desc, func)
    results.pass = results.pass or {}
    results.fail = results.fail or {}
    results.errs = results.errs or {}

    describe = mod.inner_describe
    local ok, msg, desc_stack = call_inner(desc, func)
    describe = mod.describe

    if not ok then
        table.insert(results.errs, { descriptions = desc_stack, msg = msg })
    end
end

mod.inner_describe = function(desc, func)
    local ok, msg, desc_stack = call_inner(desc, func)
    if not ok then
        table.insert(results.errs, { descriptions = desc_stack, msg = msg })
    end
end

mod.before_each = function(fn)
    table.insert(current_before_each[#current_description], fn)
end

mod.after_each = function(fn)
    table.insert(current_after_each[#current_description], fn)
end

mod.clear = function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

mod.it = function(desc, func)
    run_each(current_before_each)
    local ok, msg, desc_stack = call_inner(desc, func)
    run_each(current_after_each)

    local test_result = { descriptions = desc_stack, msg = nil }

    if not ok then
        test_result.msg = msg
        table.insert(results.fail, test_result)
        print(FAIL, "||", table.concat(test_result.descriptions, " "))
        print(indent(msg, 12))
    else
        table.insert(results.pass, test_result)
        print(SUCCESS, "||", table.concat(test_result.descriptions, " "))
    end
end

mod.pending = function(desc, _)
    local curr_stack = vim.deepcopy(current_description)
    table.insert(curr_stack, desc)
    print(PENDING, "||", table.concat(curr_stack, " "))
end

-- Set globals
_PlenaryBustedOldAssert = _PlenaryBustedOldAssert or assert
describe = mod.describe
it = mod.it
pending = mod.pending
before_each = mod.before_each
after_each = mod.after_each
clear = mod.clear
---@type Luassert
assert = require("luassert")

local _single_run = function(file)
    file = file:gsub("\\", "/")
    results = {}

    print("\n" .. HEADER)
    print("Testing: ", file)

    local loaded, msg = loadfile(file)
    if not loaded then
        print(HEADER)
        print("FAILED TO LOAD FILE")
        print(color_string("red", msg))
        print(HEADER)
        results.pass = {}
        results.fail = {}
        results.errs = { { descriptions = {}, msg = msg } }
        return results
    end

    coroutine.wrap(function()
        loaded()
    end)()

    if not results.pass then
        results.pass = {}
        results.fail = {}
        results.errs = {}
    end

    mod.format_results(results)
    return results
end

--- Collect spec files from the given paths and run them all.
--- Prints a final summary and exits with the appropriate code.
mod.run = function()
    local files = {}
    for _, path in ipairs(_G.arg) do
        local stat = vim.uv.fs_stat(path)
        if stat and stat.type == "directory" then
            vim.list_extend(files, vim.fn.globpath(path, "**/*_spec.lua", true, true))
        elseif stat then
            table.insert(files, path)
        end
    end

    local total_pass, total_fail, total_errs = 0, 0, 0
    for _, file in ipairs(files) do
        local res = _single_run(file)
        total_pass = total_pass + #res.pass
        total_fail = total_fail + #res.fail
        total_errs = total_errs + #res.errs
    end

    print("\n" .. HEADER)
    print(color_string("green", "Total Success || "), total_pass)
    print(color_string("red", "Total Failed || "), total_fail)
    print(color_string("red", "Total Errors || "), total_errs)
    print(HEADER)

    if total_fail > 0 or total_errs > 0 then
        vim.cmd("1cq")
    else
        vim.cmd("0cq")
    end
end

return mod
