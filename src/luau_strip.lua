-- src/luau_strip.lua
-- Strips Luau type annotations from source code so it can run in plain Lua 5.1.
-- v4: Smart param splitting with brace/paren depth tracking

local M = {}

-- Split parameters by comma, respecting brace and paren depth
local function splitParams(s)
    local parts = {}
    local depth = 0
    local current = ""
    for ch in s:gmatch(".") do
        if ch == "{" or ch == "(" then
            depth = depth + 1
            current = current .. ch
        elseif ch == "}" or ch == ")" then
            depth = depth - 1
            current = current .. ch
        elseif ch == "," and depth == 0 then
            table.insert(parts, current)
            current = ""
        else
            current = current .. ch
        end
    end
    if current:match("%S") then
        table.insert(parts, current)
    end
    return parts
end

local function stripFunctionLine(line)
    -- Handle return type: ): ReturnType
    local parenEnd = nil
    local depth = 0
    for i = 1, #line do
        local ch = line:sub(i, i)
        if ch == "(" then depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
                parenEnd = i
                break
            end
        end
    end
    
    if parenEnd then
        local afterParen = line:sub(parenEnd + 1):gsub("^%s*", "")
        if afterParen:sub(1, 1) == ":" then
            local beforeParen = line:sub(1, parenEnd)
            local trailingKeyword = afterParen:match(":%s*.-%s+(do|then)$")
            if trailingKeyword then
                line = beforeParen .. " " .. trailingKeyword
            else
                line = beforeParen
            end
        end
    end
    
    -- Extract params between outermost parens
    local firstParen = line:find("%(")
    if not firstParen then return line end
    
    -- Re-find the matching close paren
    depth = 0
    local closeParen = nil
    for i = firstParen, #line do
        local ch = line:sub(i, i)
        if ch == "(" then depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
                closeParen = i
                break
            end
        end
    end
    
    if not closeParen then return line end
    
    local prefix = line:sub(1, firstParen)
    local params = line:sub(firstParen + 1, closeParen - 1)
    local suffix = line:sub(closeParen)
    
    -- Smart-split params and strip types
    local parts = splitParams(params)
    local stripped = {}
    for _, param in ipairs(parts) do
        param = param:match("^%s*(.-)%s*$")
        -- Extract the name (first identifier before any colon)
        local name = param:match("^(%w+)%s*:")
        if name then
            table.insert(stripped, name)
        elseif param:match("^%w+$") then
            -- Already just a name
            table.insert(stripped, param)
        elseif param:match("%S") then
            -- Complex expression, keep as-is
            table.insert(stripped, param)
        end
    end
    
    return prefix .. table.concat(stripped, ", ") .. suffix
end

local function fixCompoundAssignment(line)
    local indent = line:match("^(%s*)")
    local lhs, rhs = line:match("^%s*(%S+)%s+%+=%s+(.+)$")
    if lhs then return indent .. lhs .. " = " .. lhs .. " + " .. rhs end
    lhs, rhs = line:match("^%s*(%S+)%s+%-%=%s+(.+)$")
    if lhs then return indent .. lhs .. " = " .. lhs .. " - " .. rhs end
    lhs, rhs = line:match("^%s*(%S+)%s+%*=%s+(.+)$")
    if lhs then return indent .. lhs .. " = " .. lhs .. " * " .. rhs end
    lhs, rhs = line:match("^%s*(%S+)%s+%.%.=%s+(.+)$")
    if lhs then return indent .. lhs .. " = " .. lhs .. " .. " .. rhs end
    return line
end

local function fixContinue(line)
    if line:match("^%s*continue%s*$") then
        return line:match("^(%s*)") .. "-- continue (stripped)"
    end
    return line
end

local function fixIfExpression(line)
    local prefix, cond, a, b = line:match("^(.*=%s*)if%s+(.+)%s+then%s+(.-)%s+else%s+(.+)$")
    if prefix and cond and a and b then
        return prefix .. "(" .. cond .. " and " .. a .. " or " .. b .. ")"
    end
    return line
end

local function stripVariableType(line)
    local name, rest = line:match("^%s*local%s+(%w+)%s*:%s*.-%s*=%s*(.+)$")
    if name then
        return line:match("^(%s*)") .. "local " .. name .. " = " .. rest
    end
    local typeName = line:match("^%s*local%s+(%w+)%s*:%s*[%w%.%[%]_,{}%s%?]+$")
    if typeName then
        return line:match("^(%s*)") .. "local " .. typeName .. " = nil"
    end
    return line
end

local function shouldSkip(line)
    if line:match("^%s*export%s+type%s") then return true end
    if line:match("^%s*type%s+%w+%s*=") and not line:match("^%s*local%s") then return true end
    return false
end

local function isFunctionSignatureStart(line)
    if line:match("^%s*function%s") or line:match("^%s*local%s+function%s") then
        local open = 0
        for _ in line:gmatch("%(") do open = open + 1 end
        for _ in line:gmatch("%)") do open = open - 1 end
        return open > 0
    end
    return false
end

local function collectFunctionSignature(allLines, startIdx)
    local collected = allLines[startIdx]
    local i = startIdx + 1
    local open = 0
    for _ in collected:gmatch("%(") do open = open + 1 end
    for _ in collected:gmatch("%)") do open = open - 1 end
    while i <= #allLines and open > 0 do
        local line = allLines[i]
        for _ in line:gmatch("%(") do open = open + 1 end
        for _ in line:gmatch("%)") do open = open - 1 end
        collected = collected .. " " .. line:gsub("^%s+", ""):gsub("%s+$", "")
        i = i + 1
    end
    -- Skip return type lines (lines starting with `:` after closing paren)
    while i <= #allLines do
        local line = allLines[i]:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" then
            i = i + 1
        elseif line:sub(1, 1) == ":" then
            i = i + 1
        else
            break
        end
    end
    return collected, i - startIdx - 1
end

function M.strip(source)
    local allLines = {}
    for line in source:gmatch("[^\n]*") do
        table.insert(allLines, line)
    end
    local lines = {}
    local inTypeBlock = false
    local braceDepth = 0
    local inMultilineString = false
    local i = 1
    while i <= #allLines do
        local line = allLines[i]
        if line:match("%[%[") and not line:match("%]%]") then
            inMultilineString = true
            table.insert(lines, line)
            i = i + 1
        elseif inMultilineString then
            table.insert(lines, line)
            if line:match("%]%]") then inMultilineString = false end
            i = i + 1
        elseif inTypeBlock then
            for _ in line:gmatch("{") do braceDepth = braceDepth + 1 end
            for _ in line:gmatch("}") do braceDepth = braceDepth - 1 end
            if braceDepth <= 0 then inTypeBlock = false end
            i = i + 1
        elseif shouldSkip(line) then
            if line:match("=%s*$") and not line:match("=%s*[^%s]") then
                inTypeBlock = true
                braceDepth = 0
            elseif line:match("{") then
                for _ in line:gmatch("{") do braceDepth = braceDepth + 1 end
                for _ in line:gmatch("}") do braceDepth = braceDepth - 1 end
                if braceDepth > 0 then inTypeBlock = true end
            end
            i = i + 1
        elseif isFunctionSignatureStart(line) then
            local joined, consumed = collectFunctionSignature(allLines, i)
            joined = stripFunctionLine(joined)
            table.insert(lines, joined)
            i = i + consumed + 1
        else
            if line:match("^%s*function") or line:match("^%s*local%s+function") then
                line = stripFunctionLine(line)
            end
            line = stripVariableType(line)
            line = fixIfExpression(line)
            line = fixCompoundAssignment(line)
            line = fixContinue(line)
            table.insert(lines, line)
            i = i + 1
        end
    end
    local result = table.concat(lines, "\n")
    local polyfill = [[
if not table.clone then
    table.clone = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
end
if not table.clear then
    table.clear = function(t) for k in pairs(t) do t[k] = nil end end
end
if not math.clamp then
    math.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
end
if not math.sign then
    math.sign = function(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
end
Vector3 = Vector3 or setmetatable({}, {
    __call = function(_, x, y, z)
        return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, x = x or 0, y = y or 0, z = z or 0}, {
            __sub = function(a, b) return Vector3(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end,
            __add = function(a, b) return Vector3(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end,
            __tostring = function(a) return string.format("Vector3(%f, %f, %f)", a.X, a.Y, a.Z) end,
        })
    end
})
Vector3.new = Vector3
CFrame = CFrame or setmetatable({}, {
    __call = function(_, x, y, z) return setmetatable({Position = Vector3(x or 0, y or 0, z or 0)}, {__sub = function(a, b) return a end}) end
})
CFrame.new = CFrame
Enum = Enum or setmetatable({}, {__index = function(t, k) return setmetatable({}, {__index = function(t2, k2) return {Name = k2, Value = 0} end}) end})
]]
    return polyfill .. "\n" .. result
end

function M.loadFile(path)
    local file = io.open(path, "r")
    if not file then return nil, "File not found: " .. path end
    local source = file:read("*a")
    file:close()
    local stripped = M.strip(source)
    local chunk, err = loadstring(stripped, path)
    if not chunk then return nil, "Failed to parse stripped: " .. tostring(err) end
    return chunk
end

return M
