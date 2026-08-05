-- main.lua
-- Draggable GUI + Close + Player ESP (name / health / auto-detect stamina)
-- Usage: paste & run. Unload with _G.SIMPLE_GUI_DRAG_UNLOAD()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then warn("No LocalPlayer") return end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
local parent = PlayerGui or game:GetService("CoreGui")

-- cleanup previous
pcall(function()
    local old = parent:FindFirstChild("SimpleDraggableGUI")
    if old then old:Destroy() end
end)

-- connection registry
local connections = {}
local function reg(c) if c then table.insert(connections, c) end return c end
local function disconnectAll()
    for i = #connections, 1, -1 do
        local c = connections[i]
        pcall(function()
            if typeof(c) == "RBXScriptConnection" then c:Disconnect()
            elseif type(c) == "table" and c.Disconnect then c:Disconnect()
            end
        end)
        connections[i] = nil
    end
end

-- ESP state
local ESP_ENABLED = false
local ESP_DISTANCE = 200
local espFolders = {} -- player -> folder
local selectedStaminaSource = nil -- {type="Attribute"| "Instance", ref=instance, path=string}

local function safeDestroy(obj)
    if obj and obj.Parent then pcall(function() obj:Destroy() end) end
end

-- UTIL: collect numeric candidates from common places
local function collectCandidates()
    local list = {}
    local function push(info)
        table.insert(list, info)
    end
    local function tryCollectFromParent(root, prefix)
        if not root then return end
        for _,inst in ipairs(root:GetDescendants()) do
            if inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("DoubleConstrainedValue") then
                push({kind="Instance", inst=inst, name = prefix..inst:GetFullName(), get = function() return inst.Value end})
            end
            -- attributes on Instances (numeric)
            if inst and inst.GetAttributes then
                local atts = inst:GetAttributes()
                for k,v in pairs(atts) do
                    if type(v) == "number" then
                        push({kind="Attribute", inst=inst, attr = k, name = prefix..inst:GetFullName().."@"..k, get = function() return inst:GetAttribute(k) end})
                    end
                end
            end
        end
    end
    -- character + humanoid
    if LocalPlayer.Character then
        tryCollectFromParent(LocalPlayer.Character, "MyChar:")
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then tryCollectFromParent(hum, "MyHum:") end
    end
    -- Player top-level (leaderstats etc)
    tryCollectFromParent(LocalPlayer, "Player:")
    -- PlayerGui and PlayerScripts
    if PlayerGui then tryCollectFromParent(PlayerGui, "PlayerGui:") end
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    if ps then tryCollectFromParent(ps, "PlayerScripts:") end
    -- ReplicatedStorage (client-accessible shared)
    pcall(function() tryCollectFromParent(ReplicatedStorage, "ReplicatedStorage:") end)
    -- also search other players characters/humanoids for instance-type candidates (not attributes)
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl.Character then
            tryCollectFromParent(pl.Character, pl.Name..":")
            local hum = pl.Character:FindFirstChildOfClass("Humanoid")
            if hum then tryCollectFromParent(hum, pl.Name.."Hum:") end
        end
    end
    -- dedupe by name
    local seen = {}
    local out = {}
    for _,c in ipairs(list) do
        if c.name and not seen[c.name] then
            seen[c.name] = true
            table.insert(out, c)
        end
    end
    return out
end

-- Auto-detect algorithm:
local function autodetectStamina(samples, duration, onProgress)
    samples = samples or 28
    duration = duration or 4
    local candidates = collectCandidates()
    if #candidates == 0 then return nil, "no_candidates" end
    local dt = duration / samples
    local data = {}
    for i,c in ipairs(candidates) do
        data[i] = {c=c, vals={}}
    end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local speeds = {}
    for s=1,samples do
        local sp = hum and hum.WalkSpeed or nil
        table.insert(speeds, sp)
        for i,entry in ipairs(data) do
            local ok, v = pcall(entry.c.get)
            if not ok then v = nil end
            table.insert(entry.vals, v)
        end
        if onProgress then onProgress(s / samples) end
        task.wait(dt)
    end
    local function mean(t)
        local c = 0 local sum = 0
        for _,v in ipairs(t) do if type(v) == "number" then sum = sum + v; c = c + 1 end end
        if c == 0 then return nil end
        return sum / c
    end
    local function variance(t, m)
        m = m or mean(t)
        if not m then return nil end
        local c = 0; local s = 0
        for _,v in ipairs(t) do
            if type(v) == "number" then
                s = s + (v - m)*(v - m)
                c = c + 1
            end
        end
        if c <= 1 then return 0 end
        return s / (c - 1)
    end
    local function range(t)
        local amin, amax = nil, nil
        for _,v in ipairs(t) do if type(v) == "number" then if amin == nil or v < amin then amin = v end if amax == nil or v > amax then amax = v end end end
        if amin == nil then return nil end
        return amax - amin
    end
    local function corrcoef(a,b)
        if not a or not b then return 0 end
        local ma = mean(a); local mb = mean(b)
        if not ma or not mb then return 0 end
        local num = 0; local da = 0; local db = 0; local n=0
        for i=1,math.min(#a,#b) do
            local ai=a[i]; local bi=b[i]
            if type(ai)=="number" and type(bi)=="number" then
                num = num + (ai-ma)*(bi-mb)
                da = da + (ai-ma)*(ai-ma)
                db = db + (bi-mb)*(bi-mb)
                n = n + 1
            end
        end
        if n==0 then return 0 end
        local denom = math.sqrt(da*db)
        if denom == 0 then return 0 end
        return num/denom
    end

    local results = {}
    for i,entry in ipairs(data) do
        local vals = entry.vals
        local m = mean(vals)
        local v = variance(vals, m) or 0
        local r = range(vals) or 0
        local score = r + math.sqrt(v)
        local speedCorr = 0
        if hum then
            local sc = corrcoef(vals, speeds)
            speedCorr = sc
            score = score + ( -sc ) * 10
        end
        results[i] = {candidate = entry.c, mean = m, var = v, range = r, score = score, corr = speedCorr}
    end
    table.sort(results, function(a,b) return a.score > b.score end)
    local best = results[1]
    if best and ((best.range and best.range > 0.5) or (best.var and best.var > 0.1) or (best.corr and math.abs(best.corr) > 0.25)) then
        return best.candidate, results
    end
    return nil, results
end

-- Stamina reading wrapper (using selectedStaminaSource if present)
local function readStaminaValueForPlayer(pl)
    if not pl or not pl.Character then return nil end
    if selectedStaminaSource then
        if selectedStaminaSource.kind == "Attribute" and selectedStaminaSource.inst and selectedStaminaSource.attr then
            local inst = selectedStaminaSource.inst
            if inst and inst.Parent then
                return inst:GetAttribute(selectedStaminaSource.attr)
            end
        elseif selectedStaminaSource.kind == "Instance" and selectedStaminaSource.inst then
            local inst = selectedStaminaSource.inst
            if inst and inst.Parent and inst.Value ~= nil then
                return inst.Value
            end
        elseif selectedStaminaSource.kind == "PlayerScoped" and selectedStaminaSource.name then
            local ch = pl.Character
            if ch then
                local target = ch:FindFirstChild(selectedStaminaSource.name) or (ch:FindFirstChildOfClass("Humanoid") and ch:FindFirstChildOfClass("Humanoid"):FindFirstChild(selectedStaminaSource.name))
                if target and target.Value ~= nil then return target.Value end
            end
        end
    end
    local candidates = {"Stamina","stamina","Energy","energy","Sprint","sprint","Stam","stam"}
    local ch = pl.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum then
        local a = hum:GetAttribute("Stamina") or hum:GetAttribute("stamina")
        if type(a) == "number" then return a end
    end
    if ch then
        for _,name in ipairs(candidates) do
            local v = ch:FindFirstChild(name) or (hum and hum:FindFirstChild(name))
            if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
                return v.Value
            end
        end
    end
    local v = pl:FindFirstChild("Stamina") or pl:FindFirstChild("stamina")
    if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return v.Value end
    return nil
end

-- ESP create/remove
local function createESPForPlayer(pl)
    if not pl or not pl.Character then return end
    if espFolders[pl] then return end
    local ch = pl.Character
    local folder = Instance.new("Folder")
    folder.Name = "GARA_ESP"
    folder.Parent = ch
    espFolders[pl] = folder

    local head = ch:FindFirstChild("Head") or ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("HumanoidRootPart")
    local adornee = head or ch:FindFirstChildWhichIsA("BasePart")
    local bg = Instance.new("BillboardGui")
    bg.Name = "GaraESP_Billboard"
    bg.Adornee = adornee
    bg.Size = UDim2.new(0,160,0,60)
    bg.StudsOffset = Vector3.new(0, 2.4, 0)
    bg.AlwaysOnTop = true
    bg.Parent = folder

    local frame = Instance.new("Frame", bg)
    frame.Size = UDim2.new(1,0,1,0)
    frame.BackgroundTransparency = 0.4
    frame.BackgroundColor3 = Color3.fromRGB(10,10,10)
    frame.BorderSizePixel = 0
    local cr = Instance.new("UICorner", frame)
    cr.CornerRadius = UDim.new(0,6)

    local nameLabel = Instance.new("TextLabel", frame)
    nameLabel.Size = UDim2.new(1,-8,0,18)
    nameLabel.Position = UDim2.new(0,4,0,2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = pl.Name
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.TextSize = 14
    nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left

    local hpLabel = Instance.new("TextLabel", frame)
    hpLabel.Size = UDim2.new(1,-8,0,16)
    hpLabel.Position = UDim2.new(0,4,0,22)
    hpLabel.BackgroundTransparency = 1
    hpLabel.Text = "HP: ?"
    hpLabel.Font = Enum.Font.SourceSans
    hpLabel.TextSize = 13
    hpLabel.TextColor3 = Color3.fromRGB(200,200,200)
    hpLabel.TextXAlignment = Enum.TextXAlignment.Left

    local stamLabel = Instance.new("TextLabel", frame)
    stamLabel.Size = UDim2.new(1,-8,0,16)
    stamLabel.Position = UDim2.new(0,4,0,38)
    stamLabel.BackgroundTransparency = 1
    stamLabel.Text = "Stamina: ?"
    stamLabel.Font = Enum.Font.SourceSans
    stamLabel.TextSize = 13
    stamLabel.TextColor3 = Color3.fromRGB(200,200,200)
    stamLabel.TextXAlignment = Enum.TextXAlignment.Left

    folder:SetAttribute("nameLabel", true)
    folder:SetAttribute("hpLabel", true)
    folder:SetAttribute("stamLabel", true)
end

local function removeESPForPlayer(pl)
    if not pl then return end
    local f = espFolders[pl]
    if f and f.Parent then pcall(function() f:Destroy() end) end
    espFolders[pl] = nil
end

-- Build GUI (draggable + controls + detect button)
local SG = Instance.new("ScreenGui")
SG.Name = "SimpleDraggableGUI"
SG.ResetOnSpawn = false
SG.Parent = parent

local Main = Instance.new("Frame", SG)
Main.Name = "Main"
Main.Size = UDim2.new(0, 400, 0, 240)
Main.Position = UDim2.new(0.5, -200, 0.5, -120)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Color3.fromRGB(18,18,18)
Main.BorderSizePixel = 0
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

-- Title bar and drag capture
local TitleBar = Instance.new("Frame", Main)
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.Position = UDim2.new(0, 0, 0, 0)
TitleBar.BackgroundColor3 = Color3.fromRGB(28,28,28)
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 8)
local DragBtn = Instance.new("TextButton", TitleBar)
DragBtn.Size = UDim2.new(1, 1, 1, 0)
DragBtn.BackgroundTransparency = 1
DragBtn.AutoButtonColor = false
DragBtn.Text = ""
local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size = UDim2.new(0, 40, 0, 24)
CloseBtn.Position = UDim2.new(1, -46, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(170,20,20)
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.Text = "X"
CloseBtn.TextSize = 18
CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0,6)
local Title = Instance.new("TextLabel", TitleBar)
Title.Size = UDim2.new(1, -12 - 46, 1, 0)
Title.Position = UDim2.new(0, 8, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "GARA - ESP (with stamina detection)"
Title.Font = Enum.Font.SourceSansSemibold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(230,230,230)
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Controls area
local controls = Instance.new("Frame", Main)
controls.Size = UDim2.new(1, -24, 0, 92)
controls.Position = UDim2.new(0, 12, 0, 44)
controls.BackgroundTransparency = 1

local function makeRow(parent, y, labelText)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1,0,0,28)
    row.Position = UDim2.new(0,0,0, y)
    row.BackgroundTransparency = 1
    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.5,0,1,0)
    label.Position = UDim2.new(0,0,0,0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.Font = Enum.Font.SourceSansSemibold
    label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(220,220,220)
    label.TextXAlignment = Enum.TextXAlignment.Left
    return row, label
end

local row1 = makeRow(controls, 0, "Player ESP")
local toggleESP = Instance.new("TextButton", row1)
toggleESP.Size = UDim2.new(0, 60, 0, 22)
toggleESP.Position = UDim2.new(1, -70, 0, 3)
toggleESP.Text = "OFF"
toggleESP.Font = Enum.Font.SourceSansBold
toggleESP.TextSize = 14
toggleESP.BackgroundColor3 = Color3.fromRGB(60,60,60)
toggleESP.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", toggleESP).CornerRadius = UDim.new(0,6)

local detectBtn = Instance.new("TextButton", row1)
detectBtn.Size = UDim2.new(0, 90, 0, 22)
detectBtn.Position = UDim2.new(1, -150, 0, 3)
detectBtn.Text = "Detect Stamina"
detectBtn.Font = Enum.Font.SourceSansBold
detectBtn.TextSize = 13
detectBtn.BackgroundColor3 = Color3.fromRGB(70,70,70)
detectBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", detectBtn).CornerRadius = UDim.new(0,6)

local row2 = makeRow(controls, 34, "Distance")
local distLabel = Instance.new("TextLabel", row2)
distLabel.Size = UDim2.new(0, 80, 1, 0)
distLabel.Position = UDim2.new(1, -150, 0, 0)
distLabel.BackgroundTransparency = 1
distLabel.Text = tostring(ESP_DISTANCE).." studs"
distLabel.Font = Enum.Font.SourceSans
distLabel.TextSize = 13
distLabel.TextColor3 = Color3.fromRGB(200,200,200)
distLabel.TextXAlignment = Enum.TextXAlignment.Right

local decBtn = Instance.new("TextButton", row2)
decBtn.Size = UDim2.new(0, 28, 0, 22)
decBtn.Position = UDim2.new(1, -116, 0, 3)
decBtn.Text = "-"
decBtn.Font = Enum.Font.SourceSansBold
decBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
decBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", decBtn).CornerRadius = UDim.new(0,6)

local incBtn = Instance.new("TextButton", row2)
incBtn.Size = UDim2.new(0, 28, 0, 22)
incBtn.Position = UDim2.new(1, -82, 0, 3)
incBtn.Text = "+"
incBtn.Font = Enum.Font.SourceSansBold
incBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
incBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", incBtn).CornerRadius = UDim.new(0,6)

-- status & candidates display area
local status = Instance.new("TextLabel", Main)
status.Size = UDim2.new(1, -24, 0, 60)
status.Position = UDim2.new(0, 12, 0, 148)
status.BackgroundTransparency = 1
status.Text = "ESP: OFF\nDistance: "..tostring(ESP_DISTANCE)
status.Font = Enum.Font.SourceSans
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(200,200,200)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true

local candList = Instance.new("Frame", Main)
candList.Size = UDim2.new(1, -24, 0, 40)
candList.Position = UDim2.new(0, 12, 0, 208)
candList.BackgroundTransparency = 1

-- Draggable logic (capture overlay)
do
    local dragging = false
    local dragInput = nil
    local dragStart = Vector2.new()
    local startPos = Main.Position

    local function getMousePos()
        local ok, pos = pcall(function() return UserInputService:GetMouseLocation() end)
        if ok and pos then return pos end
        return Vector2.new()
    end

    reg(DragBtn.MouseButton1Down:Connect(function()
        dragging = true
        dragInput = Enum.UserInputType.MouseMovement
        dragStart = getMousePos()
        startPos = Main.Position
    end))
    reg(DragBtn.MouseButton1Up:Connect(function()
        dragging = false
        dragInput = nil
    end))
    reg(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end))
    reg(TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = input.Position
            startPos = Main.Position
            reg(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end))
        end
    end))
    reg(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local current
        if input.UserInputType == Enum.UserInputType.MouseMovement then current = getMousePos()
        elseif input.UserInputType == Enum.UserInputType.Touch then current = input.Position
        end
        if not current then return end
        local delta = current - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end))
end

-- Close / unload
reg(CloseBtn.MouseButton1Click:Connect(function()
    if _G.SIMPLE_GUI_DRAG_UNLOAD then
        pcall(_G.SIMPLE_GUI_DRAG_UNLOAD)
    else
        pcall(function() if SG and SG.Parent then SG:Destroy() end end)
        disconnectAll()
    end
end))

-- toggle and distance buttons
reg(toggleESP.MouseButton1Click:Connect(function()
    ESP_ENABLED = not ESP_ENABLED
    toggleESP.Text = ESP_ENABLED and "ON" or "OFF"
    status.Text = (ESP_ENABLED and "ESP: ON\n" or "ESP: OFF\n").. "Distance: "..tostring(ESP_DISTANCE)
    if not ESP_ENABLED then
        for pl,_ in pairs(espFolders) do removeESPForPlayer(pl) end
    else
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local myRoot = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Torso") or LocalPlayer.Character:FindFirstChild("UpperTorso"))
                if myRoot and pl.Character then
                    local otherRoot = pl.Character:FindFirstChild("HumanoidRootPart") or pl.Character:FindFirstChild("Torso") or pl.Character:FindFirstChild("UpperTorso")
                    if otherRoot and (otherRoot.Position - myRoot.Position).Magnitude <= ESP_DISTANCE then
                        pcall(function() createESPForPlayer(pl) end)
                    end
                end
            end
        end
    end
end))

reg(decBtn.MouseButton1Click:Connect(function()
    ESP_DISTANCE = math.max(50, ESP_DISTANCE - 50)
    distLabel.Text = tostring(ESP_DISTANCE).." studs"
    status.Text = (ESP_ENABLED and "ESP: ON\n" or "ESP: OFF\n").. "Distance: "..tostring(ESP_DISTANCE)
end))
reg(incBtn.MouseButton1Click:Connect(function()
    ESP_DISTANCE = math.min(2000, ESP_DISTANCE + 50)
    distLabel.Text = tostring(ESP_DISTANCE).." studs"
    status.Text = (ESP_ENABLED and "ESP: ON\n" or "ESP: OFF\n").. "Distance: "..tostring(ESP_DISTANCE)
end))

-- detect button: runs autodetect, shows progress, then selects best candidate or lists choices
local detecting = false
reg(detectBtn.MouseButton1Click:Connect(function()
    if detecting then return end
    detecting = true
    detectBtn.Text = "Detecting..."
    status.Text = "Please sprint/perform action to change stamina for ~4s. If you cannot, cancel and pick manual."
    task.spawn(function()
        local candidate, results = autodetectStamina(28, 4, function(progress)
            detectBtn.Text = string.format("Detecting (%.0f%%)", progress*100)
        end)
        detecting = false
        detectBtn.Text = "Detect Stamina"
        if type(candidate) == "table" then
            selectedStaminaSource = candidate
            status.Text = "Auto-detected stamina source: "..(candidate.name or "unknown")
        else
            status.Text = "Auto-detect did not find confident source; showing candidates (top 6). Click one to select."
            for _,c in ipairs(candList:GetChildren()) do c:Destroy() end
            local resultsTable = results or {}
            local max = math.min(6, #resultsTable)
            for i=1,max do
                local r = resultsTable[i]
                local b = Instance.new("TextButton", candList)
                b.Size = UDim2.new(0, math.floor((Main.AbsoluteSize.X - 40) / max) - 4, 1, 0)
                b.Position = UDim2.new((i-1)/max, 0, 0, 0)
                b.Text = (r.candidate and r.candidate.name) or ("cand"..i)
                b.Font = Enum.Font.SourceSans
                b.TextSize = 12
                b.BackgroundColor3 = Color3.fromRGB(60,60,60)
                b.TextColor3 = Color3.fromRGB(255,255,255)
                Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
                b.MouseButton1Click:Connect(function()
                    if r and r.candidate then
                        selectedStaminaSource = r.candidate
                        status.Text = "Selected stamina source: "..(r.candidate.name or "unknown")
                        for _,c in ipairs(candList:GetChildren()) do c:Destroy() end
                    end
                end)
            end
        end
    end)
end))

-- player/character events to create ESP when appropriate
reg(Players.PlayerAdded:Connect(function(pl)
    reg(pl.CharacterAdded:Connect(function()
        if ESP_ENABLED then task.wait(0.2); if pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (pl.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            if dist <= ESP_DISTANCE then pcall(function() createESPForPlayer(pl) end)
            end
        end
    end))
end))

reg(Players.PlayerRemoving:Connect(function(pl) removeESPForPlayer(pl) end))

-- heartbeat: culling & label updates (stamina read from selectedStaminaSource or fallback)
reg(RunService.Heartbeat:Connect(function()
    if not ESP_ENABLED then return end
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local otherRoot = pl.Character:FindFirstChild("HumanoidRootPart") or pl.Character:FindFirstChild("Torso") or pl.Character:FindFirstChild("UpperTorso")
            if otherRoot then
                local dist = (otherRoot.Position - myRoot.Position).Magnitude
                if dist <= ESP_DISTANCE then
                    if not espFolders[pl] then pcall(function() createESPForPlayer(pl) end) end
                    local f = espFolders[pl]
                    if f and f.Parent then
                        local bg = f:FindFirstChild("GaraESP_Billboard")
                        if bg then
                            local frame = bg:FindFirstChildOfClass("Frame")
                            if frame then
                                local children = {}
                                for _,c in ipairs(frame:GetChildren()) do if c:IsA("TextLabel") then table.insert(children, c) end end
                                local nameL = children[1]; local hpL = children[2]; local stamL = children[3]
                                if nameL then nameL.Text = pl.Name end
                                local hum = pl.Character:FindFirstChildOfClass("Humanoid")
                                if hpL and hum then
                                    local hp = math.floor(hum.Health + 0.5)
                                    local mh = math.floor(hum.MaxHealth + 0.5)
                                    hpL.Text = "HP: "..tostring(hp).."/"..tostring(mh)
                                end
                                if stamL then
                                    local s = readStaminaValueForPlayer(pl)
                                    if type(s) == "number" then stamL.Text = "Stamina: "..tostring(math.floor(s+0.5)) else stamL.Text = "Stamina: -" end
                                end
                            end
                        end
                    end
                else
                    if espFolders[pl] then pcall(function() removeESPForPlayer(pl) end) end
                end
            end
        end
    end
end))

-- Unload function
_G.SIMPLE_GUI_DRAG_UNLOAD = function()
    pcall(function()
        for pl,_ in pairs(espFolders) do removeESPForPlayer(pl) end
        safeDestroy(SG)
    end)
    disconnectAll()
    _G.SIMPLE_GUI_DRAG_UNLOAD = nil
    print("[simple_draggable_gui] Unloaded (ESP cleaned)")
end

print("[simple_draggable_gui] Loaded with improved stamina detection. Click Detect Stamina and perform sprint action while it samples (4s).")
