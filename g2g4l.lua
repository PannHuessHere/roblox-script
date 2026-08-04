-- g2g4l.lua
-- Utility module untuk XENO / GUI
-- Added: close/hide UI controls (buttons + hotkeys), cleanup to avoid memory leaks

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local module = {}
module.__version = "0.3.0"

-- CONNECTIONS SAFE INSERT
function module.registerConnection(tbl, conn)
    if type(tbl) ~= "table" or conn == nil then return end
    table.insert(tbl, conn)
    return conn
end

-- SAFE PCALL
function module.safePcall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        warn("[g2g4l] Error: " .. tostring(res))
    end
    return ok, res
end

-- UTILITIES
function module.clamp(val, minv, maxv)
    val = tonumber(val) or 0
    if minv and val < minv then return minv end
    if maxv and val > maxv then return maxv end
    return val
end

function module.toNumber(v, default)
    local n = tonumber(v)
    if not n then return default or 0 end
    return n
end

function module.formatTimeSeconds(sec)
    sec = tonumber(sec) or 0
    local s = math.floor(sec % 60)
    local m = math.floor((sec / 60) % 60)
    local h = math.floor(sec / 3600)
    if h > 0 then
        return string.format("%02d:%02d:%02d", h, m, s)
    else
        return string.format("%02d:%02d", m, s)
    end
end

-- PLAYER / HUMANOID HELPERS
function module.getPlayerByName(name)
    if not name then return nil end
    local byName = Players:FindFirstChild(name)
    if byName then return byName end
    for _, p in pairs(Players:GetPlayers()) do
        if p.DisplayName == name then return p end
    end
    for _, p in pairs(Players:GetPlayers()) do
        if string.find(string.lower(p.Name), string.lower(name)) or string.find(string.lower(p.DisplayName), string.lower(name)) then
            return p
        end
    end
    return nil
end

function module.getHumanoid(character)
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

function module.getPostureValue(character)
    if not character then return 100 end
    local postureValue = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
    if postureValue and (postureValue:IsA("NumberValue") or postureValue:IsA("IntValue")) then
        return module.clamp(postureValue.Value, 0, 100)
    end
    if character.GetAttribute then
        local att = character:GetAttribute("Posture") or character:GetAttribute("Stamina")
        if att then return module.clamp(tonumber(att) or 100, 0, 100) end
    end
    return 100
end

-- TELEPORT BEHIND helper (safe)
function module.teleportBehind(targetPlayer, offsetZ, recordFunc)
    offsetZ = tonumber(offsetZ) or 3
    if not targetPlayer then return false, "no target" end
    local char = targetPlayer.Character
    if not char then return false, "target has no character" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "target has no HRP" end
    local localPlayer = Players.LocalPlayer
    if not localPlayer or not localPlayer.Character then return false, "local player/character missing" end
    local myHRP = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return false, "local HRP missing" end
    return module.safePcall(function()
        if recordFunc and type(recordFunc) == "function" and myHRP.CFrame then
            pcall(function() recordFunc(myHRP.CFrame) end)
        end
        myHRP.CFrame = hrp.CFrame * CFrame.new(0, 0, offsetZ)
    end)
end

-- DEBOUNCE
function module.debounce(func, delay)
    local busy = false
    delay = tonumber(delay) or 0.2
    return function(...)
        if busy then return end
        busy = true
        spawn(function()
            pcall(function() func(...) end)
            wait(delay)
            busy = false
        end)
    end
end

-- REQUIRE FROM URL (raw code). NOTE: caller accepts the risk.
function module.requireFromUrl(url)
    if type(url) ~= "string" then return nil, "invalid url" end
    local ok, chunkOrErr = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil, ("HttpGet failed: " .. tostring(chunkOrErr)) end
    local ok2, res = pcall(function() return loadstring(chunkOrErr) end)
    if not ok2 then return nil, ("loadstring compile error: " .. tostring(res)) end
    local ok3, mod = pcall(function() return res() end)
    if not ok3 then return nil, ("module runtime error: " .. tostring(mod)) end
    return mod, nil
end

-- WATCH DAMAGE (improved): accepts Player | Character | Humanoid
-- callback(newHealth, oldHealth)
function module.watchDamage(target, callback)
    if not target then return nil, "no target" end
    local char
    if typeof(target) == "Instance" then
        if target:IsA("Player") then
            char = target.Character
        elseif target:FindFirstChildOfClass then
            if target:IsA("Model") then char = target
            elseif target:IsA("Humanoid") then
                local hum = target
                local conn
                local last = hum.Health
                conn = hum.HealthChanged:Connect(function(new)
                    if new < last then
                        pcall(function() callback(new, last) end)
                    end
                    last = new
                end)
                return conn
            end
        end
    elseif type(target) == "string" then
        local pl = module.getPlayerByName(target)
        char = pl and pl.Character
    end
    if not char then return nil, "character not found" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil, "humanoid not found" end
    local last = hum.Health
    local conn = hum.HealthChanged:Connect(function(new)
        if new < last then
            pcall(function() callback(new, last) end)
        end
        last = new
    end)
    return conn
end

-- SLIDER BINDING helper
function module.bindSlider(thumb, bar, fill, label, onUpdate, maxValue)
    maxValue = tonumber(maxValue) or 200
    local dragging = false
    local conns = {}

    local function updateVisual(percent)
        percent = module.clamp(percent, 0, 1)
        if fill and fill:IsA("GuiObject") then
            fill.Size = UDim2.new(percent, 0, 1, 0)
        end
        if thumb and thumb:IsA("GuiObject") then
            thumb.Position = UDim2.new(percent, -6, 0.5, -6)
        end
    end

    local function setFromMouse()
        local mouse = UserInputService:GetMouseLocation()
        local absPos = bar.AbsolutePosition
        local absSize = bar.AbsoluteSize
        local x = mouse.X - absPos.X
        local percent = x / absSize.X
        percent = module.clamp(percent, 0, 1)
        updateVisual(percent)
        local value = math.floor(percent * maxValue)
        if label and (label:IsA("TextLabel") or label:IsA("TextBox")) then
            local prefix = tostring(label.Text or "")
            prefix = prefix:match("^[^:]+:") or prefix
            label.Text = (prefix or "") .. " " .. tostring(value) .. "%/s"
        end
        if type(onUpdate) == "function" then
            pcall(onUpdate, value)
        end
    end

    table.insert(conns, thumb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end))
    table.insert(conns, thumb.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))
    table.insert(conns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))
    table.insert(conns, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromMouse()
        end
    end))

    return {
        connections = conns,
        updateVisual = updateVisual,
        setValue = function(value)
            local percent = module.clamp(value / maxValue, 0, 1)
            updateVisual(percent)
            if type(onUpdate) == "function" then pcall(onUpdate, math.floor(value)) end
            if label and (label:IsA("TextLabel") or label:IsA("TextBox")) then
                local prefix = tostring(label.Text or "")
                prefix = prefix:match("^[^:]+:") or prefix
                label.Text = (prefix or "") .. " " .. tostring(math.floor(value)) .. "%/s"
            end
        end
    }
end

-- MANAGER FACTORY (consistent API)
function module.createManager(name, opts)
    opts = opts or {}
    local mgr = {}
    mgr.Name = tostring(name or "Manager")
    mgr.Enabled = false
    mgr.InfiniteMode = not not opts.InfiniteMode
    mgr.MaxValue = tonumber(opts.MaxValue) or 100
    mgr.RegenRate = tonumber(opts.RegenRate) or 50
    mgr.OnlyInCombat = not not opts.OnlyInCombat

    function mgr:enable() self.Enabled = true end
    function mgr:disable() self.Enabled = false end
    function mgr:toggle() self.Enabled = not self.Enabled; return self.Enabled end
    function mgr:setRegenRate(r) self.RegenRate = tonumber(r) or self.RegenRate end
    function mgr:setOnlyInCombat(v) self.OnlyInCombat = not not v end
    function mgr:setMaxValue(v) self.MaxValue = tonumber(v) or self.MaxValue end
    function mgr:reset()
        self.Enabled = false
        self.InfiniteMode = false
        self.OnlyInCombat = false
    end

    function mgr:apply(character, deltaTime, combatState)
        if not character or not self.Enabled then return end
        if self.OnlyInCombat and not combatState then return end
        module.safePcall(function()
            if self.InfiniteMode then
                local v = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
                if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
                    v.Value = self.MaxValue
                    return
                end
                if character.SetAttribute and (character:GetAttribute("Posture") or character:GetAttribute("Stamina")) ~= nil then
                    character:SetAttribute("Posture", self.MaxValue)
                    return
                end
                return
            end

            local current = module.getPostureValue(character)
            local amount = (self.MaxValue * (self.RegenRate / 100)) * deltaTime
            local newVal = math.min(current + amount, self.MaxValue)
            local v = character:FindFirstChild("Posture") or character:FindFirstChild("Stamina") or character:FindFirstChild("PostureValue")
            if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
                v.Value = newVal
                return
            end
            if character.SetAttribute and (character:GetAttribute("Posture") or character:GetAttribute("Stamina")) ~= nil then
                character:SetAttribute("Posture", newVal)
                return
            end
        end)
    end

    return mgr
end

-- CLEANUP helpers to avoid memory leaks
function module.cleanup(connectionsTable, guiList)
    -- disconnect all connections in the provided table
    if type(connectionsTable) == "table" then
        for _, c in ipairs(connectionsTable) do
            pcall(function()
                if type(c) == "RBXScriptConnection" or (type(c) == "table" and c.Disconnect) then
                    -- RBXScriptConnection
                    c:Disconnect()
                elseif type(c) == "function" then
                    -- ignore
                elseif type(c) == "userdata" and c.Disconnect then
                    -- try disconnect
                    pcall(function() c:Disconnect() end)
                end
            end)
        end
        -- clear table
        for i = #connectionsTable, 1, -1 do
            connectionsTable[i] = nil
        end
    end

    -- destroy provided GUI instances
    if type(guiList) == "table" then
        for _, g in ipairs(guiList) do
            pcall(function()
                if g and g.Destroy then g:Destroy() end
            end)
        end
    end
end

-- Add close/hide buttons to a frame and bind hotkeys
-- options: {connections = table, guiToManage = table (list of GuiObjects), toggleKey = string, closeKey = string}
function module.addCloseControls(frame, options)
    options = options or {}
    local conns = options.connections or {}
    local guiList = options.guiToManage or {frame}
    local toggleKeyName = options.toggleKey or "Minus" -- fallback
    local closeKeyName = options.closeKey or "X"

    -- create small buttons inside frame (top-right)
    local success, err = module.safePcall(function()
        local btnContainer = Instance.new("Frame")
        btnContainer.Name = "_CloseButtons"
        btnContainer.Size = UDim2.new(0, 80, 0, 24)
        btnContainer.Position = UDim2.new(1, -86, 0, 6)
        btnContainer.BackgroundTransparency = 1
        btnContainer.Parent = frame

        local underscoreBtn = Instance.new("TextButton")
        underscoreBtn.Name = "_Underscore"
        underscoreBtn.Size = UDim2.new(0, 36, 1, 0)
        underscoreBtn.Position = UDim2.new(0, 0, 0, 0)
        underscoreBtn.Text = "_"
        underscoreBtn.Font = Enum.Font.SourceSans
        underscoreBtn.TextSize = 18
        underscoreBtn.BackgroundColor3 = Color3.fromRGB(80,80,90)
        underscoreBtn.TextColor3 = Color3.fromRGB(230,230,230)
        underscoreBtn.Parent = btnContainer
        local usCorner = Instance.new("UICorner", underscoreBtn); usCorner.CornerRadius = UDim.new(0,4)

        local closeBtn = Instance.new("TextButton")
        closeBtn.Name = "_Close"
        closeBtn.Size = UDim2.new(0, 36, 1, 0)
        closeBtn.Position = UDim2.new(0, 40, 0, 0)
        closeBtn.Text = "X"
        closeBtn.Font = Enum.Font.SourceSans
        closeBtn.TextSize = 16
        closeBtn.BackgroundColor3 = Color3.fromRGB(200,60,60)
        closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
        closeBtn.Parent = btnContainer
        local clCorner = Instance.new("UICorner", closeBtn); clCorner.CornerRadius = UDim.new(0,4)

        -- toggle (hide/show) behavior
        table.insert(conns, underscoreBtn.MouseButton1Click:Connect(function()
            for _, g in ipairs(guiList) do
                if g and g.IsA and g:IsA("GuiObject") then
                    g.Visible = not g.Visible
                end
            end
        end))

        -- full close behavior
        table.insert(conns, closeBtn.MouseButton1Click:Connect(function()
            module.cleanup(conns, guiList)
        end))

        -- hotkey bindings (map names to Enum.KeyCode if possible)
        local toggleKey = Enum.KeyCode[toggleKeyName] or Enum.KeyCode.Minus
        local closeKey = Enum.KeyCode[closeKeyName] or Enum.KeyCode.X
        table.insert(conns, UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == toggleKey then
                for _, g in ipairs(guiList) do
                    if g and g.IsA and g:IsA("GuiObject") then
                        g.Visible = not g.Visible
                    end
                end
            elseif input.KeyCode == closeKey then
                module.cleanup(conns, guiList)
            end
        end))

    end)
    if not success then
        warn("g2g4l.addCloseControls error: " .. tostring(err))
    end

    return true
end

return module
