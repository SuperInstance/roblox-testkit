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
local luauStrip = require("luau_strip")

-- Load TestEZ compatibility layer (optional, for TestEZ-style specs)
local testezCompatOk, testezCompat = pcall(require, "testez_compat")

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

-- Inject BDD globals so spec files can use describe/it/expect directly.
_G.describe = testkit.describe
_G.it = testkit.it
_G.beforeEach = testkit.beforeEach
_G.afterEach = testkit.afterEach
_G.beforeAll = testkit.beforeAll
_G.afterAll = testkit.afterAll
_G.expect = testkit.expect

-- If TestEZ compat loaded, also provide TestEZ-style expect
if testezCompatOk then
    _G.expect = testezCompat
end

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

-- Build a project tree so `script.Parent.src` resolves correctly.
-- The tree mirrors a typical Roblox project layout:
--   ReplicatedStorage (or ServerScriptService)
--   └── <project-root>      ← script.Parent
--       ├── spec/            ← script lives here
--       └── src/             ← script.Parent.src
local projectRoot = mock.Instance.new("Folder", "ProjectRoot")
projectRoot.Parent = mock.game.ReplicatedStorage

local specFolder = mock.Instance.new("Folder", "spec")
specFolder.Parent = projectRoot

local srcFolder = mock.Instance.new("Folder", "src")
srcFolder.Parent = projectRoot

specScript.Parent = specFolder

-- Wire `script.Parent` to project root by setting it directly
-- The mock Instance supports Parent assignment
specScript.Parent = projectRoot

-- Make src available on the parent so `script.Parent.src` works
projectRoot.src = srcFolder

-- Wire require() to handle Instance arguments (Roblox-style require of ModuleScript)
local projectDir = specDir:gsub("[/\\]spec$", "")
if projectDir == specDir then
    -- Maybe specDir IS "spec" (relative)
    projectDir = "."
end
package.path = projectDir .. "/src/?.lua;" .. projectDir .. "/src/?/init.lua;" .. package.path

local realRequire = require
local function smartRequire(modname)
    if type(modname) == "table" and modname.Name then
        -- Instance-style require — resolve by name
        local name = modname.Name
        local path = projectDir .. "/src/" .. name .. ".lua"
        local init = projectDir .. "/src/init.lua"
        local file = io.open(path, "r")
        if file then
            file:close()
            local chunk, err = luauStrip.loadFile(path)
            if chunk then
                local env = getfenv(chunk)
                for k, v in pairs(_G) do
                    if rawget(env, k) == nil then
                        env[k] = v
                    end
                end
                env.script = mock.Instance.new("ModuleScript", name)
                env.script.Parent = projectRoot
                setfenv(chunk, env)
                return chunk()
            end
        end
        -- Try init.lua for src
        file = io.open(init, "r")
        if file then
            file:close()
            local chunk, err = luauStrip.loadFile(init)
            if chunk then
                local env = getfenv(chunk)
                for k, v in pairs(_G) do
                    if rawget(env, k) == nil then
                        env[k] = v
                    end
                end
                env.script = mock.Instance.new("ModuleScript", "init")
                env.script.Parent = srcFolder
                setfenv(chunk, env)
                return chunk()
            end
        end
        error("Could not resolve require(Instance: " .. tostring(name) .. ")")
    end
    return realRequire(modname)
end
_G.require = smartRequire

_G.script = specScript

testkit.reset()

local ok, result = pcall(dofile, specPath)
if not ok then
    io.stderr:write("Failed to load spec '" .. specPath .. "':\n" .. tostring(result) .. "\n")
    io.stderr:write(debug.traceback() .. "\n")
    os.exit(2)
end

-- If the spec returned a function (common TestEZ pattern), call it
if type(result) == "function" then
    local callOk, callErr = pcall(result)
    if not callOk then
        io.stderr:write("Failed to run spec function: " .. tostring(callErr) .. "\n")
        os.exit(2)
    end
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
