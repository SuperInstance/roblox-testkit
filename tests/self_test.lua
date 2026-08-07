-- tests/self_test.lua
-- Self-tests for roblox-testkit's mock infrastructure and test framework.
--
-- Run: lua5.1 src/runner.lua tests/self_test.lua

local testkit = require("testkit")
local robloxMock = require("roblox_mock")
local expect = testkit.expect

describe("Event mock", function()
    it("fires connected handlers", function()
        local event = robloxMock.Event.new("TestEvent")
        local fired = false
        local args = nil

        event:Connect(function(a, b)
            fired = true
            args = {a, b}
        end)

        event:Fire(42, "hello")

        expect(fired):toBe(true)
        expect(args[1]):toBe(42)
        expect(args[2]):toBe("hello")
    end)

    it("supports multiple connections", function()
        local event = robloxMock.Event.new("MultiEvent")
        local count = 0

        event:Connect(function() count = count + 1 end)
        event:Connect(function() count = count + 10 end)

        event:Fire()

        expect(count):toBe(11)
    end)

    it("allows disconnecting handlers", function()
        local event = robloxMock.Event.new("DisconnectEvent")
        local count = 0

        local conn = event:Connect(function() count = count + 1 end)
        event:Fire()
        expect(count):toBe(1)

        conn:Disconnect()
        event:Fire()
        expect(count):toBe(1)
    end)

    it("returns last fired args from Wait", function()
        local event = robloxMock.Event.new("WaitEvent")

        event:Fire("first", "second")
        local a, b = event:Wait()

        expect(a):toBe("first")
        expect(b):toBe("second")
    end)
end)

describe("Instance mock", function()
    it("creates instances with correct ClassName", function()
        local part = Instance.new("Part")
        expect(part.ClassName):toBe("Part")
    end)

    it("creates instances with default Name = ClassName", function()
        local part = Instance.new("Part")
        expect(part.Name):toBe("Part")
    end)

    it("creates instances with custom Name", function()
        local part = Instance.new("Part", "MyPart")
        expect(part.Name):toBe("MyPart")
    end)

    it("sets and gets Parent correctly", function()
        local parent = Instance.new("Folder", "Parent")
        local child = Instance.new("Part", "Child")

        child.Parent = parent
        expect(child.Parent):toBe(parent)
    end)

    it("adds child to parent's children when Parent is set", function()
        local parent = Instance.new("Folder", "Parent")
        local child = Instance.new("Part", "Child")

        child.Parent = parent
        local found = false
        for _, c in ipairs(parent:GetChildren()) do
            if c == child then found = true end
        end
        expect(found):toBe(true)
    end)

    it("removes child from old parent when reparented", function()
        local parentA = Instance.new("Folder", "A")
        local parentB = Instance.new("Folder", "B")
        local child = Instance.new("Part", "Child")

        child.Parent = parentA
        child.Parent = parentB

        -- child should be in B but not A
        local inA = false
        for _, c in ipairs(parentA:GetChildren()) do
            if c == child then inA = true end
        end
        expect(inA):toBe(false)

        local inB = false
        for _, c in ipairs(parentB:GetChildren()) do
            if c == child then inB = true end
        end
        expect(inB):toBe(true)
    end)

    it("FindFirstChild returns named child", function()
        local parent = Instance.new("Folder", "Parent")
        local child = Instance.new("Part", "MyChild")
        child.Parent = parent

        local found = parent:FindFirstChild("MyChild")
        expect(found):toBe(child)
    end)

    it("FindFirstChild returns nil for missing child", function()
        local parent = Instance.new("Folder", "Parent")
        local found = parent:FindFirstChild("Nonexistent")
        expect(found):toBe(nil)
    end)

    it("GetChildren returns array of children", function()
        local parent = Instance.new("Folder", "Parent")
        local child1 = Instance.new("Part", "C1")
        local child2 = Instance.new("Part", "C2")
        child1.Parent = parent
        child2.Parent = parent

        local children = parent:GetChildren()
        expect(#children):toBe(2)
    end)

    it("GetDescendants returns nested children", function()
        local root = Instance.new("Folder", "Root")
        local child = Instance.new("Folder", "Child")
        local grandchild = Instance.new("Part", "Grandchild")
        child.Parent = root
        grandchild.Parent = child

        local descendants = root:GetDescendants()
        expect(#descendants):toBe(2)
    end)
end)

describe("expect framework", function()
    it("toBe passes for equal values", function()
        expect(42):toBe(42)
        expect("hello"):toBe("hello")
    end)

    it("toBe passes for nil", function()
        expect(nil):toBe(nil)
    end)

    it("toBe passes for tables by reference", function()
        local t = {}
        expect(t):toBe(t)
    end)

    it("toDeepEqual passes for deeply equal tables", function()
        expect({1, 2, 3}):toDeepEqual({1, 2, 3})
    end)
end)
