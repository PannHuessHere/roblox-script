-- g2g4L.lua (DEPRECATED wrapper)
-- This file existed as a duplicate due to case-sensitivity. The canonical module is "g2g4l.lua" (lowercase).
-- To avoid confusion, this wrapper will attempt to return the canonical module if possible, otherwise it errors

local ok, mod
-- prefer ReplicatedStorage module if present
pcall(function()
    local rs = game:GetService("ReplicatedStorage"):FindFirstChild("g2g4l")
    if rs and rs:IsA("ModuleScript") then
        ok, mod = pcall(function() return require(rs) end)
    end
end)

if ok and mod then
    return mod
end

-- fallback: try to load canonical file from raw URL
local raw = "https://raw.githubusercontent.com/PannHuessHere/roblox-script/main/g2g4l.lua"
local httpOk, chunk = pcall(function() return game:HttpGet(raw, true) end)
if httpOk and type(chunk) == "string" then
    local compileOk, fn = pcall(function() return loadstring(chunk) end)
    if compileOk and type(fn) == "function" then
        local runOk, result = pcall(fn)
        if runOk and result then
            return result
        end
    end
end

error("Deprecated module 'g2g4L.lua' detected. Please use 'g2g4l.lua' (lowercase) as the canonical module.")
