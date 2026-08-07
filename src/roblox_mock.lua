-- src/roblox_mock.lua
-- Minimal Roblox API mock for running Roblox Lua modules outside of Studio (Lua 5.1).

local RobloxMock = {}

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------

local function isArray(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

-----------------------------------------------------------------------------
-- Event mock
-----------------------------------------------------------------------------

local Event = {}
Event.__index = Event

function Event.new(name)
    return setmetatable({
        _name = name or "Event",
        _connections = {},
        _lastArgs = {}
    }, Event)
end

function Event:Connect(fn)
    if type(fn) ~= "function" then
        error("Event:Connect expects a function")
    end
    table.insert(self._connections, fn)
    return {
        Disconnect = function()
            for i, c in ipairs(self._connections) do
                if c == fn then
                    table.remove(self._connections, i)
                    return
                end
            end
        end
    }
end

function Event:Fire(...)
    self._lastArgs = {...}
    for _, fn in ipairs(self._connections) do
        fn(unpack(self._lastArgs))
    end
end

function Event:Wait()
    -- Headless tests cannot block; return the last fired args if any.
    if #self._lastArgs > 0 then
        return unpack(self._lastArgs)
    end
    return nil
end

RobloxMock.Event = Event

-----------------------------------------------------------------------------
-- Instance mock
-----------------------------------------------------------------------------

local Instance = {}

Instance.__index = function(t, k)
    if k == "Parent" then
        return rawget(t, "_parent")
    end
    -- Check instance's own fields first (e.g., workspace.Terrain)
    local own = rawget(t, k)
    if own ~= nil then return own end
    return Instance[k]
end

Instance.__newindex = function(t, k, v)
    if k == "Parent" then
        local old = rawget(t, "_parent")
        if old == v then return end
        if old then
            local oc = rawget(old, "_children")
            for i, c in ipairs(oc) do
                if c == t then
                    table.remove(oc, i)
                    break
                end
            end
        end
        rawset(t, "_parent", v)
        if v then
            local nc = rawget(v, "_children")
            table.insert(nc, t)
        end
    else
        rawset(t, k, v)
    end
end

function Instance.new(className, name)
    local self = setmetatable({}, Instance)
    self.ClassName = className or "Instance"
    self.Name = name or self.ClassName
    self._parent = nil
    self._children = {}
    self._attributes = {}
    self._destroyed = false
    self.Archivable = true
    return self
end

RobloxMock.Instance = { new = Instance.new }

local classHierarchy = {
    Instance = {},
    DataModel = {"Instance"},
    WorldRoot = {"Instance"},
    Workspace = {"WorldRoot", "Instance"},
    Model = {"PVInstance", "Instance"},
    PVInstance = {"Instance"},
    BasePart = {"PVInstance", "Instance"},
    Part = {"BasePart", "PVInstance", "Instance"},
    MeshPart = {"BasePart", "PVInstance", "Instance"},
    LuaSourceContainer = {"Instance"},
    ModuleScript = {"LuaSourceContainer", "Instance"},
    Script = {"LuaSourceContainer", "Instance"},
    LocalScript = {"LuaSourceContainer", "Instance"},
    Players = {"Instance"},
    Player = {"Instance"},
    ReplicatedStorage = {"Instance"},
    ServerScriptService = {"Instance"},
    ServerStorage = {"Instance"},
    Lighting = {"Instance"},
    RunService = {"Instance"},
    TweenService = {"Instance"},
    Debris = {"Instance"},
    CollectionService = {"Instance"},
    TextService = {"Instance"},
    HttpService = {"Instance"},
    Folder = {"Instance"},
    Sound = {"Instance"},
    Tween = {"Instance"},
}

local function isA(instance, className)
    if not instance or type(instance) ~= "table" then return false end
    local own = rawget(instance, "ClassName")
    if own == className then return true end
    local chain = classHierarchy[own]
    if chain then
        for _, c in ipairs(chain) do
            if c == className then return true end
        end
    end
    return false
end

function Instance:IsA(className)
    return isA(self, className)
end

function Instance:FindFirstChild(name, recursive)
    if self._destroyed then return nil end
    for _, child in ipairs(self._children) do
        if child.Name == name then return child end
    end
    if recursive then
        for _, child in ipairs(self._children) do
            local found = child:FindFirstChild(name, true)
            if found then return found end
        end
    end
    return nil
end

function Instance:FindFirstChildOfClass(className)
    for _, child in ipairs(self._children) do
        if child.ClassName == className then return child end
    end
    return nil
end

function Instance:FindFirstChildWhichIsA(className)
    for _, child in ipairs(self._children) do
        if child:IsA(className) then return child end
    end
    return nil
end

function Instance:GetChildren()
    local copy = {}
    for i, c in ipairs(self._children) do copy[i] = c end
    return copy
end

local function collectDescendants(instance, out)
    for _, child in ipairs(instance._children) do
        table.insert(out, child)
        collectDescendants(child, out)
    end
end

function Instance:GetDescendants()
    local out = {}
    collectDescendants(self, out)
    return out
end

function Instance:Clone()
    if not self.Archivable then return nil end
    local copy = Instance.new(self.ClassName, self.Name)
    for k, v in pairs(self) do
        if k ~= "_parent" and k ~= "_children" and k ~= "_destroyed"
           and k ~= "ClassName" and k ~= "Name" and k ~= "Parent" then
            copy[k] = v
        end
    end
    for _, child in ipairs(self._children) do
        local cc = child:Clone()
        cc.Parent = copy
    end
    return copy
end

function Instance:Destroy()
    self._destroyed = true
    self.Parent = nil
    local kids = {unpack(self._children)}
    for _, child in ipairs(kids) do
        child:Destroy()
    end
    self._children = {}
end

function Instance:ClearAllChildren()
    local kids = {unpack(self._children)}
    for _, child in ipairs(kids) do
        child:Destroy()
    end
    self._children = {}
end

function Instance:WaitForChild(name, timeout)
    return self:FindFirstChild(name)
end

function Instance:GetAttribute(name)
    return self._attributes[name]
end

function Instance:SetAttribute(name, value)
    self._attributes[name] = value
end

function Instance:GetAttributes()
    local copy = {}
    for k, v in pairs(self._attributes) do copy[k] = v end
    return copy
end

function Instance:IsDescendantOf(ancestor)
    local p = self._parent
    while p do
        if p == ancestor then return true end
        p = rawget(p, "_parent")
    end
    return false
end

function Instance:GetFullName()
    local parts = {}
    local cur = self
    while cur do
        table.insert(parts, 1, cur.Name)
        cur = rawget(cur, "_parent")
    end
    return table.concat(parts, ".")
end

-----------------------------------------------------------------------------
-- Services
-----------------------------------------------------------------------------

local function newService(className, name)
    local s = Instance.new(className, name)
    s._isService = true
    return s
end

local DataModel = {}

function DataModel:GetService(name)
    if self._services[name] then return self._services[name] end

    local svc
    if name == "Players" then
        svc = newService("Players", "Players")
        svc.LocalPlayer = nil
        svc._players = {}
        svc.PlayerAdded = Event.new("PlayerAdded")
        svc.PlayerRemoving = Event.new("PlayerRemoving")

        function svc:GetPlayers()
            local copy = {}
            for i, p in ipairs(svc._players) do copy[i] = p end
            return copy
        end

        function svc:GetPlayerByUserId(userId)
            for _, p in ipairs(svc._players) do
                if p.UserId == userId then return p end
            end
            return nil
        end

        function svc:CreatePlayer(playerName, userId)
            local p = Instance.new("Player", playerName)
            p.UserId = userId or 0
            p.Character = nil
            table.insert(svc._players, p)
            svc.PlayerAdded:Fire(p)
            return p
        end

        function svc:SetLocalPlayer(player)
            svc.LocalPlayer = player
        end

    elseif name == "ReplicatedStorage" then
        svc = newService("ReplicatedStorage", "ReplicatedStorage")

    elseif name == "ServerScriptService" then
        svc = newService("ServerScriptService", "ServerScriptService")

    elseif name == "ServerStorage" then
        svc = newService("ServerStorage", "ServerStorage")

    elseif name == "Lighting" then
        svc = newService("Lighting", "Lighting")
        svc.Ambient = {r = 127, g = 127, b = 127}
        svc.Brightness = 1
        svc.ClockTime = 12
        svc.FogColor = {r = 191, g = 191, b = 191}
        svc.FogEnd = 1000
        svc.FogStart = 0

    elseif name == "RunService" then
        svc = newService("RunService", "RunService")
        svc._running = false
        svc._studio = true
        svc.Heartbeat = Event.new("Heartbeat")
        svc.RenderStepped = Event.new("RenderStepped")
        svc.Stepped = Event.new("Stepped")
        svc._renderBindings = {}

        function svc:IsRunning() return svc._running end
        function svc:IsStudio() return svc._studio end
        function svc:IsServer() return true end
        function svc:IsClient() return false end

        function svc:BindToRenderStep(name, priority, fn)
            svc._renderBindings[name] = {priority = priority, fn = fn}
        end

        function svc:UnbindFromRenderStep(name)
            svc._renderBindings[name] = nil
        end

    elseif name == "TweenService" then
        svc = newService("TweenService", "TweenService")

        function svc:Create(instance, tweenInfo, propertyTable)
            local tween = Instance.new("Tween", "Tween")
            tween.Instance = instance
            tween.TweenInfo = tweenInfo or {}
            tween.Properties = propertyTable or {}
            tween.PlaybackState = "Begin"
            tween.Completed = Event.new("Completed")

            function tween:Play()
                self.PlaybackState = "Playing"
                if self.Instance and self.Properties then
                    for k, v in pairs(self.Properties) do
                        self.Instance[k] = v
                    end
                end
                self.PlaybackState = "Completed"
                self.Completed:Fire("Completed")
            end

            function tween:Pause()
                self.PlaybackState = "Paused"
            end

            function tween:Cancel()
                self.PlaybackState = "Cancelled"
            end

            function tween:Destroy()
                self:Cancel()
                Instance.Destroy(self)
            end

            return tween
        end

    elseif name == "Debris" then
        svc = newService("Debris", "Debris")

        function svc:AddItem(item, lifetime)
            if item and type(item) == "table" and item.Destroy then
                item:Destroy()
            end
        end

        function svc:SetMaxItems(maxItems) end

    elseif name == "CollectionService" then
        svc = newService("CollectionService", "CollectionService")
        svc._tags = {}

        function svc:AddTag(instance, tag)
            if not svc._tags[tag] then svc._tags[tag] = {} end
            svc._tags[tag][instance] = true
        end

        function svc:RemoveTag(instance, tag)
            if svc._tags[tag] then svc._tags[tag][instance] = nil end
        end

        function svc:HasTag(instance, tag)
            return svc._tags[tag] and svc._tags[tag][instance] == true
        end

        function svc:GetTags(instance)
            local tags = {}
            for tag, set in pairs(svc._tags) do
                if set[instance] then table.insert(tags, tag) end
            end
            return tags
        end

        function svc:GetTagged(tag)
            local list = {}
            if svc._tags[tag] then
                for inst, _ in pairs(svc._tags[tag]) do
                    table.insert(list, inst)
                end
            end
            return list
        end

    elseif name == "TextService" then
        svc = newService("TextService", "TextService")

        function svc:GetTextSize(text, fontSize, font, frameSize)
            text = tostring(text or "")
            fontSize = fontSize or 14
            frameSize = frameSize or {X = 100, Y = 100}
            local width = math.min(#text * fontSize * 0.5, frameSize.X)
            local lines = math.max(1, math.ceil((#text * fontSize * 0.5) / frameSize.X))
            return {X = math.floor(width), Y = math.floor(lines * fontSize)}
        end

    elseif name == "HttpService" then
        svc = newService("HttpService", "HttpService")

        local escapes = {
            ["\\"] = "\\\\",
            ['"'] = '\\"',
            ["\n"] = "\\n",
            ["\t"] = "\\t",
            ["\r"] = "\\r"
        }

        local function escapeString(s)
            return s:gsub("[\\\n\t\r\"]", function(c) return escapes[c] end)
        end

        local function jsonEncode(value)
            local t = type(value)
            if t == "nil" then return "null"
            elseif t == "boolean" then return tostring(value)
            elseif t == "number" then return tostring(value)
            elseif t == "string" then return '"' .. escapeString(value) .. '"'
            elseif t == "table" then
                if isArray(value) then
                    local parts = {}
                    for i = 1, #value do parts[i] = jsonEncode(value[i]) end
                    return "[" .. table.concat(parts, ",") .. "]"
                else
                    local parts = {}
                    for k, v in pairs(value) do
                        table.insert(parts, jsonEncode(tostring(k)) .. ":" .. jsonEncode(v))
                    end
                    return "{" .. table.concat(parts, ",") .. "}"
                end
            else
                error("Cannot encode type " .. t)
            end
        end

        svc.JSONEncode = function(self, value) return jsonEncode(value) end

        local function jsonDecode(text)
            local pos = 1
            local function peek() return text:sub(pos, pos) end
            local function advance() pos = pos + 1 end
            local function skipSpace()
                while pos <= #text and peek():match("%s") do advance() end
            end

            local parseValue

            local function parseString()
                advance()
                local out = {}
                while pos <= #text do
                    local c = peek()
                    if c == '"' then
                        advance()
                        return table.concat(out)
                    elseif c == "\\" then
                        advance()
                        local e = peek(); advance()
                        if e == "n" then table.insert(out, "\n")
                        elseif e == "t" then table.insert(out, "\t")
                        elseif e == "r" then table.insert(out, "\r")
                        elseif e == "\\" then table.insert(out, "\\")
                        elseif e == '"' then table.insert(out, '"')
                        elseif e == "/" then table.insert(out, "/")
                        elseif e == "b" then table.insert(out, "\b")
                        elseif e == "f" then table.insert(out, "\f")
                        elseif e == "u" then
                            local hex = text:sub(pos, pos + 3)
                            pos = pos + 4
                            local code = tonumber(hex, 16)
                            table.insert(out, string.char(code))
                        else
                            table.insert(out, e)
                        end
                    else
                        table.insert(out, c)
                        advance()
                    end
                end
                error("Unterminated string")
            end

            local function parseNumber()
                local start = pos
                if peek() == "-" then advance() end
                while pos <= #text and peek():match("%d") do advance() end
                if peek() == "." then
                    advance()
                    while pos <= #text and peek():match("%d") do advance() end
                end
                if peek():lower() == "e" then
                    advance()
                    if peek() == "+" or peek() == "-" then advance() end
                    while pos <= #text and peek():match("%d") do advance() end
                end
                return tonumber(text:sub(start, pos - 1))
            end

            parseValue = function()
                skipSpace()
                local c = peek()
                if c == "{" then
                    advance()
                    local obj = {}
                    skipSpace()
                    while peek() ~= "}" do
                        skipSpace()
                        local key = parseValue()
                        skipSpace()
                        if peek() ~= ":" then error("Expected ':' in object") end
                        advance()
                        local val = parseValue()
                        obj[key] = val
                        skipSpace()
                        if peek() == "," then advance() else break end
                    end
                    if peek() ~= "}" then error("Expected '}' in object") end
                    advance()
                    return obj
                elseif c == "[" then
                    advance()
                    local arr = {}
                    skipSpace()
                    while peek() ~= "]" do
                        table.insert(arr, parseValue())
                        skipSpace()
                        if peek() == "," then advance() else break end
                    end
                    if peek() ~= "]" then error("Expected ']' in array") end
                    advance()
                    return arr
                elseif c == '"' then
                    return parseString()
                elseif text:sub(pos, pos + 3) == "true" then
                    pos = pos + 4; return true
                elseif text:sub(pos, pos + 4) == "false" then
                    pos = pos + 5; return false
                elseif text:sub(pos, pos + 3) == "null" then
                    pos = pos + 4; return nil
                else
                    return parseNumber()
                end
            end

            local result = parseValue()
            skipSpace()
            if pos <= #text then error("Unexpected trailing characters in JSON") end
            return result
        end

        svc.JSONDecode = function(self, text) return jsonDecode(text) end

    elseif name == "Workspace" then
        svc = newService("Workspace", "Workspace")
        svc.Gravity = 196.2
        svc.StreamingEnabled = false
        -- Terrain child (needed by modules that reference workspace.Terrain)
        local terrain = Instance.new("Terrain")
        terrain.Parent = svc
        terrain.FillBlock = function(self, cframe, size, material) end
        svc.Terrain = terrain

    else
        -- Unknown service: create a generic service instance.
        svc = newService(name, name)
    end

    self._services[name] = svc
    svc.Parent = self
    return svc
end

function DataModel:IsLoaded() return true end

-----------------------------------------------------------------------------
-- Math Types (Color3, Vector3, CFrame, NumberRange, NumberSequence)
-----------------------------------------------------------------------------

-- Color3
local Color3 = {}
Color3.__index = Color3

function Color3.new(r, g, b)
    return setmetatable({
        R = r or 0,
        G = g or 0,
        B = b or 0,
        _robloxType = "Color3"
    }, Color3)
end

function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3.fromHSV(h, s, v)
    return Color3.new(h, s, v)
end

function Color3:ToRGB()
    return math.floor(self.R * 255 + 0.5), math.floor(self.G * 255 + 0.5), math.floor(self.B * 255 + 0.5)
end

-- Vector3
local Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x, y, z)
    return setmetatable({
        X = x or 0,
        Y = y or 0,
        Z = z or 0,
        _robloxType = "Vector3"
    }, Vector3)
end

-- CFrame (simplified — only position)
local CFrame = {}
CFrame.__index = CFrame

function CFrame.new(pos)
    return setmetatable({
        Position = pos or Vector3.new(),
        X = (pos and pos.X) or 0,
        Y = (pos and pos.Y) or 0,
        Z = (pos and pos.Z) or 0,
        _robloxType = "CFrame"
    }, { __index = CFrame, __mul = function(a, b) return a end, __sub = function(a, b) return a end })
end

function CFrame.Angles(x, y, z)
    return setmetatable({
        Position = Vector3.new(),
        X = 0, Y = 0, Z = 0,
        _rotX = x, _rotY = y, _rotZ = z,
        _robloxType = "CFrame"
    }, { __index = CFrame, __mul = function(a, b) return a end, __sub = function(a, b) return a end })
end

-- NumberRange
local NumberRange = {}
NumberRange.__index = NumberRange

function NumberRange.new(min, max)
    return setmetatable({
        Min = min or 0,
        Max = max or min or 0,
        _robloxType = "NumberRange"
    }, NumberRange)
end

-- NumberSequence
local NumberSequence = {}
NumberSequence.__index = NumberSequence

function NumberSequence.new(a, b)
    if type(a) == "table" and a.Keypoints then
        return setmetatable({ Keypoints = a.Keypoints, _robloxType = "NumberSequence" }, NumberSequence)
    end
    return setmetatable({
        Keypoints = {
            { Time = 0, Value = a or 0 },
            { Time = 1, Value = b or a or 0 }
        },
        _robloxType = "NumberSequence"
    }, NumberSequence)
end

-- ColorSequence
local ColorSequence = {}
ColorSequence.__index = ColorSequence

function ColorSequence.new(a, b)
    return setmetatable({
        Keypoints = {
            { Time = 0, Value = a },
            { Time = 1, Value = b or a }
        },
        _robloxType = "ColorSequence"
    }, ColorSequence)
end

-----------------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------------

function RobloxMock.create()
    local game = Instance.new("DataModel", "Game")
    game._services = {}
    game.PlaceId = 0
    game.GameId = 0
    game.JobId = "test-job-id"
    game.PlayersMax = 10
    game.GetService = DataModel.GetService
    game.IsLoaded = DataModel.IsLoaded

    local mock = {}
    mock.game = game
    mock.workspace = game:GetService("Workspace")
    mock.Players = game:GetService("Players")
    mock.ReplicatedStorage = game:GetService("ReplicatedStorage")
    mock.ServerScriptService = game:GetService("ServerScriptService")
    mock.ServerStorage = game:GetService("ServerStorage")
    mock.Lighting = game:GetService("Lighting")
    mock.RunService = game:GetService("RunService")
    mock.TweenService = game:GetService("TweenService")
    mock.Debris = game:GetService("Debris")
    mock.CollectionService = game:GetService("CollectionService")
    mock.TextService = game:GetService("TextService")
    mock.HttpService = game:GetService("HttpService")
    mock.Instance = RobloxMock.Instance
    mock.Event = Event
    mock.Color3 = Color3
    mock.Vector3 = Vector3
    mock.CFrame = CFrame
    mock.NumberRange = NumberRange
    mock.NumberSequence = NumberSequence
    mock.ColorSequence = ColorSequence
    mock.TweenInfo = {
        new = function(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)
            return {
                Time = time or 1,
                EasingStyle = easingStyle or "Linear",
                EasingDirection = easingDirection or "Out",
                RepeatCount = repeatCount or 0,
                Reverses = reverses or false,
                DelayTime = delayTime or 0
            }
        end
    }

    mock.script = Instance.new("ModuleScript", "script")
    mock.script.Parent = mock.ServerScriptService

    return mock
end

function RobloxMock.install(env)
    env = env or _G
    local mock = RobloxMock.create()
    for k, v in pairs(mock) do
        env[k] = v
    end
    return mock
end

return RobloxMock
