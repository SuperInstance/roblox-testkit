-- src/testkit.lua
-- BDD-style test framework for headless Roblox Lua tests.

local testkit = {}

-----------------------------------------------------------------------------
-- Suite tree
-----------------------------------------------------------------------------

local root = {
    name = "ROOT",
    path = "",
    tests = {},
    children = {},
    beforeEach = {},
    afterEach = {},
    beforeAll = {},
    afterAll = {}
}
local current = root

function testkit.reset()
    root.tests = {}
    root.children = {}
    root.beforeEach = {}
    root.afterEach = {}
    root.beforeAll = {}
    root.afterAll = {}
    current = root
end

function testkit.describe(name, fn)
    local parent = current
    local suite = {
        name = name,
        parent = parent,
        path = (parent.path ~= "" and parent.path .. " > " or "") .. name,
        tests = {},
        children = {},
        beforeEach = {},
        afterEach = {},
        beforeAll = {},
        afterAll = {}
    }
    table.insert(parent.children, suite)
    current = suite
    local ok, err = pcall(fn)
    current = parent
    if not ok then
        error("describe block '" .. name .. "' failed during registration: " .. tostring(err), 2)
    end
end

function testkit.it(name, fn)
    if type(fn) ~= "function" then
        error("it() expects a function", 2)
    end
    if not current then
        error("it() called outside of a describe block", 2)
    end
    table.insert(current.tests, {
        name = name,
        fn = fn,
        suite = current
    })
end

function testkit.beforeEach(fn)
    if type(fn) ~= "function" then error("beforeEach() expects a function", 2) end
    table.insert(current.beforeEach, fn)
end

function testkit.afterEach(fn)
    if type(fn) ~= "function" then error("afterEach() expects a function", 2) end
    table.insert(current.afterEach, fn)
end

function testkit.beforeAll(fn)
    if type(fn) ~= "function" then error("beforeAll() expects a function", 2) end
    table.insert(current.beforeAll, fn)
end

function testkit.afterAll(fn)
    if type(fn) ~= "function" then error("afterAll() expects a function", 2) end
    table.insert(current.afterAll, fn)
end

-----------------------------------------------------------------------------
-- Module loader with its own script instance
-----------------------------------------------------------------------------

function testkit.loadModule(path)
    local mock = require("roblox_mock")
    -- Try Luau strip first (handles type annotations), fall back to loadfile
    local luauStrip = require("luau_strip")
    local chunk, err = luauStrip.loadFile(path)
    if not chunk then
        chunk, err = loadfile(path)
    end
    if not chunk then
        error("Failed to load module '" .. path .. "': " .. tostring(err), 2)
    end

    local moduleScript = mock.Instance.new("ModuleScript")
    moduleScript.Name = (path:match("([^/\\]+)%.lua$") or path)
    moduleScript.Source = "-- loaded from " .. path
    moduleScript.Parent = mock.game.ServerScriptService

    local env = getfenv(chunk)
    for k, v in pairs(mock) do
        if rawget(env, k) == nil then
            env[k] = v
        end
    end
    env.script = moduleScript
    setfenv(chunk, env)

    local ok, result = pcall(chunk)
    if not ok then
        error("Failed to run module '" .. path .. "': " .. tostring(result), 2)
    end
    return result, moduleScript
end

-----------------------------------------------------------------------------
-- Assertions
-----------------------------------------------------------------------------

local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b

    local countA = 0
    for k, v in pairs(a) do
        countA = countA + 1
        if not deepEqual(v, b[k], seen) then return false end
    end

    local countB = 0
    for _ in pairs(b) do countB = countB + 1 end
    return countA == countB
end

local function fail(self, msg)
    error((self._not and "Expected NOT: " or "Expected ") .. msg, 3)
end

local ExpectMethods = {}

function ExpectMethods:isNot()
    local wrapped = {
        actual = self.actual,
        _not = not self._not
    }
    setmetatable(wrapped, getmetatable(self))
    return wrapped
end
ExpectMethods.never = ExpectMethods.isNot
ExpectMethods.toNot = ExpectMethods.isNot

function ExpectMethods:equals(expected)
    local pass = self.actual == expected
    if self._not then pass = not pass end
    if not pass then
        fail(self, "values to be equal. Actual: " .. tostring(self.actual) .. ", Expected: " .. tostring(expected))
    end
    return self
end
ExpectMethods.toEqual = ExpectMethods.equals
ExpectMethods.toBe = ExpectMethods.equals

function ExpectMethods:deepEquals(expected)
    local pass = deepEqual(self.actual, expected)
    if self._not then pass = not pass end
    if not pass then
        fail(self, "tables to be deeply equal")
    end
    return self
end
ExpectMethods.toDeepEqual = ExpectMethods.deepEquals

function ExpectMethods:isNil()
    local pass = self.actual == nil
    if self._not then pass = not pass end
    if not pass then
        fail(self, "value to be nil. Actual: " .. tostring(self.actual))
    end
    return self
end
ExpectMethods.toBeNil = ExpectMethods.isNil

function ExpectMethods:isType(typeName)
    local pass = type(self.actual) == typeName
    if self._not then pass = not pass end
    if not pass then
        fail(self, "type '" .. tostring(typeName) .. "'. Got " .. type(self.actual))
    end
    return self
end
ExpectMethods.toBeA = ExpectMethods.isType
ExpectMethods.toBeType = ExpectMethods.isType

function ExpectMethods:throws(expectedMessage)
    if type(self.actual) ~= "function" then
        fail(self, "a function to check for throws. Got " .. type(self.actual))
    end
    local ok, err = pcall(self.actual)
    local threw = not ok
    if self._not then
        if threw then
            fail(self, "function to not throw, but it threw: " .. tostring(err))
        end
    else
        if not threw then
            fail(self, "function to throw, but it did not throw")
        end
        if expectedMessage then
            local msg = tostring(err)
            if not msg:find(tostring(expectedMessage), 1, true) then
                fail(self, "error message containing '" .. tostring(expectedMessage) .. "', but got '" .. msg .. "'")
            end
        end
    end
    return self
end
ExpectMethods.toThrow = ExpectMethods.throws

local ExpectMeta = { __index = ExpectMethods }

function testkit.expect(actual)
    return setmetatable({ actual = actual, _not = false }, ExpectMeta)
end

-----------------------------------------------------------------------------
-- Runner
-----------------------------------------------------------------------------

local function runTest(test, beforeStack, afterStack)
    local start = os.clock()
    local errors = {}
    local beforeFailed = false

    -- beforeEach hooks, outer -> inner
    for _, arr in ipairs(beforeStack) do
        for _, fn in ipairs(arr) do
            local ok, err = pcall(fn)
            if not ok then
                beforeFailed = true
                table.insert(errors, {
                    phase = "beforeEach",
                    message = tostring(err),
                    trace = debug.traceback("", 4)
                })
            end
        end
    end

    if not beforeFailed then
        local ok, err = pcall(test.fn)
        if not ok then
            table.insert(errors, {
                message = tostring(err),
                trace = debug.traceback("", 2)
            })
        end
    end

    -- afterEach hooks, inner -> outer
    for i = #afterStack, 1, -1 do
        local arr = afterStack[i]
        for _, fn in ipairs(arr) do
            local ok, err = pcall(fn)
            if not ok then
                table.insert(errors, {
                    phase = "afterEach",
                    message = tostring(err),
                    trace = debug.traceback("", 4)
                })
            end
        end
    end

    return {
        suitePath = test.suite.path,
        name = test.name,
        status = (#errors == 0 and "passed" or "failed"),
        errors = errors,
        duration = os.clock() - start
    }
end

local function runSuite(suite, beforeStack, afterStack, results)
    local beforeAllErrors = {}
    for _, fn in ipairs(suite.beforeAll) do
        local ok, err = pcall(fn)
        if not ok then
            table.insert(beforeAllErrors, {
                phase = "beforeAll",
                message = tostring(err),
                trace = debug.traceback("", 3)
            })
        end
    end
    local skipAll = #beforeAllErrors > 0

    local childBefore = {}
    for _, arr in ipairs(beforeStack) do table.insert(childBefore, arr) end
    table.insert(childBefore, suite.beforeEach)

    local childAfter = {}
    for _, arr in ipairs(afterStack) do table.insert(childAfter, arr) end
    table.insert(childAfter, suite.afterEach)

    -- Run tests registered directly on this suite
    for _, test in ipairs(suite.tests) do
        if skipAll then
            table.insert(results.tests, {
                suitePath = suite.path,
                name = test.name,
                status = "failed",
                errors = beforeAllErrors,
                duration = 0
            })
            results.failed = results.failed + 1
        else
            local r = runTest(test, childBefore, childAfter)
            table.insert(results.tests, r)
            if r.status == "passed" then
                results.passed = results.passed + 1
            else
                results.failed = results.failed + 1
            end
        end
    end

    -- Recurse into nested describes
    for _, child in ipairs(suite.children) do
        runSuite(child, childBefore, childAfter, results)
    end

    -- afterAll hooks
    for _, fn in ipairs(suite.afterAll) do
        local ok, err = pcall(fn)
        if not ok then
            table.insert(results.errors, {
                phase = "afterAll",
                message = tostring(err),
                trace = debug.traceback("", 3)
            })
        end
    end
end

function testkit.run()
    current = root
    local results = {
        passed = 0,
        failed = 0,
        skipped = 0,
        tests = {},
        errors = {},
        duration = 0
    }
    local start = os.clock()
    runSuite(root, {}, {}, results)
    results.duration = os.clock() - start
    return results
end

return testkit
