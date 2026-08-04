local testkit = require("testkit")

-- Load the module under test with its own mocked script instance.
local MyModule = testkit.loadModule("example/MyModule.lua")

testkit.describe("MyModule", function()
    testkit.it("adds two numbers", function()
        testkit.expect(MyModule.add(2, 3)):equals(5)
    end)

    testkit.it("returns ReplicatedStorage", function()
        local storage = MyModule.getStorage()
        testkit.expect(storage):isNot():isNil()
        testkit.expect(storage.Name):equals("ReplicatedStorage")
        testkit.expect(storage:IsA("Instance")):equals(true)
    end)

    testkit.it("creates a Part in Workspace", function()
        local part = MyModule.createPart("TestBlock")
        testkit.expect(part.ClassName):equals("Part")
        testkit.expect(part.Name):equals("TestBlock")
        testkit.expect(part.Parent):isNot():isNil()
        testkit.expect(part.Parent.Name):equals("Workspace")
        testkit.expect(part:IsA("BasePart")):equals(true)
    end)

    testkit.describe("error handling", function()
        testkit.it("detects a function that throws", function()
            testkit.expect(function()
                error("boom")
            end):throws("boom")
        end)
    end)
end)
