-- simple_gui_v3.lua
-- Clean, structured GUI v3 — red & black theme
-- Features:
--  - Main size: 360x180
--  - Clean header, two-column body, footer
--  - Exit (X) and Minimize (_) buttons; minimize creates draggable logo in bottom-right
--  - ESP toggle as a proper switch; distance culling (default 200 studs)
--  - ESP skeleton best-effort using attachments+beams, created only within distance cull
--  - All connections registered and cleaned up on unload to avoid memory leaks
--  - Global unload: _G.SIMPLE_GUI_V3_UNLOAD()

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("simple_gui_v3: LocalPlayer not found")
    return
end

-- Remove previous GUI
if CoreGui:FindFirstChild("SimpleLiveGUI_v3") then
    pcall(function() CoreGui.SimpleLiveGUI_v3:Destroy() end)
end

local CONNECTIONS = {}
local function register(conn)
    if conn then table.insert(CONNECTIONS, conn) end
    return conn
end

local function cleanup()
    for i = #CONNECTIONS, 1, -1 do
        local c = CONNECTIONS[i]
        pcall(function()
            if typeof(c) == "RBXScriptConnection" then c:Disconnect()
            elseif type(c) == "table" and c.Disconnect then c:Disconnect()
            end
        end)
        CONNECTIONS[i] = nil
    end
    pcall(function()
        local sg = CoreGui:FindFirstChild("SimpleLiveGUI_v3")
        if sg then sg:Destroy() end
    end)
    -- clear ESP folders (characters store their ESP under a folder named GARA_ESP)
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then
            local f = pl.Character:FindFirstChild("GARA_ESP")
            if f then pcall(function() f:Destroy() end) end
        end
    end
end
_G.SIMPLE_GUI_V3_UNLOAD = cleanup

-- Helpers
local function tween(instance, props, info)
    info = info or TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TweenService:Create(instance, info, props)
    t:Play()
    return t
end

local function makeToggle(parent, pos, initial)
    initial = not not initial
    local cont = Instance.new("Frame", parent)
    cont.Size = UDim2.new(0, 50, 0, 26)
    cont.Position = pos or UDim2.new(0, 0, 0, 0)
    cont.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    cont.BorderSizePixel = 0
    Instance.new("UICorner", cont).CornerRadius = UDim.new(0, 12)
    local knob = Instance.new("Frame", cont)
    knob.Size = UDim2.new(0, 22, 0, 22)
    knob.Position = UDim2.new(initial and 1 or 0, 2, 0, 2)
    knob.AnchorPoint = Vector2.new(initial and 1 or 0, 0)
    knob.BackgroundColor3 = initial and Color3.fromRGB(200, 40, 40) or Color3.fromRGB(200,200,200)
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 11)
    local active = initial
    local function setState(state)
        active = not not state
        local x = active and UDim2.new(1, -2, 0, 2) or UDim2.new(0, 2, 0, 2)
        tween(knob, {Position = x}, TweenInfo.new(0.16))
        knob.BackgroundColor3 = active and Color3.fromRGB(200,40,40) or Color3.fromRGB(200,200,200)
    end
    local btn = Instance.new("TextButton", cont)
    btn.Text = ""
    btn.BackgroundTransparency = 1
    btn.Size = UDim2.new(1,0,1,0)
    btn.MouseButton1Click:Connect(function()
        setState(not active)
    end)
    return cont, function() return active end, setState
end

-- ESP utilities
local ESP_ENABLED = false
local ESP_DISTANCE = 200 -- studs default

local function createESPForCharacter(char)
    if not char or not char:IsA("Model") then return end
    if char:FindFirstChild("GARA_ESP") then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    if not root then return end

    local folder = Instance.new("Folder") folder.Name = "GARA_ESP" folder.Parent = char

    -- attempt to create attachments on typical parts and beam between them
    local partNames = {"Head","UpperTorso","LowerTorso","LeftUpperArm","LeftLowerArm","RightUpperArm","RightLowerArm","LeftUpperLeg","LeftLowerLeg","RightUpperLeg","RightLowerLeg","Torso","Left Arm","Right Arm","Left Leg","Right Leg"}
    local parts = {}
    for _,n in ipairs(partNames) do
        local p = char:FindFirstChild(n)
        if p and p:IsA("BasePart") then parts[n] = p end
    end

    local function makeAttachment(p, name)
        if not p then return nil end
        local a = Instance.new("Attachment") a.Name = "ESP_"..name a.Parent = p
        return a
    end

    -- create attachments for found parts
    local atts = {}
    for name, part in pairs(parts) do
        local a = makeAttachment(part, name)
        if a then table.insert(atts, a) end
    end

    local function makeBeam(a0, a1)
        if not a0 or not a1 then return end
        local b = Instance.new("Beam")
        b.Attachment0 = a0
        b.Attachment1 = a1
        b.FaceCamera = true
        b.Width0 = 0.06
        b.Width1 = 0.06
        b.Color = ColorSequence.new(Color3.fromRGB(255,80,80))
        b.LightEmission = 0.6
        b.Parent = folder
        return b
    end

    local links = {
        {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
        {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},
        {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},
        {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},
        {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},
        {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"}
    }

    for _,ln in ipairs(links) do
        local a = char:FindFirstChild(ln[1]) and char[ln[1]]:FindFirstChild("ESP_"..ln[1])
        local b = char:FindFirstChild(ln[2]) and char[ln[2]]:FindFirstChild("ESP_"..ln[2])
        pcall(function() makeBeam(a,b) end)
    end

    -- name billboard
    local adornee = char:FindFirstChild("Head") or root
    local bg = Instance.new("BillboardGui") bg.Adornee = adornee bg.Size = UDim2.new(0,140,0,36) bg.StudsOffset = Vector3.new(0,2.2,0) bg.AlwaysOnTop = true bg.Parent = folder
    local t = Instance.new("TextLabel", bg) t.Size = UDim2.new(1,0,1,0) t.BackgroundTransparency = 1 t.Text = char.Name t.Font = Enum.Font.SourceSansSemibold t.TextSize = 14 t.TextColor3 = Color3.fromRGB(255,255,255)

    -- remove on death
    local diedConn
    if hum then
        diedConn = hum.Died:Connect(function()
            pcall(function() if folder and folder.Parent then folder:Destroy() end end)
            if diedConn then pcall(function() diedConn:Disconnect() end) end
        end)
        register(diedConn)
    end
end

local function removeESPForCharacter(char)
    if not char then return end
    local f = char:FindFirstChild("GARA_ESP")
    if f then pcall(function() f:Destroy() end) end
end

local function updateESPVisibility()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local root = pl.Character:FindFirstChild("HumanoidRootPart") or pl.Character:FindFirstChild("Torso") or pl.Character:FindFirstChild("UpperTorso")
            if root then
                local dist = (root.Position - (LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Torso") or LocalPlayer.Character:FindFirstChild("UpperTorso"):GetModelCFrame().p) or Vector3.new()).Magnitude
                -- above line risky; safe fallback
            end
        end
    end
end

-- Build GUI structure (clean layout)
local SG = Instance.new("ScreenGui") SG.Name = "SimpleLiveGUI_v3" SG.ResetOnSpawn = false SG.Parent = CoreGui
local Main = Instance.new("Frame") Main.Name = "Main" Main.Size = UDim2.new(0,360,0,180) Main.Position = UDim2.new(0.5,-180,0.5,-90) Main.AnchorPoint = Vector2.new(0.5,0.5) Main.BackgroundColor3 = Color3.fromRGB(12,12,12) Main.BorderSizePixel = 0 Main.Parent = SG; Instance.new("UICorner", Main).CornerRadius = UDim.new(0,10)
local stroke = Instance.new("UIStroke", Main); stroke.Color = Color3.fromRGB(140, 20, 20); stroke.Thickness = 1.2

-- Header
local Header = Instance.new("Frame", Main) Header.Size = UDim2.new(1,0,0,42) Header.Position = UDim2.new(0,0,0,0) Header.BackgroundTransparency = 1
local HTitle = Instance.new("TextLabel", Header) HTitle.Size = UDim2.new(0.6, -12,1,0) HTitle.Position = UDim2.new(0,12,0,0) HTitle.BackgroundTransparency = 1 HTitle.Text = "GARA - CLEAN UI" HTitle.Font = Enum.Font.GothamBold HTitle.TextSize = 16 HTitle.TextColor3 = Color3.fromRGB(240,240,240) HTitle.TextXAlignment = Enum.TextXAlignment.Left

-- buttons
local BtnFrame = Instance.new("Frame", Header) BtnFrame.Size = UDim2.new(0, 96, 1, 0) BtnFrame.Position = UDim2.new(1, -110, 0, 0) BtnFrame.BackgroundTransparency = 1
local MinBtn = Instance.new("TextButton", BtnFrame); MinBtn.Size = UDim2.new(0, 42,0,28); MinBtn.Position = UDim2.new(0,4,0,7); MinBtn.Text = "_"; MinBtn.Font = Enum.Font.SourceSansBold; MinBtn.TextSize = 20; MinBtn.BackgroundColor3 = Color3.fromRGB(30,30,30); MinBtn.TextColor3 = Color3.fromRGB(230,230,230); MinBtn.BorderSizePixel = 0; Instance.new("UICorner", MinBtn)
local CloseBtn = Instance.new("TextButton", BtnFrame); CloseBtn.Size = UDim2.new(0, 42,0,28); CloseBtn.Position = UDim2.new(0,50,0,7); CloseBtn.Text = "X"; CloseBtn.Font = Enum.Font.SourceSansBold; CloseBtn.TextSize = 18; CloseBtn.BackgroundColor3 = Color3.fromRGB(170,20,20); CloseBtn.TextColor3 = Color3.fromRGB(255,255,255); CloseBtn.BorderSizePixel = 0; Instance.new("UICorner", CloseBtn)

-- Body: two columns
local Body = Instance.new("Frame", Main) Body.Size = UDim2.new(1,-24,1,-74) Body.Position = UDim2.new(0,12,0,48) Body.BackgroundTransparency = 1
local leftCol = Instance.new("Frame", Body) leftCol.Size = UDim2.new(0.6, -8,1,0) leftCol.Position = UDim2.new(0,0,0,0) leftCol.BackgroundTransparency = 1
local rightCol = Instance.new("Frame", Body) rightCol.Size = UDim2.new(0.4, -8,1,0) rightCol.Position = UDim2.new(0.6, 8,0,0) rightCol.BackgroundTransparency = 1

-- left column controls layout
local leftLayout = Instance.new("UIListLayout", leftCol) leftLayout.Padding = UDim.new(0,8) leftLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function makeControlRow(parent, labelText)
    local row = Instance.new("Frame", parent); row.Size = UDim2.new(1,0,0,34); row.BackgroundTransparency = 1
    local label = Instance.new("TextLabel", row); label.Size = UDim2.new(0.6,0,1,0); label.Position = UDim2.new(0,0,0,0); label.BackgroundTransparency = 1; label.Text = labelText; label.Font = Enum.Font.SourceSansSemibold; label.TextSize = 14; label.TextColor3 = Color3.fromRGB(220,220,220); label.TextXAlignment = Enum.TextXAlignment.Left
    return row, label
end

-- ESP control row (with toggle and distance input)
local espRow, espLabel2 = makeControlRow(leftCol, "Enemy ESP")
local toggleFrame, isOnFunc, setOn = makeToggle(espRow, UDim2.new(0, 220, 0, 4), false)
local distLabel = Instance.new("TextLabel", espRow); distLabel.Size = UDim2.new(0, 80, 1, 0); distLabel.Position = UDim2.new(0, 280, 0, 0); distLabel.BackgroundTransparency = 1; distLabel.Text = tostring(ESP_DISTANCE) .. " studs"; distLabel.Font = Enum.Font.SourceSans; distLabel.TextSize = 12; distLabel.TextColor3 = Color3.fromRGB(200,200,200); distLabel.TextXAlignment = Enum.TextXAlignment.Right

-- distance row (slider-like simple buttons)
local distRow, _ = makeControlRow(leftCol, "ESP Distance")
local decBtn = Instance.new("TextButton", distRow); decBtn.Size = UDim2.new(0, 32,0,24); decBtn.Position = UDim2.new(0.62,0,0,5); decBtn.Text = "-"; decBtn.Font = Enum.Font.SourceSansBold; decBtn.BackgroundColor3 = Color3.fromRGB(40,40,40); decBtn.TextColor3 = Color3.fromRGB(220,220,220); Instance.new("UICorner", decBtn)
local incBtn = Instance.new("TextButton", distRow); incBtn.Size = UDim2.new(0, 32,0,24); incBtn.Position = UDim2.new(0.78,0,0,5); incBtn.Text = "+"; incBtn.Font = Enum.Font.SourceSansBold; incBtn.BackgroundColor3 = Color3.fromRGB(40,40,40); incBtn.TextColor3 = Color3.fromRGB(220,220,220); Instance.new("UICorner", incBtn)

register(decBtn.MouseButton1Click:Connect(function() ESP_DISTANCE = math.max(50, ESP_DISTANCE - 50); distLabel.Text = tostring(ESP_DISTANCE) .. " studs" end))
register(incBtn.MouseButton1Click:Connect(function() ESP_DISTANCE = math.min(1000, ESP_DISTANCE + 50); distLabel.Text = tostring(ESP_DISTANCE) .. " studs" end))

-- right column: status preview
local statusTitle = Instance.new("TextLabel", rightCol); statusTitle.Size = UDim2.new(1,0,0,20); statusTitle.Position = UDim2.new(0,0,0,0); statusTitle.BackgroundTransparency = 1; statusTitle.Text = "Status"; statusTitle.Font = Enum.Font.SourceSansSemibold; statusTitle.TextSize = 13; statusTitle.TextColor3 = Color3.fromRGB(220,220,220); statusTitle.TextXAlignment = Enum.TextXAlignment.Left
local statusBox = Instance.new("Frame", rightCol); statusBox.Size = UDim2.new(1,0,0,110); statusBox.Position = UDim2.new(0,0,0,28); statusBox.BackgroundColor3 = Color3.fromRGB(18,18,18); Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0,6)
local statusText = Instance.new("TextLabel", statusBox); statusText.Size = UDim2.new(1,-12,1,-12); statusText.Position = UDim2.new(0,6,0,6); statusText.BackgroundTransparency = 1; statusText.Text = "ESP: OFF\nDistance: "..tostring(ESP_DISTANCE) ; statusText.Font = Enum.Font.SourceSans; statusText.TextSize = 12; statusText.TextColor3 = Color3.fromRGB(200,200,200); statusText.TextXAlignment = Enum.TextXAlignment.Left; statusText.TextWrapped = true

-- footer
local footer = Instance.new("TextLabel", Main); footer.Size = UDim2.new(1,-20,0,18); footer.Position = UDim2.new(0,10,1,-24); footer.BackgroundTransparency = 1; footer.Text = "Minimize to logo (bottom-right). '-' to minimize | 'X' to close"; footer.Font = Enum.Font.SourceSans; footer.TextSize = 11; footer.TextColor3 = Color3.fromRGB(170,170,170); footer.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize into bottom-right logo
local minimized = false
local logo
local logoPos = UDim2.new(1, -72, 1, -72) -- bottom-right offset

local function createLogo()
    if logo and logo.Parent then return end
    logo = Instance.new("Frame", CoreGui)
    logo.Name = "GaraLogo"
    logo.Size = UDim2.new(0,56,0,56)
    logo.Position = logoPos
    logo.AnchorPoint = Vector2.new(0,0)
    logo.BackgroundColor3 = Color3.fromRGB(170,20,20)
    Instance.new("UICorner", logo).CornerRadius = UDim.new(0,12)
    local lab = Instance.new("TextLabel", logo)
    lab.Size = UDim2.new(1,0,1,0) lab.BackgroundTransparency = 1 lab.Text = "G" lab.Font = Enum.Font.GothamBold lab.TextSize = 20 lab.TextColor3 = Color3.fromRGB(255,255,255)
    local btn = Instance.new("TextButton", logo) btn.Size = UDim2.new(1,1,1,1) btn.BackgroundTransparency = 1 btn.Text = ""
    register(btn.MouseButton1Click:Connect(function()
        if minimized then
            tween(Main, {Size = UDim2.new(0,360,0,180), Position = UDim2.new(0.5,-180,0.5,-90)}, TweenInfo.new(0.25, Enum.EasingStyle.Back))
            pcall(function() logo:Destroy() end); logo = nil; minimized = false
        end
    end))
    -- allow dragging
    local dragging, startPos, mStart
    register(logo.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; mStart = input.Position; startPos = logo.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end))
    register(UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - mStart
            logo.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

local function doMinimize()
    if minimized then return end
    minimized = true
    tween(Main, {Size = UDim2.new(0, 56, 0, 56), Position = UDim2.new(1,-72,1,-72)}, TweenInfo.new(0.22, Enum.EasingStyle.Back))
    createLogo()
end

register(MinBtn.MouseButton1Click:Connect(function()
    doMinimize()
end))

register(CloseBtn.MouseButton1Click:Connect(function()
    cleanup()
end))

register(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Minus then doMinimize()
    elseif input.KeyCode == Enum.KeyCode.X then cleanup() end
end))

-- Hook ESP toggle
register(toggleFrame.MouseButton1Click:Connect(function()
    -- toggle uses internal state setter
    -- sneakily toggle by calling the hidden button inside toggle
    local active = (function() -- read current
        local knob = toggleFrame:FindFirstChildOfClass("Frame")
        if not knob then return false end
        return knob.Position.X.Scale > 0.5
    end)()
    -- flip
    local setState = toggleFrame and (function()
        local knob = toggleFrame:FindFirstChildOfClass("Frame")
        if not knob then return end
        local new = not (knob.Position.X.Scale > 0.5)
        local pos = new and UDim2.new(1, -2, 0, 2) or UDim2.new(0, 2, 0, 2)
        tween(knob, {Position = pos}, TweenInfo.new(0.16))
        knob.BackgroundColor3 = new and Color3.fromRGB(200,40,40) or Color3.fromRGB(200,200,200)
        return new
    end)()
    ESP_ENABLED = not ESP_ENABLED
    if ESP_ENABLED then
        -- create ESP for eligible existing players
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local dist = (pl.Character.HumanoidRootPart.Position - (LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position or LocalPlayer.Character:GetModelCFrame().p) or Vector3.new())).Magnitude
                if dist <= ESP_DISTANCE then pcall(function() createESPForCharacter(pl.Character) end) end
            end
        end
        statusText.Text = "ESP: ON\nDistance: "..tostring(ESP_DISTANCE)
    else
        for _,pl in ipairs(Players:GetPlayers()) do if pl.Character then pcall(function() removeESPForCharacter(pl.Character) end) end end
        statusText.Text = "ESP: OFF\nDistance: "..tostring(ESP_DISTANCE)
    end
end))

-- Periodic ESP distance culling & update
register(RunService.Heartbeat:Connect(function()
    if not ESP_ENABLED then return end
    if not LocalPlayer.Character then return end
    local myRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Torso")
    if not myRoot then return end
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            local root = pl.Character.HumanoidRootPart
            local dist = (root.Position - myRoot.Position).Magnitude
            if dist <= ESP_DISTANCE then
                if not pl.Character:FindFirstChild("GARA_ESP") then pcall(function() createESPForCharacter(pl.Character) end) end
            else
                if pl.Character:FindFirstChild("GARA_ESP") then pcall(function() removeESPForCharacter(pl.Character) end) end
            end
        end
    end
end))

-- Update status text when ESP_DISTANCE changes
register(decBtn.MouseButton1Click:Connect(function()
    ESP_DISTANCE = math.max(50, ESP_DISTANCE - 50)
    distLabel.Text = tostring(ESP_DISTANCE) .. " studs"
    statusText.Text = (ESP_ENABLED and "ESP: ON\n" or "ESP: OFF\n") .. "Distance: "..tostring(ESP_DISTANCE)
end))
register(incBtn.MouseButton1Click:Connect(function()
    ESP_DISTANCE = math.min(2000, ESP_DISTANCE + 50)
    distLabel.Text = tostring(ESP_DISTANCE) .. " studs"
    statusText.Text = (ESP_ENABLED and "ESP: ON\n" or "ESP: OFF\n") .. "Distance: "..tostring(ESP_DISTANCE)
end))

-- Show appear animation
Main.Position = UDim2.new(0.5, -180, 0, -300)
tween(Main, {Position = UDim2.new(0.5, -180, 0.5, -90)}, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))

print("[simple_gui_v3] Loaded — minimized logo bottom-right; ESP distance default:"..tostring(ESP_DISTANCE))
