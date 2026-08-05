-- simple_gui_final.lua
-- Close -> show logo image -> click logo to restore GUI
-- Unload: _G.SIMPLE_GUI_FINAL_UNLOAD()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then warn("No LocalPlayer") return end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
local ParentGui = PlayerGui or game:GetService("CoreGui")

-- Config: replace with your image asset id if you want an actual image logo
local IMAGE_ASSET_ID = "rbxassetid://128707963227656"  -- provided asset id
local LOGO_SIZE = UDim2.new(0, 56, 0, 56)
local GUI_SIZE = UDim2.new(0, 360, 0, 180)

-- Forced cleanup of any previous instances
pcall(function()
    local old = ParentGui:FindFirstChild("SimpleLiveGUI_Final")
    if old then old:Destroy() end
    local oldLogo = ParentGui:FindFirstChild("GaraLogo_Final")
    if oldLogo then oldLogo:Destroy() end
end)

local connections = {}
local function reg(conn) if conn then table.insert(connections, conn) end return conn end
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

local function safeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

-- Create main ScreenGui
local SG = Instance.new("ScreenGui")
SG.Name = "SimpleLiveGUI_Final"
SG.ResetOnSpawn = false
SG.Parent = ParentGui

-- Main frame
local Main = Instance.new("Frame", SG)
Main.Name = "Main"
Main.Size = GUI_SIZE
Main.Position = UDim2.new(0.5, -GUI_SIZE.X.Offset/2, 0.5, -GUI_SIZE.Y.Offset/2)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Color3.fromRGB(12,12,12)
Main.BorderSizePixel = 0
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", Main); stroke.Color = Color3.fromRGB(140,20,20); stroke.Thickness = 1.2

-- Header
local Header = Instance.new("Frame", Main)
Header.Size = UDim2.new(1, 0, 0, 36)
Header.Position = UDim2.new(0, 0, 0, 0)
Header.BackgroundTransparency = 1
local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, -120, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "GARA UI"
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 16
Title.TextColor3 = Color3.fromRGB(240,240,240)
Title.TextXAlignment = Enum.TextXAlignment.Left

-- Close button (will hide GUI and show logo)
local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 42, 0, 28)
CloseBtn.Position = UDim2.new(1, -54, 0, 4)
CloseBtn.AnchorPoint = Vector2.new(0, 0)
CloseBtn.BackgroundColor3 = Color3.fromRGB(170,20,20)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.TextSize = 18
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0,6)

-- Content sample (so menu has something)
local Content = Instance.new("Frame", Main)
Content.Size = UDim2.new(1, -24, 1, -70)
Content.Position = UDim2.new(0, 12, 0, 44)
Content.BackgroundTransparency = 1
local sampleLabel = Instance.new("TextLabel", Content)
sampleLabel.Size = UDim2.new(1, 0, 0, 24)
sampleLabel.Position = UDim2.new(0, 0, 0, 0)
sampleLabel.BackgroundTransparency = 1
sampleLabel.Text = "Simple menu content here"
sampleLabel.Font = Enum.Font.SourceSans
sampleLabel.TextSize = 14
sampleLabel.TextColor3 = Color3.fromRGB(220,220,220)
sampleLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Footer
local footer = Instance.new("TextLabel", Main)
footer.Size = UDim2.new(1, -20, 0, 18)
footer.Position = UDim2.new(0, 10, 1, -24)
footer.BackgroundTransparency = 1
footer.Text = "Close → becomes logo; click logo to restore GUI"
footer.Font = Enum.Font.SourceSans
footer.TextSize = 11
footer.TextColor3 = Color3.fromRGB(170,170,170)
footer.TextXAlignment = Enum.TextXAlignment.Left

-- Logo creator (bottom-right)
local logo
local function createLogo()
    if logo and logo.Parent then return logo end
    local parent = ParentGui
    logo = Instance.new("Frame")
    logo.Name = "GaraLogo_Final"
    logo.Size = LOGO_SIZE
    logo.Position = UDim2.new(1, -72, 1, -72)
    logo.AnchorPoint = Vector2.new(0, 0)
    logo.BackgroundColor3 = Color3.fromRGB(170,20,20)
    logo.BorderSizePixel = 0
    logo.Parent = parent
    local cr = Instance.new("UICorner", logo)
    cr.CornerRadius = UDim.new(0, 12)

    if IMAGE_ASSET_ID and type(IMAGE_ASSET_ID) == "string" then
        -- use image button
        local img = Instance.new("ImageButton", logo)
        img.Size = UDim2.new(1, 0, 1, 0)
        img.Position = UDim2.new(0, 0, 0, 0)
        img.BackgroundTransparency = 1
        img.Image = IMAGE_ASSET_ID
        img.ScaleType = Enum.ScaleType.Fit
        img.AutoButtonColor = false
        reg(img.MouseButton1Click:Connect(function()
            -- restore GUI
            if Main and Main.Parent then
                Main.Visible = true
                safeDestroy(logo)
                logo = nil
            end
        end))
    else
        -- fallback: text button with "(  )"
        local lbl = Instance.new("TextLabel", logo)
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "(  )"
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 18
        lbl.TextColor3 = Color3.fromRGB(255,255,255)
        local btn = Instance.new("TextButton", logo)
        btn.Size = UDim2.new(1,0,1,0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        reg(btn.MouseButton1Click:Connect(function()
            if Main and Main.Parent then
                Main.Visible = true
                safeDestroy(logo)
                logo = nil
            end
        end))
    end

    -- dragging for logo (optional)
    local dragging, startPos, mStart
    reg(logo.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mStart = input.Position
            startPos = logo.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))
    reg(UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - mStart
            logo.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))

    return logo
end

-- Close behavior: hide main and show logo
reg(CloseBtn.MouseButton1Click:Connect(function()
    -- hide main
    if Main and Main.Parent then
        Main.Visible = false
        createLogo()
    end
end))

-- Also allow keyboard 'X' to close (same behavior)
reg(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.X then
        if Main and Main.Parent and Main.Visible then
            Main.Visible = false
            createLogo()
        else
            -- if hidden and logo exists, restore
            if logo and logo.Parent then
                Main.Visible = true
                safeDestroy(logo)
                logo = nil
            end
        end
    end
end))

-- Draggable main via header
do
    local dragging, dragInput, dragStart, startPos
    reg(Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            dragInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end))
    reg(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

-- Global unload
_G.SIMPLE_GUI_FINAL_UNLOAD = function()
    pcall(function()
        safeDestroy(logo)
        safeDestroy(SG)
    end)
    disconnectAll()
    _G.SIMPLE_GUI_FINAL_UNLOAD = nil
    print("[simple_gui_final] Unloaded")
end

print("[simple_gui_final] Ready. Close -> becomes logo; click logo to restore.")
