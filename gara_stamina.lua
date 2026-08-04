-- gara_stamina.lua (updated loader + UI using consolidated g2g4l module)
-- This file is intended to be loaded via:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/PannHuessHere/roblox-script/main/gara_stamina.lua", true))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local function safeLog(msg, lvl)
    lvl = lvl or "INFO"
    print(string.format("[GARA %s] [%s] %s", os.date("%H:%M:%S"), lvl, tostring(msg)))
end

-- load consolidated g2g4l (prefer ReplicatedStorage, else raw)
local function load_g2g4l()
    local ok, mod
    pcall(function()
        local rs = game:GetService("ReplicatedStorage"):FindFirstChild("g2g4l")
        if rs and rs:IsA("ModuleScript") then
            ok, mod = pcall(function() return require(rs) end)
            if ok and mod then return mod end
        end
    end)
    -- fallback raw
    local rawUrl = "https://raw.githubusercontent.com/PannHuessHere/roblox-script/main/g2g4l.lua"
    local httpOk, chunk = pcall(function() return game:HttpGet(rawUrl, true) end)
    if not httpOk then safeLog("Failed HttpGet g2g4l: "..tostring(chunk), "ERROR"); return nil end
    local compOk, fn = pcall(function() return loadstring(chunk) end)
    if not compOk or type(fn) ~= "function" then safeLog("g2g4l compile failed: "..tostring(fn), "ERROR"); return nil end
    local runOk, res = pcall(fn)
    if not runOk then safeLog("g2g4l runtime failed: "..tostring(res), "ERROR"); return nil end
    return res
end

local g2g4l = load_g2g4l()
if not g2g4l then safeLog("Could not load g2g4l module", "ERROR"); return end

-- connections table
local connections = {}

-- create managers
local StaminaManager = g2g4l.createManager("Stamina", {RegenRate = 50, MaxValue = 100})
local HealthManager = g2g4l.createManager("Health", {RegenRate = 15, MaxValue = 100})

-- combat detector
local CombatDetector = {inCombat=false, last=0, timeout=5}
function CombatDetector:mark() self.inCombat = true; self.last = tick() end
function CombatDetector:update() if self.inCombat and (tick() - self.last) > self.timeout then self.inCombat = false end end

-- build UI using module helper with dark blue / light accents, size 360x460
local ui = g2g4l.createMainUI({ connections = connections, staminaDefault = StaminaManager.RegenRate, healthDefault = HealthManager.RegenRate, toggleKey = "Minus", closeKey = "X" })
-- adjust size/theme
ui.main.Size = UDim2.new(0, 360, 0, 460)
ui.main.BackgroundColor3 = Color3.fromRGB(12, 24, 52) -- darker blue
ui.main.Title.Text = "  XENO V7 | GARA (custom)"

-- wire up sliders (and save slider connections)
local sSlider = g2g4l.bindSlider(ui.stamina.slider.thumb, ui.stamina.slider.bar, ui.stamina.slider.fill, ui.stamina.slider.label, function(v) StaminaManager:setRegenRate(v) end, 200)
for _, c in ipairs(sSlider.connections) do g2g4l.registerConnection(connections, c) end
local hSlider = g2g4l.bindSlider(ui.health.slider.thumb, ui.health.slider.bar, ui.health.slider.fill, ui.health.slider.label, function(v) HealthManager:setRegenRate(v) end, 200)
for _, c in ipairs(hSlider.connections) do g2g4l.registerConnection(connections, c) end

-- hook toggles
g2g4l.registerConnection(connections, ui.stamina.toggle.MouseButton1Click:Connect(function()
    StaminaManager:toggle(); StaminaManager.InfiniteMode = false
    ui.stamina.toggle.Text = StaminaManager.Enabled and ("Stamina Regen: ON ("..StaminaManager.RegenRate.."%/s)") or "Toggle Stamina"
end))

g2g4l.registerConnection(connections, ui.stamina.combat.MouseButton1Click:Connect(function()
    StaminaManager.OnlyInCombat = not StaminaManager.OnlyInCombat
    ui.stamina.combat.Text = "Only Regen In Combat: " .. (StaminaManager.OnlyInCombat and "ON" or "OFF")
end))

g2g4l.registerConnection(connections, ui.health.toggle.MouseButton1Click:Connect(function()
    HealthManager:toggle(); HealthManager.InfiniteMode = false
    ui.health.toggle.Text = HealthManager.Enabled and ("Health Regen: ON ("..HealthManager.RegenRate.."%/s)") or "Toggle Health"
end))

g2g4l.registerConnection(connections, ui.health.combat.MouseButton1Click:Connect(function()
    HealthManager.OnlyInCombat = not HealthManager.OnlyInCombat
    ui.health.combat.Text = "Only Regen In Combat: " .. (HealthManager.OnlyInCombat and "ON" or "OFF")
end))

-- teleport behind button
g2g4l.registerConnection(connections, ui.actions.teleport.MouseButton1Click:Connect(function()
    local target = g2g4l.getPlayerByName(ui.targetName and tostring(ui.targetName.Value) or "")
    if not target then safeLog("No target selected", "WARNING"); return end
    g2g4l.teleportBehind(target, 3, function(prev) table.insert(connections, prev) end)
end))

-- unload button
g2g4l.registerConnection(connections, ui.actions.unload.MouseButton1Click:Connect(function()
    safeLog("Unloading GARA...", "WARNING")
    g2g4l.cleanup(connections, {ui.screenGui})
end))

-- watch local character
local function watchCharacter(ch)
    g2g4l.safePcall(function()
        local hum = g2g4l.getHumanoid(ch)
        if not hum then return end
        local last = hum.Health
        g2g4l.registerConnection(connections, hum.HealthChanged:Connect(function(new)
            if new < last then CombatDetector:mark() end
            last = new
        end))
    end)
end
if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end
g2g4l.registerConnection(connections, LocalPlayer.CharacterAdded:Connect(function(ch) watchCharacter(ch) end))

-- render loop
local rs = RunService.RenderStepped:Connect(function(dt)
    CombatDetector:update()
    if LocalPlayer and LocalPlayer.Character then
        StaminaManager:apply(LocalPlayer.Character, dt, CombatDetector.inCombat)
        HealthManager:apply(LocalPlayer.Character, dt, CombatDetector.inCombat)
    end
end)
g2g4l.registerConnection(connections, rs)

-- expose unload to global
_G.GARA_UNLOAD = function()
    safeLog("GARA unload requested", "WARNING")
    g2g4l.cleanup(connections, {ui.screenGui})
end

safeLog("gara_stamina initialized (UI should be visible).", "SUCCESS")
