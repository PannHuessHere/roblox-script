-- XENO V7 | GAKURAN (refactor + Health Regen slider + combat-only option + activation key)
-- Required activation key: 1231234123
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- connections tracker for cleanup
local connections = {}

-- logging helper
local function log(message, level)
    level = level or "INFO"
    local timestamp = os.date("%H:%M:%S")
    local logMessage = "[XENO " .. timestamp .. "] [" .. level .. "] " .. message
    print(logMessage)
    return logMessage
end

-- safe pcall wrapper
local function safePcall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        warn("[XENO] Error: " .. tostring(result))
        log("Error: " .. tostring(result), "ERROR")
    end
    return success, result
end

-- basic checks
if not LocalPlayer then
    warn("XenoPremiumV7: LocalPlayer tidak ditemukan")
    return
end

-- destroy previous GUI if exists
if CoreGui:FindFirstChild("XenoPremiumV7") then 
    CoreGui.XenoPremiumV7:Destroy() 
end

-- global active flag
_G.XBActive = true

-- Settings and state
local Settings = {
    ESP = false,
    Respawn = false,
    Hitbox = false
}
local targetPlayerName = ""
local unlocked = false -- activation key entered

-- Teleport history
local teleportHistory = {}
local maxHistory = 5
local function recordTeleport(pos)
    table.insert(teleportHistory, 1, pos)
    if #teleportHistory > maxHistory then table.remove(teleportHistory) end
    log("Teleport recorded. History: " .. #teleportHistory)
end
local function undoTeleport()
    if #teleportHistory > 0 then
        local lastPos = table.remove(teleportHistory, 1)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = lastPos
            log("Teleport undone!", "SUCCESS")
        end
    else
        log("No teleport history!", "WARNING")
    end
end

-- Combat detector
local CombatDetector = {
    inCombat = false,
    lastCombat = 0,
    timeout = 5, -- seconds to stay in combat after last hit
}
function CombatDetector:markCombat()
    self.inCombat = true
    self.lastCombat = tick()
end
function CombatDetector:update()
    if self.inCombat and (tick() - self.lastCombat) > self.timeout then
        self.inCombat = false
    end
end

-- Helper to get posture/stamina value
local function getPostureValue(character)
    if not character then return 100 end
    local postureValue = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
    if postureValue and (postureValue:IsA("NumberValue") or postureValue:IsA("IntValue")) then
        return math.clamp(postureValue.Value, 0, 100)
    end
    local att = character:GetAttribute("Posture") or character:GetAttribute("Stamina")
    if att then return math.clamp(tonumber(att) or 100, 0, 100) end
    return 100
end

-- Clear ESP helper
local function clearESP()
    safePcall(function()
        for _, v in pairs(Workspace:GetChildren()) do
            if v:FindFirstChild("XESP") then pcall(function() v.XESP:Destroy() end) end
        end
        for _, v in pairs(Players:GetPlayers()) do
            if v.Character and v.Character:FindFirstChild("XESP") then pcall(function() v.Character.XESP:Destroy() end) end
        end
    end)
end

-- Safe clean scan
local function safeClean()
    safePcall(function()
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:FindFirstChild("XESP") then
                pcall(function() v.XESP:Destroy() end)
            end
        end
    end)
end

-- Manager base (for consistent API)
local ManagerBase = {}
function ManagerBase:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
function ManagerBase:enable()
    self.Enabled = true
    log(self.Name .. " enabled", "SUCCESS")
end
function ManagerBase:disable()
    self.Enabled = false
    log(self.Name .. " disabled", "INFO")
end
function ManagerBase:toggle()
    self.Enabled = not self.Enabled
    log(self.Name .. " toggled: " .. (self.Enabled and "ON" or "OFF"), "INFO")
    return self.Enabled
end
function ManagerBase:setRegenRate(rate)
    self.RegenRate = math.max(0, tonumber(rate) or self.RegenRate)
    log(self.Name .. " RegenRate set to " .. tostring(self.RegenRate) .. "%/s", "INFO")
end
function ManagerBase:setOnlyInCombat(val)
    self.OnlyInCombat = not not val
    log(self.Name .. " OnlyInCombat: " .. tostring(self.OnlyInCombat), "INFO")
end
function ManagerBase:reset()
    self.Enabled = false
    self.OnlyInCombat = false
    log(self.Name .. " reset", "INFO")
end

-- StaminaManager (inherits ManagerBase)
local StaminaManager = ManagerBase:new({
    Name = "StaminaManager",
    Enabled = false,
    InfiniteMode = false, -- if true, always set to max
    MaxStamina = 100,
    RegenRate = 50, -- percent per second
    OnlyInCombat = false
})
function StaminaManager:setStamina(character, value)
    if not character then return false end
    local stamina = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
    if stamina and (stamina:IsA("NumberValue") or stamina:IsA("IntValue")) then
        stamina.Value = math.clamp(value, 0, self.MaxStamina)
        return true
    end
    local postureAttr = character:GetAttribute("Posture")
    local staminaAttr = character:GetAttribute("Stamina")
    if postureAttr ~= nil then
        character:SetAttribute("Posture", math.clamp(value, 0, self.MaxStamina))
        return true
    end
    if staminaAttr ~= nil then
        character:SetAttribute("Stamina", math.clamp(value, 0, self.MaxStamina))
        return true
    end
    return false
end
function StaminaManager:getStamina(character)
    if not character then return 0 end
    local stamina = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
    if stamina and (stamina:IsA("NumberValue") or stamina:IsA("IntValue")) then return stamina.Value end
    local postureAttr = character:GetAttribute("Posture")
    if postureAttr then return postureAttr end
    local staminaAttr = character:GetAttribute("Stamina")
    if staminaAttr then return staminaAttr end
    return 0
end
function StaminaManager:apply(character, deltaTime)
    if not character or not self.Enabled then return end
    if self.OnlyInCombat and not CombatDetector.inCombat then return end
    safePcall(function()
        if self.InfiniteMode then
            self:setStamina(character, self.MaxStamina)
        else
            local current = self:getStamina(character)
            local amount = (self.MaxStamina * self.RegenRate / 100) * deltaTime
            local newVal = math.min(current + amount, self.MaxStamina)
            self:setStamina(character, newVal)
        end
    end)
end
function StaminaManager:toggleInfiniteMode()
    self.InfiniteMode = not self.InfiniteMode
    if self.InfiniteMode then
        log("Stamina Infinite Mode ENABLED", "SUCCESS")
    else
        log("Stamina Infinite Mode DISABLED", "INFO")
    end
    return self.InfiniteMode
end

-- HealthManager (inherits ManagerBase)
local HealthManager = ManagerBase:new({
    Name = "HealthManager",
    Enabled = false,
    RegenRate = 15, -- default 15%/s (user requested)
    OnlyInCombat = false
})
function HealthManager:apply(character, deltaTime)
    if not character or not self.Enabled then return end
    if self.OnlyInCombat and not CombatDetector.inCombat then return end
    safePcall(function()
        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local maxHP = (hum.MaxHealth > 0) and hum.MaxHealth or 100
        local current = hum.Health
        local amount = (maxHP * self.RegenRate / 100) * deltaTime
        local newHP = math.min(current + amount, maxHP)
        hum.Health = newHP
    end)
end

-- GUI creation
local SG = Instance.new("ScreenGui")
SG.Name = "XenoPremiumV7"
SG.ResetOnSpawn = false
SG.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 420)
MainFrame.Position = UDim2.new(0.02, 0, 0.18, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 28, 50)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = SG

local corner = Instance.new("UICorner", MainFrame)
corner.CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", MainFrame)
stroke.Color = Color3.fromRGB(40, 100, 180)
stroke.Thickness = 1.5

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 36)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundColor3 = Color3.fromRGB(25, 40, 75)
Title.Text = "  XENO V7 | GAKURAN"
Title.TextColor3 = Color3.fromRGB(230, 240, 255)
Title.TextSize = 14
Title.Font = Enum.Font.RobotoMono
Title.TextXAlignment = Enum.TextXAlignment.Left

local HideText = Instance.new("TextLabel", Title)
HideText.Size = UDim2.new(0, 120, 1, 0)
HideText.Position = UDim2.new(1, -130, 0, 0)
HideText.BackgroundTransparency = 1
HideText.Text = "[ RightShift ]"
HideText.TextColor3 = Color3.fromRGB(160, 180, 220)
HideText.TextSize = 11
HideText.TextXAlignment = Enum.TextXAlignment.Right

-- Layout container
local UIList = Instance.new("UIListLayout", MainFrame)
UIList.Padding = UDim.new(0, 8)
UIList.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Padding = UDim.new(0, 8)
UIList.Padding = UDim.new(0, 8)

-- Sections
local function createSection(titleText, parent)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(1, -20, 0, 100)
    frame.BackgroundColor3 = Color3.fromRGB(18, 24, 40)
    frame.BorderSizePixel = 0
    frame.LayoutOrder = 1
    local c = Instance.new("UICorner", frame)
    c.CornerRadius = UDim.new(0, 6)
    local t = Instance.new("TextLabel", frame)
    t.Size = UDim2.new(1, -12, 0, 22)
    t.Position = UDim2.new(0, 6, 0, 6)
    t.BackgroundTransparency = 1
    t.Text = titleText
    t.TextColor3 = Color3.fromRGB(220, 230, 255)
    t.TextSize = 12
    t.Font = Enum.Font.SourceSansSemibold
    return frame
end

-- Stamina Section
local staminaSection = createSection("Stamina Controls", MainFrame)
staminaSection.Size = UDim2.new(1, -20, 0, 120)

local staminaButtons = Instance.new("Frame", staminaSection)
staminaButtons.Size = UDim2.new(1, -12, 0, 28)
staminaButtons.Position = UDim2.new(0, 6, 0, 30)
staminaButtons.BackgroundTransparency = 1

local BInfStamina = Instance.new("TextButton", staminaButtons)
BInfStamina.Size = UDim2.new(0, 150, 1, 0)
BInfStamina.Position = UDim2.new(0, 0, 0, 0)
BInfStamina.Text = "∞ Stamina: OFF"
BInfStamina.Font = Enum.Font.SourceSansBold
BInfStamina.TextSize = 12
BInfStamina.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
BInfStamina.TextColor3 = Color3.fromRGB(255,255,255)
local c1 = Instance.new("UICorner", BInfStamina); c1.CornerRadius = UDim.new(0,6)

local BStaminaRegen = Instance.new("TextButton", staminaButtons)
BStaminaRegen.Size = UDim2.new(0, 150, 1, 0)
BStaminaRegen.Position = UDim2.new(0, 160, 0, 0)
BStaminaRegen.Text = "↑ Regen Stamina: OFF"
BStaminaRegen.Font = Enum.Font.SourceSansBold
BStaminaRegen.TextSize = 12
BStaminaRegen.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
BStaminaRegen.TextColor3 = Color3.fromRGB(255,255,255)
local c2 = Instance.new("UICorner", BStaminaRegen); c2.CornerRadius = UDim.new(0,6)

-- Stamina slider
local staminaSliderFrame = Instance.new("Frame", staminaSection)
staminaSliderFrame.Size = UDim2.new(1, -12, 0, 26)
staminaSliderFrame.Position = UDim2.new(0, 6, 0, 64)
staminaSliderFrame.BackgroundTransparency = 1

local staminaLabel = Instance.new("TextLabel", staminaSliderFrame)
staminaLabel.Size = UDim2.new(0, 160, 1, 0)
staminaLabel.Position = UDim2.new(0, 0, 0, 0)
staminaLabel.BackgroundTransparency = 1
staminaLabel.Text = "Stamina Regen Rate: " .. tostring(StaminaManager.RegenRate or 50) .. "%/s"
staminaLabel.TextColor3 = Color3.fromRGB(200,200,220)
staminaLabel.TextSize = 11
staminaLabel.Font = Enum.Font.SourceSans

local staminaSliderBar = Instance.new("Frame", staminaSliderFrame)
staminaSliderBar.Size = UDim2.new(0.5, 0, 0, 8)
staminaSliderBar.Position = UDim2.new(0, 162, 0.5, -4)
staminaSliderBar.BackgroundColor3 = Color3.fromRGB(40,60,90)
local ssCorner = Instance.new("UICorner", staminaSliderBar); ssCorner.CornerRadius = UDim.new(0, 6)

local staminaSliderFill = Instance.new("Frame", staminaSliderBar)
staminaSliderFill.Size = UDim2.new(math.clamp((StaminaManager.RegenRate or 50)/200, 0, 1), 0, 1, 0)
staminaSliderFill.BackgroundColor3 = Color3.fromRGB(100,180,255)
local ssfCorner = Instance.new("UICorner", staminaSliderFill); ssfCorner.CornerRadius = UDim.new(0, 6)

local staminaThumb = Instance.new("TextButton", staminaSliderBar)
staminaThumb.Size = UDim2.new(0, 12, 0, 12)
staminaThumb.Position = UDim2.new(staminaSliderFill.Size.X.Scale, -6, 0.5, -6)
staminaThumb.Text = ""
staminaThumb.BackgroundColor3 = Color3.fromRGB(220,220,255)
local sstCorner = Instance.new("UICorner", staminaThumb); sstCorner.CornerRadius = UDim.new(0, 6)

-- Stamina OnlyInCombat toggle
local StaminaCombatToggle = Instance.new("TextButton", staminaSection)
StaminaCombatToggle.Size = UDim2.new(0, 200, 0, 24)
StaminaCombatToggle.Position = UDim2.new(0, 6, 0, 92)
StaminaCombatToggle.Text = "Only Regen In Combat: OFF"
StaminaCombatToggle.Font = Enum.Font.SourceSans
StaminaCombatToggle.TextSize = 11
StaminaCombatToggle.BackgroundColor3 = Color3.fromRGB(70,70,80)
local scCorner = Instance.new("UICorner", StaminaCombatToggle); scCorner.CornerRadius = UDim.new(0,6)

-- Health Section
local healthSection = createSection("Health Controls", MainFrame)
healthSection.Size = UDim2.new(1, -20, 0, 120)

local healthButtons = Instance.new("Frame", healthSection)
healthButtons.Size = UDim2.new(1, -12, 0, 28)
healthButtons.Position = UDim2.new(0, 6, 0, 30)
healthButtons.BackgroundTransparency = 1

local BHealthRegen = Instance.new("TextButton", healthButtons)
BHealthRegen.Size = UDim2.new(0, 240, 1, 0)
BHealthRegen.Position = UDim2.new(0, 0, 0, 0)
BHealthRegen.Text = "♥ Regen HP: OFF"
BHealthRegen.Font = Enum.Font.SourceSansBold
BHealthRegen.TextSize = 12
BHealthRegen.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
BHealthRegen.TextColor3 = Color3.fromRGB(255,255,255)
local hc1 = Instance.new("UICorner", BHealthRegen); hc1.CornerRadius = UDim.new(0,6)

-- Health slider
local healthSliderFrame = Instance.new("Frame", healthSection)
healthSliderFrame.Size = UDim2.new(1, -12, 0, 26)
healthSliderFrame.Position = UDim2.new(0, 6, 0, 64)
healthSliderFrame.BackgroundTransparency = 1

local healthLabel = Instance.new("TextLabel", healthSliderFrame)
healthLabel.Size = UDim2.new(0, 160, 1, 0)
healthLabel.Position = UDim2.new(0, 0, 0, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.Text = "Health Regen Rate: " .. tostring(HealthManager.RegenRate) .. "%/s"
healthLabel.TextColor3 = Color3.fromRGB(200,200,220)
healthLabel.TextSize = 11
healthLabel.Font = Enum.Font.SourceSans

local healthSliderBar = Instance.new("Frame", healthSliderFrame)
healthSliderBar.Size = UDim2.new(0.5, 0, 0, 8)
healthSliderBar.Position = UDim2.new(0, 162, 0.5, -4)
healthSliderBar.BackgroundColor3 = Color3.fromRGB(40,60,90)
local hsCorner = Instance.new("UICorner", healthSliderBar); hsCorner.CornerRadius = UDim.new(0, 6)

local healthSliderFill = Instance.new("Frame", healthSliderBar)
healthSliderFill.Size = UDim2.new(math.clamp((HealthManager.RegenRate)/200, 0, 1), 0, 1, 0)
healthSliderFill.BackgroundColor3 = Color3.fromRGB(120,220,140)
local hsfCorner = Instance.new("UICorner", healthSliderFill); hsfCorner.CornerRadius = UDim.new(0, 6)

local healthThumb = Instance.new("TextButton", healthSliderBar)
healthThumb.Size = UDim2.new(0, 12, 0, 12)
healthThumb.Position = UDim2.new(healthSliderFill.Size.X.Scale, -6, 0.5, -6)
healthThumb.Text = ""
healthThumb.BackgroundColor3 = Color3.fromRGB(255,255,255)
local hstCorner = Instance.new("UICorner", healthThumb); hstCorner.CornerRadius = UDim.new(0, 6)

-- Health OnlyInCombat toggle
local HealthCombatToggle = Instance.new("TextButton", healthSection)
HealthCombatToggle.Size = UDim2.new(0, 200, 0, 24)
HealthCombatToggle.Position = UDim2.new(0, 6, 0, 92)
HealthCombatToggle.Text = "Only Regen In Combat: OFF"
HealthCombatToggle.Font = Enum.Font.SourceSans
HealthCombatToggle.TextSize = 11
HealthCombatToggle.BackgroundColor3 = Color3.fromRGB(70,70,80)
local hcCorner = Instance.new("UICorner", HealthCombatToggle); hcCorner.CornerRadius = UDim.new(0,6)

-- Teleport & Misc buttons
local miscSection = createSection("Actions", MainFrame)
miscSection.Size = UDim2.new(1, -20, 0, 120)
local TeleportBehind = Instance.new("TextButton", miscSection)
TeleportBehind.Size = UDim2.new(0, 200, 0, 28)
TeleportBehind.Position = UDim2.new(0, 6, 0, 30)
TeleportBehind.Text = "⚡ Teleport Behind Target"
TeleportBehind.Font = Enum.Font.SourceSansBold
TeleportBehind.BackgroundColor3 = Color3.fromRGB(30,110,220)
local unloadBtn = Instance.new("TextButton", miscSection)
unloadBtn.Size = UDim2.new(0, 100, 0, 28)
unloadBtn.Position = UDim2.new(0, 210, 0, 30)
unloadBtn.Text = "⛔ Unload"
unloadBtn.Font = Enum.Font.SourceSansBold
unloadBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)

-- Activation key modal
local KeyModal = Instance.new("Frame", SG)
KeyModal.Name = "KeyModal"
KeyModal.Size = UDim2.new(0, 340, 0, 140)
KeyModal.Position = UDim2.new(0.5, -170, 0.5, -70)
KeyModal.BackgroundColor3 = Color3.fromRGB(16,18,28)
KeyModal.BorderSizePixel = 0
local kmCorner = Instance.new("UICorner", KeyModal); kmCorner.CornerRadius = UDim.new(0,8)
local kmTitle = Instance.new("TextLabel", KeyModal)
kmTitle.Size = UDim2.new(1, -20, 0, 28)
kmTitle.Position = UDim2.new(0, 10, 0, 8)
kmTitle.BackgroundTransparency = 1
kmTitle.Text = "Enter Activation Key"
kmTitle.TextColor3 = Color3.fromRGB(220,230,255)
kmTitle.Font = Enum.Font.SourceSansBold
kmTitle.TextSize = 14
local keyBox = Instance.new("TextBox", KeyModal)
keyBox.Size = UDim2.new(1, -40, 0, 36)
keyBox.Position = UDim2.new(0, 20, 0, 48)
keyBox.PlaceholderText = "Activation Key"
keyBox.ClearTextOnFocus = false
keyBox.Text = ""
keyBox.TextSize = 14
local submitBtn = Instance.new("TextButton", KeyModal)
submitBtn.Size = UDim2.new(0, 120, 0, 28)
submitBtn.Position = UDim2.new(1, -140, 1, -40)
submitBtn.Text = "Activate"
submitBtn.BackgroundColor3 = Color3.fromRGB(70,140,200)
local cancelBtn = Instance.new("TextButton", KeyModal)
cancelBtn.Size = UDim2.new(0, 80, 0, 28)
cancelBtn.Position = UDim2.new(1, -60, 1, -40)
cancelBtn.Text = "Close"
cancelBtn.BackgroundColor3 = Color3.fromRGB(90,90,100)

-- Initially hide main UI until unlocked
MainFrame.Visible = false

-- Utility: set slider visuals
local function updateSliderVisual(barFill, thumb, bar, valuePercent)
    local clamped = math.clamp(valuePercent, 0, 1)
    barFill.Size = UDim2.new(clamped, 0, 1, 0)
    thumb.Position = UDim2.new(clamped, -6, 0.5, -6)
end

-- Slider interaction helper (returns connection to Mouse events)
local function makeSliderInteractions(thumb, bar, fill, label, onUpdateFunc, maxValue)
    maxValue = maxValue or 200
    local dragging = false
    local conn1, conn2, conn3

    conn1 = thumb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    conn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    conn3 = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouse = UserInputService:GetMouseLocation()
            local absPos = bar.AbsolutePosition
            local absSize = bar.AbsoluteSize
            local x = mouse.X - absPos.X
            local percent = x / absSize.X
            percent = math.clamp(percent, 0, 1)
            updateSliderVisual(fill, thumb, bar, percent)
            local value = math.floor(percent * maxValue)
            if onUpdateFunc then pcall(onUpdateFunc, value) end
            if label then label.Text = label.Text:match("^[^:]+:") .. " " .. tostring(value) .. "%/s" end
        end
    end)

    return {conn1, conn2, conn3}
end

-- Hook up slider interactions and store connections
do
    local conns = makeSliderInteractions(staminaThumb, staminaSliderBar, staminaSliderFill, staminaLabel, function(v)
        StaminaManager:setRegenRate(v)
    end, 200)
    for _, c in ipairs(conns) do table.insert(connections, c) end

    local conns2 = makeSliderInteractions(healthThumb, healthSliderBar, healthSliderFill, healthLabel, function(v)
        HealthManager:setRegenRate(v)
    end, 200)
    for _, c in ipairs(conns2) do table.insert(connections, c) end
end

-- Button connections
table.insert(connections, BInfStamina.MouseButton1Click:Connect(function()
    if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    StaminaManager.Enabled = not StaminaManager.Enabled
    StaminaManager.InfiniteMode = true
    BInfStamina.Text = StaminaManager.Enabled and "∞ Stamina: ON" or "∞ Stamina: OFF"
    BInfStamina.BackgroundColor3 = StaminaManager.Enabled and Color3.fromRGB(45,185,45) or Color3.fromRGB(180,50,50)
    -- ensure regen UI shows off if infinite
    if StaminaManager.Enabled then
        BStaminaRegen.Text = "↑ Regen Stamina: OFF"
        BStaminaRegen.BackgroundColor3 = Color3.fromRGB(180,50,50)
    end
    log("Infinite Stamina: " .. (StaminaManager.Enabled and "ON" or "OFF"))
end))

table.insert(connections, BStaminaRegen.MouseButton1Click:Connect(function()
    if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    if StaminaManager.InfiniteMode and StaminaManager.Enabled then
        StaminaManager.Enabled = false
    end
    StaminaManager.InfiniteMode = false
    StaminaManager.Enabled = not StaminaManager.Enabled
    BStaminaRegen.Text = StaminaManager.Enabled and ("↑ Regen Stamina: ON (" .. StaminaManager.RegenRate .. "%/s)") or "↑ Regen Stamina: OFF"
    BStaminaRegen.BackgroundColor3 = StaminaManager.Enabled and Color3.fromRGB(100,200,255) or Color3.fromRGB(180,50,50)
    BInfStamina.Text = "∞ Stamina: OFF"
    BInfStamina.BackgroundColor3 = Color3.fromRGB(180,50,50)
    log("Stamina Regen: " .. (StaminaManager.Enabled and "ON" or "OFF"))
end))

table.insert(connections, StaminaCombatToggle.MouseButton1Click:Connect(function()
    if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    StaminaManager.OnlyInCombat = not StaminaManager.OnlyInCombat
    StaminaCombatToggle.Text = "Only Regen In Combat: " .. (StaminaManager.OnlyInCombat and "ON" or "OFF")
    StaminaCombatToggle.BackgroundColor3 = StaminaManager.OnlyInCombat and Color3.fromRGB(120,200,140) or Color3.fromRGB(70,70,80)
    log("Stamina OnlyInCombat: " .. tostring(StaminaManager.OnlyInCombat))
end))

table.insert(connections, BHealthRegen.MouseButton1Click:Connect(function()
    if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    HealthManager.Enabled = not HealthManager.Enabled
    BHealthRegen.Text = HealthManager.Enabled and ("♥ Regen HP: ON (" .. HealthManager.RegenRate .. "%/s)") or "♥ Regen HP: OFF"
    BHealthRegen.BackgroundColor3 = HealthManager.Enabled and Color3.fromRGB(120,220,140) or Color3.fromRGB(180,50,50)
    log("Health Regen: " .. (HealthManager.Enabled and "ON" or "OFF"))
end))

table.insert(connections, HealthCombatToggle.MouseButton1Click:Connect(function()
    if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    HealthManager.OnlyInCombat = not HealthManager.OnlyInCombat
    HealthCombatToggle.Text = "Only Regen In Combat: " .. (HealthManager.OnlyInCombat and "ON" or "OFF")
    HealthCombatToggle.BackgroundColor3 = HealthManager.OnlyInCombat and Color3.fromRGB(120,220,140) or Color3.fromRGB(70,70,80)
    log("Health OnlyInCombat: " .. tostring(HealthManager.OnlyInCombat))
end))

table.insert(connections, TeleportBehind.MouseButton1Click:Connect(function()
    if not _G.XBActive or not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    if targetPlayerName ~= "" then
        safePcall(function()
            local tPlr = Players:FindFirstChild(targetPlayerName)
            if tPlr and tPlr.Character and tPlr.Character:FindFirstChild("HumanoidRootPart") then
                recordTeleport(LocalPlayer.Character.HumanoidRootPart.CFrame)
                LocalPlayer.Character.HumanoidRootPart.CFrame = tPlr.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
                log("Teleported behind " .. targetPlayerName, "SUCCESS")
            end
        end)
    else
        log("No target selected!", "WARNING")
    end
end))

table.insert(connections, unloadBtn.MouseButton1Click:Connect(function()
    safePcall(function()
        log("Unloading script...", "WARNING")
        _G.XBActive = false
        clearESP()
        safeClean()
        if CoreGui:FindFirstChild("XenoSelfHUD") then CoreGui.XenoSelfHUD:Destroy() end
        if SG then SG:Destroy() end
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        log("Script unloaded successfully", "SUCCESS")
    end)
end))

-- Dropdown (target selection)
local DropContainer = Instance.new("ScrollingFrame", MainFrame)
DropContainer.Size = UDim2.new(1, -40, 0, 70)
DropContainer.Position = UDim2.new(0, 20, 1, -90)
DropContainer.BackgroundColor3 = Color3.fromRGB(18, 24, 40)
DropContainer.BorderSizePixel = 0
DropContainer.CanvasSize = UDim2.new(0,0,0,0)
DropContainer.ScrollBarThickness = 6
local DropListLayout = Instance.new("UIListLayout", DropContainer)
DropListLayout.Padding = UDim.new(0,4)
local DropCorner = Instance.new("UICorner", DropContainer)

local function updateDropdown()
    safePcall(function()
        for _, child in pairs(DropContainer:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -8, 0, 20)
                btn.Text = " " .. p.DisplayName .. " (@" .. p.Name .. ")"
                btn.TextColor3 = Color3.fromRGB(200,220,255)
                btn.BackgroundColor3 = (targetPlayerName == p.Name) and Color3.fromRGB(45,125,230) or Color3.fromRGB(30,40,60)
                btn.Font = Enum.Font.SourceSans
                btn.TextSize = 12
                btn.TextXAlignment = Enum.TextXAlignment.Left
                local btnCorner = Instance.new("UICorner", btn)
                btnCorner.CornerRadius = UDim.new(0,4)
                table.insert(connections, btn.MouseButton1Click:Connect(function()
                    targetPlayerName = p.Name
                    updateDropdown()
                    log("Target selected: " .. p.Name, "INFO")
                end))
                btn.Parent = DropContainer
            end
        end
        DropContainer.CanvasSize = UDim2.new(0,0,0, DropListLayout.AbsoluteContentSize.Y)
    end)
end

-- ESP function (kept simple)
local function esp(ch, npc)
    if not ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("XESP") then return end
    safePcall(function()
        local f = Instance.new("Folder", ch)
        f.Name = "XESP"
        local b = Instance.new("BillboardGui")
        b.AlwaysOnTop = true
        b.Size = UDim2.new(0, 140, 0, 55)
        b.MaxDistance = 350
        b.Adornee = ch:FindFirstChild("Head") or ch.HumanoidRootPart
        local titleL = Instance.new("TextLabel", b)
        titleL.Size = UDim2.new(1, 0, 0, 15)
        titleL.BackgroundTransparency = 1
        titleL.TextSize = 10
        titleL.Font = Enum.Font.RobotoMono
        titleL.TextColor3 = npc and Color3.fromRGB(255,140,140) or Color3.fromRGB(220,235,255)
        titleL.Text = (npc and "[NPC] " or "") .. ch.Name
        local hum = ch:FindFirstChildOfClass("Humanoid")
        local curHP = hum and hum.Health or 0
        local maxHP = hum and hum.MaxHealth or 100
        local pctHP = math.clamp(curHP / maxHP, 0, 1)
        local hpB = Instance.new("Frame", b)
        hpB.Size = UDim2.new(1,0,0,10)
        hpB.Position = UDim2.new(0,0,0,18)
        hpB.BackgroundColor3 = Color3.fromRGB(30,35,45)
        local hpF = Instance.new("Frame", hpB)
        hpF.Size = UDim2.new(pctHP,0,1,0)
        hpF.BackgroundColor3 = Color3.fromRGB(45,185,45)
        local hpT = Instance.new("TextLabel", hpB)
        hpT.Size = UDim2.new(1,0,1,0)
        hpT.BackgroundTransparency = 1
        hpT.TextSize = 9
        hpT.Font = Enum.Font.SourceSansBold
        hpT.TextColor3 = Color3.fromRGB(255,255,255)
        hpT.Text = "HP: " .. math.floor(pctHP*100) .. "%"
        local curST = getPostureValue(ch)
        local pctST = math.clamp(curST/100,0,1)
        local stB = Instance.new("Frame", b)
        stB.Size = UDim2.new(1,0,0,10)
        stB.Position = UDim2.new(0,0,0,32)
        stB.BackgroundColor3 = Color3.fromRGB(30,35,45)
        local stF = Instance.new("Frame", stB)
        stF.Size = UDim2.new(pctST,0,1,0)
        stF.BackgroundColor3 = Color3.fromRGB(230,160,35)
        local stT = Instance.new("TextLabel", stB)
        stT.Size = UDim2.new(1,0,1,0)
        stT.BackgroundTransparency = 1
        stT.TextSize = 9
        stT.Font = Enum.Font.SourceSansBold
        stT.TextColor3 = Color3.fromRGB(255,255,255)
        stT.Text = "STM: " .. math.floor(pctST*100) .. "%"
        b.Parent = f
    end)
end

-- FPS tracker
local lastFrameTime = tick()
local lastDeltaTime = 0
local fps = 0

-- RenderStepped loop
table.insert(connections, RunService.RenderStepped:Connect(function()
    -- FPS
    local now = tick()
    local dt = now - lastFrameTime
    if dt > 0 then fps = math.floor(1/dt) end
    lastDeltaTime = dt
    lastFrameTime = now

    -- update combat detector
    CombatDetector:update()

    -- apply managers
    if _G.XBActive and unlocked and LocalPlayer.Character then
        StaminaManager:apply(LocalPlayer.Character, lastDeltaTime)
        HealthManager:apply(LocalPlayer.Character, lastDeltaTime)
    end
end))

-- Watch local player's humanoid for damage to mark combat
local function watchCharacter(ch)
    safePcall(function()
        local hum = ch:WaitForChild("Humanoid", 10)
        if hum then
            local lastHealth = hum.Health
            table.insert(connections, hum.HealthChanged:Connect(function(newHealth)
                if newHealth < lastHealth then
                    CombatDetector:markCombat()
                end
                lastHealth = newHealth
            end))
            table.insert(connections, hum.Died:Connect(function()
                log("Character died", "WARNING")
                if Settings.Respawn then
                    task.wait(0.1)
                    local ts = game:GetService("TeleportService")
                    if #Players:GetPlayers() <= 1 then
                        ts:Teleport(game.PlaceId, LocalPlayer)
                    else
                        ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                    end
                end
            end))
        end
    end)
end

table.insert(connections, Players.PlayerAdded:Connect(function(plr)
    log("Player joined: " .. plr.Name)
    updateDropdown()
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(plr)
    log("Player left: " .. plr.Name)
    if targetPlayerName == plr.Name then
        targetPlayerName = ""
    end
    updateDropdown()
end))

table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(ch) watchCharacter(ch) end))
if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end

-- input handlers (hotkeys, combat mark when click)
table.insert(connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    elseif input.KeyCode == Enum.KeyCode.U then
        undoTeleport()
    elseif input.KeyCode == Enum.KeyCode.I then
        if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
        StaminaManager:toggle(); StaminaManager.InfiniteMode = true
        BInfStamina.Text = StaminaManager.Enabled and "∞ Stamina: ON" or "∞ Stamina: OFF"
    elseif input.KeyCode == Enum.KeyCode.T then
        if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
        StaminaManager:toggle(); StaminaManager.InfiniteMode = false
        BStaminaRegen.Text = StaminaManager.Enabled and ("↑ Regen Stamina: ON (" .. StaminaManager.RegenRate .. "%/s)") or "↑ Regen Stamina: OFF"
    elseif input.KeyCode == Enum.KeyCode.Y then
        if not unlocked then log("Activation key belum dimasukkan", "WARNING") return end
        HealthManager:toggle()
        BHealthRegen.Text = HealthManager.Enabled and ("♥ Regen HP: ON (" .. HealthManager.RegenRate .. "%/s)") or "♥ Regen HP: OFF"
    end

    -- mark combat on mouse click (considered as attack)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        CombatDetector:markCombat()
    end
end))

-- Dropdown init
updateDropdown()

-- Key modal actions
local ACTIVATION_KEY = "1231234123"
table.insert(connections, submitBtn.MouseButton1Click:Connect(function()
    if keyBox.Text == ACTIVATION_KEY then
        unlocked = true
        MainFrame.Visible = true
        KeyModal:Destroy()
        log("Activation key accepted. XENO unlocked.", "SUCCESS")
    else
        log("Invalid activation key entered", "WARNING")
        -- brief feedback
        keyBox.Text = ""
    end
end))
table.insert(connections, cancelBtn.MouseButton1Click:Connect(function()
    KeyModal:Destroy()
    -- keep locked; only modal removed
    log("Activation modal closed. Features remain locked.", "INFO")
end))

-- Teleport behind / hitbox assist (kept but gated behind unlock)
table.insert(connections, UserInputService.InputChanged:Connect(function(input)
    -- nothing heavy here; reserved for slider dragging handled separately
end))

-- Simple watch loop for updating dropdown and HUD texts (including slider label updates if needed)
task.spawn(function()
    while _G.XBActive do
        safePcall(function()
            updateDropdown()
            -- update slider labels (in case set via script)
            staminaLabel.Text = "Stamina Regen Rate: " .. tostring(StaminaManager.RegenRate) .. "%/s"
            healthLabel.Text = "Health Regen Rate: " .. tostring(HealthManager.RegenRate) .. "%/s"
            -- update slider visuals
            updateSliderVisual(staminaSliderFill, staminaThumb, staminaSliderBar, math.clamp((StaminaManager.RegenRate)/200, 0, 1))
            updateSliderVisual(healthSliderFill, healthThumb, healthSliderBar, math.clamp((HealthManager.RegenRate)/200, 0, 1))
        end)
        task.wait(0.5)
    end
end)

log("XENO V7 (refactor) loaded. Enter Activation Key to unlock features.", "INFO")
log("Hotkeys: I=Infinite Stamina | T=Stamina Regen | Y=Health Regen | U=Undo Teleport | RightShift=Toggle UI", "INFO")
