-- src/testez_compat.lua
-- TestEZ API compatibility layer for roblox-testkit.
--
-- Translates TestEZ-style chained expectations to roblox-testkit's
-- native assertion API. Key insight: TestEZ uses dot-chaining
-- (expect(x).to.equal(y)) which does NOT pass self, so all bridge
-- functions must be closures that capture the testkit expectation.

local testkit = require("testkit")

local function makeToBridge(tk)
    return {
        equal = function(expected) return tk:equals(expected) end,
        eql = function(expected) return tk:equals(expected) end,
        toEqual = function(expected) return tk:equals(expected) end,
        deepEqual = function(expected) return tk:deepEquals(expected) end,
        be = {
            a = function(typeName) return tk:isType(typeName) end,
            an = function(typeName) return tk:isType(typeName) end,
            ok = function()
                if tk.actual == nil then error("Expected value to be truthy, got nil", 2) end
                return tk
            end,
            truthy = function()
                if not tk.actual then error("Expected value to be truthy", 2) end
                return tk
            end,
            falsy = function()
                if tk.actual then error("Expected value to be falsy, got: " .. tostring(tk.actual), 2) end
                return tk
            end,
            at = {
                least = function(n)
                    if not (tk.actual >= n) then error(("Expected %s >= %s"):format(tostring(tk.actual), tostring(n)), 2) end
                    return tk
                end,
                most = function(n)
                    if not (tk.actual <= n) then error(("Expected %s <= %s"):format(tostring(tk.actual), tostring(n)), 2) end
                    return tk
                end,
            },
        },
        throw = function(msg) return tk:throws(msg) end,
        roughly = {
            equal = function(expected, epsilon)
                local diff = math.abs(tk.actual - expected)
                if diff > epsilon then error(("Expected %s ≈ %s (±%s)"):format(tostring(tk.actual), tostring(expected), tostring(epsilon)), 2) end
                return tk
            end,
        },
    }
end

local function testezExpect(actual)
    local tk = testkit.expect(actual)
    local neverTk = tk:never()
    return {
        actual = actual,
        _tk = tk,
        to = makeToBridge(tk),
        never = { to = makeToBridge(neverTk) },
    }
end

return testezExpect
