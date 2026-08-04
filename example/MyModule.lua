local MyModule = {}

function MyModule.add(a, b)
    return a + b
end

function MyModule.getStorage()
    return game:GetService("ReplicatedStorage")
end

function MyModule.createPart(name)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = {X = 4, Y = 1, Z = 2}
    part.Parent = workspace
    return part
end

return MyModule
