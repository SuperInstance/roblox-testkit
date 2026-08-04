-- src/runner.lua
-- CLI runner for roblox-testkit.
--
-- Usage:
--   lua src/runner.lua [options] <spec-file>
--
-- Options:
--   --junit <path>   Write a JUnit XML report to <path>
--   --no-color       Disable ANSI colors in terminal output
--   --help, -h       Show this message

local runnerDir = arg[0]:match("^(.*)[/\\]") or "."
local srcDir = runnerDir
package.path = srcDir .. "/?.lua;" .. srcDir .. "/?/init.lua;" .. package.path

local robloxMock = require("roblox_mock")
local testkit = require("testkit")
local reporter = require("reporter")

-- Preload so spec files can require them by name.
package.loaded["testkit"] = testkit
package.loaded["reporter"] = reporter

-- Install a fresh mock world into the global environment. The same world is
-- exposed to testkit.loadModule so the spec and the modules it loads share
-- the same mocked instances.
local mock = robloxMock.install()
mock.create = robloxMock.create
mock.install = robloxMock.install
package.loaded["roblox_mock"] = mock

local helpText = [[
Usage: lua src/runner.lua [options] <spec-file>

Options:
  --junit <path>   Write a JUnit XML report to <path>
  --no-color       Disable ANSI colors in terminal output
  --help, -h       Show this message

Example:
  lua src/runner.lua example/spec_example.lua
  lua src/runner.lua --junit results.xml example/spec_example.lua
]]

local specPath, junitPath, noColor
local i = 1
while arg[i] do
    local a = arg[i]
    if a == "--junit" or a == "-j" then
        junitPath = arg[i + 1]
        if not junitPath then
            io.stderr:write("Error: --junit requires a path argument\n")
            os.exit(1)
        end
        i = i + 1
    elseif a == "--no-color" then
        noColor = true
    elseif a == "--help" or a == "-h" then
        io.write(helpText)
        os.exit(0)
    elseif a:sub(1, 1) == "-" then
        io.stderr:write("Error: unknown option " .. a .. "\n")
        os.exit(1)
    else
        specPath = a
    end
    i = i + 1
end

if not specPath then
    io.stderr:write("Error: no spec file provided\n\n" .. helpText)
    os.exit(1)
end

-- Add the spec file's directory to package.path so its local requires work.
local specDir = specPath:match("^(.*)[/\\]") or "."
package.path = specDir .. "/?.lua;" .. specDir .. "/?/init.lua;" .. package.path

local function fileName(p)
    return p:match("([^/\\]+)%.lua$") or p
end

local specScript = mock.Instance.new("ModuleScript", fileName(specPath))
specScript.Source = "-- spec: " .. specPath
specScript.Parent = mock.game.ServerScriptService
_G.script = specScript

testkit.reset()

local ok, err = pcall(dofile, specPath)
if not ok then
    io.stderr:write("Failed to load spec '" .. specPath .. "':\n" .. tostring(err) .. "\n")
    io.stderr:write(debug.traceback() .. "\n")
    os.exit(2)
end

local results = testkit.run()

if junitPath then
    local junitOk, junitErr = pcall(reporter.writeJUnit, results, junitPath)
    if not junitOk then
        io.stderr:write("Failed to write JUnit report: " .. tostring(junitErr) .. "\n")
    else
        print("JUnit report written to " .. junitPath)
    end
end

io.write(reporter.toTerminal(results, {noColor = noColor}))

if results.failed > 0 or #results.errors > 0 then
    os.exit(1)
end
os.exit(0)
