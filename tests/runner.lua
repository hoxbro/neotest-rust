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

    ---@diagnostic disable-next-line: inject-field
    info.traceback = debug.traceback("", level)
    ---@diagnostic disable-next-line: inject-field
    info.message = msg

    return trimTrace(info)
end

-- Shadow print so output is reliably flushed
print = function(...)
    local args = { ... }
    for i, v in ipairs(args) do
        io.stdout:write(tostring(v))
        if i < #args then
            io.stdout:write("\t")
        end
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

local TERM_WIDTH = (function()
    local tty = vim.uv.new_tty(1, false)
    if tty then
        local w = tty:get_winsize()
        tty:close()
        if w and w > 0 then
            return w
        end
    end
    return 80
end)()

local color_table = {
    yellow = 33,
    green = 32,
    red = 31,
    bold = 1,
}

local color_string = function(color, str)
    return string.format("%s[%sm%s%s[%sm", string.char(27), color_table[color] or 0, str, string.char(27), 0)
end

--- Build a centered line like "======== text ========" padded to TERM_WIDTH.
local function centered_line(text, fill_char)
    fill_char = fill_char or "="
    if #text == 0 then
        return string.rep(fill_char, TERM_WIDTH)
    end
    local pad = TERM_WIDTH - #text - 2
    if pad < 2 then
        return text
    end
    local left = math.floor(pad / 2)
    local right = pad - left
    return string.rep(fill_char, left) .. " " .. text .. " " .. string.rep(fill_char, right)
end

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

-- Cumulative counters across all files (set in mod.run)
local grand_total = 0
local grand_done = 0
local grand_deselected = 0
local had_any_failure = false
local verbose = false
local current_file = ""
local filter_pattern = nil

mod.describe = function(desc, func)
    results.pass = results.pass or {}
    results.fail = results.fail or {}
    results.errs = results.errs or {}
    results.skip = results.skip or {}

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

local function verbose_line(desc_stack, status_str, status_color)
    local pct = grand_total > 0 and math.floor(grand_done / grand_total * 100) or 100
    local pct_color = had_any_failure and "red" or "green"
    local suffix = color_string(pct_color, string.format("[%3d%%]", pct))
    local name = current_file .. "::" .. table.concat(desc_stack, "::")
    local label = color_string(status_color, status_str)
    local plain_len = #name + 1 + #status_str + 1 + 6 -- 6 = "[xxx%]"
    local padding = math.max(1, TERM_WIDTH - plain_len)
    print(name .. " " .. label .. string.rep(" ", padding) .. suffix)
end

mod.it = function(desc, func)
    if filter_pattern then
        local full_name = current_file .. "::" .. table.concat(current_description, "::") .. "::" .. desc
        if vim.fn.match(full_name, filter_pattern) == -1 then
            grand_deselected = grand_deselected + 1
            return
        end
    end

    run_each(current_before_each)
    local ok, msg, desc_stack = call_inner(desc, func)
    run_each(current_after_each)

    local test_result = { file = current_file, descriptions = desc_stack, msg = nil }
    grand_done = grand_done + 1

    if not ok then
        test_result.msg = msg
        had_any_failure = true
        table.insert(results.fail, test_result)
        table.insert(results._ordered, { kind = "fail", cumulative = grand_done })
        if verbose then
            verbose_line(desc_stack, "FAILED", "red")
        end
    else
        table.insert(results.pass, test_result)
        table.insert(results._ordered, { kind = "pass", cumulative = grand_done })
        if verbose then
            verbose_line(desc_stack, "PASSED", "green")
        end
    end
end

mod.pending = function(desc, _)
    if filter_pattern then
        local full_name = current_file .. "::" .. table.concat(current_description, "::") .. "::" .. desc
        if vim.fn.match(full_name, filter_pattern) == -1 then
            grand_deselected = grand_deselected + 1
            return
        end
    end

    local curr_stack = vim.deepcopy(current_description)
    table.insert(curr_stack, desc)
    table.insert(results.skip, { descriptions = curr_stack })
    grand_done = grand_done + 1
    table.insert(results._ordered, { kind = "skip", cumulative = grand_done })
    if verbose then
        verbose_line(curr_stack, "SKIPPED", "yellow")
    end
end

-- Set globals
_PlenaryBustedOldAssert = _PlenaryBustedOldAssert or assert
describe = mod.describe
it = mod.it
pending = mod.pending
before_each = mod.before_each
after_each = mod.after_each
---@diagnostic disable-next-line: lowercase-global
clear = mod.clear
assert = require("luassert")

--- Count total tests in a file without running them, by temporarily
--- replacing `it` and `pending` with counters.
local function count_tests_in_file(file)
    local count = 0
    local saved_it = it
    local saved_pending = pending
    local saved_describe = describe
    local saved_before_each = before_each
    local saved_after_each = after_each
    local count_desc = {}

    local function matches_filter(desc)
        if not filter_pattern then
            return true
        end
        local full_name = file .. "::" .. table.concat(count_desc, "::") .. "::" .. desc
        return vim.fn.match(full_name, filter_pattern) ~= -1
    end

    it = function(desc, _)
        if matches_filter(desc) then
            count = count + 1
        end
    end
    pending = function(desc, _)
        if matches_filter(desc) then
            count = count + 1
        end
    end
    describe = function(desc, func)
        table.insert(count_desc, desc)
        func()
        count_desc[#count_desc] = nil
    end
    before_each = function(_) end
    after_each = function(_) end

    local loaded = loadfile(file)
    if loaded then
        local ok, _ = pcall(function()
            coroutine.wrap(function()
                loaded()
            end)()
        end)
        if not ok then
            count = 1 -- at least 1 for the error
        end
    else
        count = 1
    end

    it = saved_it
    pending = saved_pending
    describe = saved_describe
    before_each = saved_before_each
    after_each = saved_after_each

    return count
end

--- Print a single file's test line in pytest format:
---   filepath .F..s                                              [XXX%]
--- When markers overflow, they wrap to continuation lines like pytest.
--- The line never exceeds TERM_WIDTH visible characters.
--- The [XXX%] suffix is colored green if all passed, red if any failed.
local function print_file_line(file, file_results)
    local pct = grand_total > 0 and math.floor(grand_done / grand_total * 100) or 100
    local suffix = string.format("[%3d%%]", pct)
    -- suffix is 6 chars, plus 1 space before it = 7 reserved at end
    local reserved = #suffix + 1

    local prefix = file .. " "
    local prefix_len = #prefix

    -- Build the ordered marker list (.Fs)
    local markers = {}
    local file_had_failure = false
    for _, r in ipairs(file_results._ordered) do
        if r.kind == "pass" then
            table.insert(markers, ".")
        elseif r.kind == "fail" then
            table.insert(markers, "F")
            file_had_failure = true
        elseif r.kind == "error" then
            table.insert(markers, "E")
            file_had_failure = true
        elseif r.kind == "skip" then
            table.insert(markers, "s")
        end
    end

    local suffix_color = had_any_failure and "red" or "green"

    --- Color a single marker character
    local function color_marker(m)
        if m == "F" or m == "E" then
            return color_string("red", m)
        elseif m == "s" then
            return color_string("yellow", m)
        else
            return color_string("green", m)
        end
    end

    -- How many marker chars fit on the first line (with prefix)?
    local first_avail = TERM_WIDTH - prefix_len - reserved
    if first_avail < 1 then
        first_avail = 1
    end
    -- Continuation lines have no prefix, just markers right-aligned
    local cont_avail = TERM_WIDTH - reserved

    local pos = 1
    local total_markers = #markers
    local is_first = true

    while pos <= total_markers do
        local avail = is_first and first_avail or cont_avail
        local chunk_end = math.min(pos + avail - 1, total_markers)
        local chunk_len = chunk_end - pos + 1

        local colored = ""
        for i = pos, chunk_end do
            colored = colored .. color_marker(markers[i])
        end

        local line_prefix = is_first and prefix or ""
        local padding = avail - chunk_len
        if padding < 0 then
            padding = 0
        end

        -- Show percentage based on cumulative progress of last marker in chunk
        local chunk_pct = math.floor(file_results._ordered[chunk_end].cumulative / grand_total * 100)
        local chunk_suffix = string.format("[%3d%%]", chunk_pct)
        print(line_prefix .. colored .. string.rep(" ", padding) .. " " .. color_string(suffix_color, chunk_suffix))

        pos = chunk_end + 1
        is_first = false
    end

    -- Edge case: no markers at all (empty file)
    if total_markers == 0 then
        local padding = TERM_WIDTH - prefix_len - reserved
        if padding < 0 then
            padding = 0
        end
        print(prefix .. string.rep(" ", padding) .. " " .. color_string(suffix_color, suffix))
    end
end

local _single_run = function(file)
    file = file:gsub("\\", "/")
    current_file = file
    results = {}
    results.pass = {}
    results.fail = {}
    results.errs = {}
    results.skip = {}
    results._ordered = {}

    local loaded, msg = loadfile(file)
    if not loaded then
        grand_done = grand_done + 1
        had_any_failure = true
        table.insert(results.errs, { file = file, descriptions = {}, msg = msg })
        table.insert(results._ordered, { kind = "error" })
        if not verbose then
            print_file_line(file, results)
        end
        return results
    end

    coroutine.wrap(function()
        loaded()
    end)()

    if not results.pass then
        results.pass = {}
        results.fail = {}
        results.errs = {}
        results.skip = {}
        results._ordered = {}
    end

    if not verbose and #results._ordered > 0 then
        print_file_line(file, results)
    end
    return results
end

--- Collect spec files from the given paths and run them all.
--- Prints a final summary and exits with the appropriate code.
mod.run = function()
    local files = {}
    local i = 1
    while i <= #_G.arg do
        local path = _G.arg[i]
        if path == "-v" or path == "--verbose" then
            verbose = true
        elseif path == "-k" or path == "--filter" then
            i = i + 1
            filter_pattern = _G.arg[i]
        else
            local stat = vim.uv.fs_stat(path)
            if stat and stat.type == "directory" then
                vim.list_extend(files, vim.fn.globpath(path, "**/test_*.lua", true, true))
            elseif stat then
                table.insert(files, path)
            end
        end
        i = i + 1
    end
    table.sort(files)

    -- Count total tests across all files for percentage calculation
    grand_total = 0
    grand_done = 0
    for _, file in ipairs(files) do
        grand_total = grand_total + count_tests_in_file(file)
    end

    local start_time = vim.uv.hrtime()

    print(color_string("bold", centered_line("test session starts")))
    local uname = vim.uv.os_uname()
    local nv = vim.version()
    local nvim_ver = string.format("Neovim %d.%d.%d", nv.major, nv.minor, nv.patch)
    local lua_ver = jit and jit.version or _VERSION
    print(string.format("platform %s -- %s, %s", uname.sysname:lower(), nvim_ver, lua_ver))
    print("rootdir: " .. vim.uv.cwd())
    if filter_pattern then
        print(
            string.format(
                "collected %d items / %d selected (%s)",
                grand_total + grand_deselected,
                grand_total,
                filter_pattern
            )
        )
    else
        print(string.format("collected %d items", grand_total))
    end
    print("")

    local total_pass, total_fail, total_errs, total_skip = 0, 0, 0, 0
    local all_failures = {}
    local all_errors = {}

    for _, file in ipairs(files) do
        local res = _single_run(file)
        total_pass = total_pass + #res.pass
        total_fail = total_fail + #res.fail
        total_errs = total_errs + #res.errs
        total_skip = total_skip + #res.skip

        for _, f in ipairs(res.fail) do
            table.insert(all_failures, f)
        end
        for _, e in ipairs(res.errs) do
            table.insert(all_errors, e)
        end
    end

    local elapsed = (vim.uv.hrtime() - start_time) / 1e9

    -- Print failures section
    if #all_failures > 0 then
        print("")
        print(color_string("red", centered_line("FAILURES")))
        for _, f in ipairs(all_failures) do
            local name = (f.file or "") .. "::" .. table.concat(f.descriptions, " :: ")
            print(color_string("red", centered_line(name, "_")))
            if f.msg then
                print(indent(f.msg, 4))
            end
        end
    end

    -- Print errors section
    if #all_errors > 0 then
        print("")
        print(color_string("red", centered_line("ERRORS")))
        for _, e in ipairs(all_errors) do
            local desc = #e.descriptions > 0 and (e.file or "") .. "::" .. table.concat(e.descriptions, " :: ")
                or (e.file or "(load error)")
            print(color_string("red", centered_line(desc, "_")))
            if e.msg then
                print(indent(e.msg, 4))
            end
        end
    end

    -- Short test summary info (like pytest)
    if #all_failures > 0 or #all_errors > 0 then
        print(color_string("red", centered_line("short test summary info")))
        for _, f in ipairs(all_failures) do
            local name = (f.file or "") .. "::" .. table.concat(f.descriptions, "::")
            print(color_string("red", "FAILED") .. " " .. name)
        end
        for _, e in ipairs(all_errors) do
            local desc = #e.descriptions > 0 and (e.file or "") .. "::" .. table.concat(e.descriptions, "::")
                or (e.file or "(load error)")
            print(color_string("red", "ERROR") .. " " .. desc)
        end
    end

    -- Build summary line
    local parts = {}
    local plain_parts = {}
    if total_fail > 0 then
        table.insert(parts, color_string("red", total_fail .. " failed"))
        table.insert(plain_parts, total_fail .. " failed")
    end
    if total_errs > 0 then
        table.insert(parts, color_string("red", total_errs .. " errors"))
        table.insert(plain_parts, total_errs .. " errors")
    end
    if total_pass > 0 then
        table.insert(parts, color_string("green", total_pass .. " passed"))
        table.insert(plain_parts, total_pass .. " passed")
    end
    if total_skip > 0 then
        table.insert(parts, color_string("yellow", total_skip .. " skipped"))
        table.insert(plain_parts, total_skip .. " skipped")
    end
    if grand_deselected > 0 then
        table.insert(parts, color_string("yellow", grand_deselected .. " deselected"))
        table.insert(plain_parts, grand_deselected .. " deselected")
    end

    local time_str = string.format("in %.2fs", elapsed)
    local summary_text = table.concat(parts, ", ") .. " " .. time_str
    local summary_plain = table.concat(plain_parts, ", ") .. " " .. time_str

    local has_failures = total_fail > 0 or total_errs > 0
    local fill_color = has_failures and "red" or "green"

    -- Build the centered "= summary =" line
    local pad = TERM_WIDTH - #summary_plain - 2
    if pad < 2 then
        print(summary_text)
    else
        local left = math.floor(pad / 2)
        local right = pad - left
        print(
            color_string(fill_color, string.rep("=", left))
                .. " "
                .. summary_text
                .. " "
                .. color_string(fill_color, string.rep("=", right))
        )
    end

    if has_failures then
        vim.cmd("1cq")
    else
        vim.cmd("0cq")
    end
end

return mod
