-- src/reporter.lua
-- Terminal and JUnit XML reporting for roblox-testkit.

local reporter = {}

local colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    gray = "\27[90m"
}

local function shouldUseColor(options)
    if options and options.noColor then return false end
    if os.getenv("NO_COLOR") then return false end
    if os.getenv("TERM") == "dumb" then return false end
    return true
end

local function colorize(code, text, options)
    if shouldUseColor(options) then
        return colors[code] .. text .. colors.reset
    end
    return text
end

-----------------------------------------------------------------------------
-- Terminal output
-----------------------------------------------------------------------------

function reporter.toTerminal(results, options)
    options = options or {}
    local lines = {}

    table.insert(lines, colorize("bold", "Roblox TestKit", options))
    table.insert(lines, string.rep("=", 40))

    for _, test in ipairs(results.tests) do
        local symbol, cname
        if test.status == "passed" then
            symbol, cname = "[PASS]", "green"
        elseif test.status == "skipped" then
            symbol, cname = "[SKIP]", "yellow"
        else
            symbol, cname = "[FAIL]", "red"
        end

        local path = test.suitePath
        if path ~= "" then path = path .. " > " end
        local line = colorize(cname, symbol, options) .. " " .. path .. test.name
        line = line .. colorize("gray", string.format(" (%.3fs)", test.duration or 0), options)
        table.insert(lines, line)

        if test.status == "failed" then
            for _, err in ipairs(test.errors) do
                local phase = err.phase and ("[" .. err.phase .. "] ") or ""
                table.insert(lines, "  " .. colorize("red", "Error: ", options) .. phase .. tostring(err.message))
                if err.trace and err.trace ~= "" then
                    table.insert(lines, "  " .. colorize("gray", "Stack trace:", options))
                    for traceLine in err.trace:gmatch("[^\r\n]+") do
                        table.insert(lines, "    " .. traceLine)
                    end
                end
            end
        end
    end

    if #results.errors > 0 then
        table.insert(lines, "")
        table.insert(lines, colorize("red", "Suite-level hook failures:", options))
        for _, err in ipairs(results.errors) do
            table.insert(lines, "  [" .. (err.phase or "hook") .. "] " .. tostring(err.message))
        end
    end

    table.insert(lines, string.rep("-", 40))
    local total = results.passed + results.failed + results.skipped
    local summary = string.format("%d tests, %d passed, %d failed, %d skipped (%.3fs)",
        total, results.passed, results.failed, results.skipped, results.duration or 0)
    local summaryColor = (results.failed > 0 or #results.errors > 0) and "red" or "green"
    table.insert(lines, colorize(summaryColor, summary, options))

    return table.concat(lines, "\n") .. "\n"
end

function reporter.print(results, options)
    io.write(reporter.toTerminal(results, options))
end

-----------------------------------------------------------------------------
-- JUnit XML output
-----------------------------------------------------------------------------

local function escapeXml(s)
    s = tostring(s or "")
    return s:gsub("&", "&amp;")
            :gsub("<", "&lt;")
            :gsub(">", "&gt;")
            :gsub('"', "&quot;")
            :gsub("'", "&apos;")
end

local function escapeCdata(s)
    s = tostring(s or "")
    return s:gsub("]]>", "]]]]><![CDATA[>")
end

function reporter.toJUnit(results)
    local bySuite = {}
    for _, test in ipairs(results.tests) do
        local path = test.suitePath ~= "" and test.suitePath or "Default"
        if not bySuite[path] then bySuite[path] = {} end
        table.insert(bySuite[path], test)
    end

    local lines = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<testsuites>'
    }

    for suiteName, tests in pairs(bySuite) do
        local failures = 0
        local time = 0
        for _, t in ipairs(tests) do
            if t.status == "failed" then failures = failures + 1 end
            time = time + (t.duration or 0)
        end

        table.insert(lines, string.format(
            '  <testsuite name="%s" tests="%d" failures="%d" errors="0" time="%.3f">',
            escapeXml(suiteName), #tests, failures, time))

        for _, t in ipairs(tests) do
            table.insert(lines, string.format(
                '    <testcase name="%s" classname="%s" time="%.3f">',
                escapeXml(t.name), escapeXml(suiteName), t.duration or 0))

            if t.status == "failed" then
                for _, err in ipairs(t.errors) do
                    local msg = tostring(err.message or "failure")
                    local trace = tostring(err.trace or "")
                    table.insert(lines, string.format(
                        '      <failure message="%s"><![CDATA[%s\n%s]]></failure>',
                        escapeXml(msg), escapeCdata(msg), escapeCdata(trace)))
                end
            end

            table.insert(lines, '    </testcase>')
        end

        table.insert(lines, '  </testsuite>')
    end

    table.insert(lines, '</testsuites>')
    return table.concat(lines, "\n") .. "\n"
end

function reporter.writeJUnit(results, path)
    local file, err = io.open(path, "w")
    if not file then
        error("Could not open JUnit output file '" .. path .. "': " .. tostring(err))
    end
    file:write(reporter.toJUnit(results))
    file:close()
end

return reporter
