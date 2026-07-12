-- =====================================================================
--  MINE A MOUNTAIN: UNIVERSAL SAFE AUTOMATION PANEL (GLITCH EDITION)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") 
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Main State Flags
local ProfileSettings = {
    AutoBuyActive = false,
    InstantInteractions = false,
    MultiJumpActive = false,
    NoRagdollActive = false,
    NoDamageActive = false,
    PlayerESPActive = false,
    GlitchActive = false, 
    CurrentSpeedMultiplier = 1.0,
    SlowSpeedMultiplier = 1.0,
    SpeedMode = "Fast" -- "Fast" or "Slow"
}

local maxBonusJumps = 10
local jumpCount = 0

-- ---------------------------------------------------------------------
--  1. ESP LOGIC
-- ---------------------------------------------------------------------

local function createESP(player)
    if player == LocalPlayer then return end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = "PlayerHighlight"
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Enabled = false
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlayerLabel"
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = false
    
    local nameLabel = Instance.new("TextLabel", billboard)
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.Text = player.Name
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextStrokeTransparency = 0
    
    local function setupChar(char)
        highlight.Parent = char
        billboard.Parent = char:WaitForChild("HumanoidRootPart")
    end
    
    player.CharacterAdded:Connect(setupChar)
    if player.Character then setupChar(player.Character) end
end

Players.PlayerAdded:Connect(createESP)
for _, p in pairs(Players:GetPlayers()) do createESP(p) end

RunService.RenderStepped:Connect(function()
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character and p.Character:FindFirstChild("PlayerHighlight") then
            p.Character.PlayerHighlight.Enabled = ProfileSettings.PlayerESPActive
            p.Character.HumanoidRootPart:FindFirstChild("PlayerLabel").Enabled = ProfileSettings.PlayerESPActive
        end
    end
end)

-- ---------------------------------------------------------------------
--  2. AUTOMATION & CORE LOGIC
-- ---------------------------------------------------------------------

local BUY_BOMB_REMOTE = nil
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 3) or ReplicatedStorage:WaitForChild("Events", 3) or ReplicatedStorage

if remotesFolder then
    BUY_BOMB_REMOTE = remotesFolder:FindFirstChild("BuyBomb") or remotesFolder:FindFirstChild("PurchaseBomb")
end

local cashBombs = {"Classic Bomb", "Wind Bomb", "Ice Bomb", "Fire Bomb", "Thunder Bomb"}

task.spawn(function()
    while true do
        if ProfileSettings.AutoBuyActive and BUY_BOMB_REMOTE then
            for _, bombName in ipairs(cashBombs) do
                if not ProfileSettings.AutoBuyActive then break end
                pcall(function()
                    if BUY_BOMB_REMOTE:IsA("RemoteFunction") then
                        BUY_BOMB_REMOTE:InvokeServer(bombName)
                    else
                        BUY_BOMB_REMOTE:FireServer(bombName)
                    end
                end)
                task.wait(0.4)
            end
        end
        task.wait(3)
    end
end)

-- THE REAL 3FPS GLITCH ENGINE
local FPS = 3
local FRAME_DURATION = 1 / FPS
local lastGlobalTick = 0
local snappedCFrame = nil

local function createGhostClone(char)
    if not char then return end
    char.Archivable = true
    local clone = char:Clone()
    char.Archivable = false
    
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Transparency = 0.5
            part.Color = Color3.fromRGB(150, 150, 255)
            TweenService:Create(part, TweenInfo.new(0.3), {Transparency = 1, Size = part.Size * 0.8}):Play()
        elseif part:IsA("Decal") or part:IsA("Texture") then
            part:Destroy()
        end
    end
    
    clone.Parent = workspace
    game:GetService("Debris"):AddItem(clone, 0.3)
end

-- Global Heartbeat for Visual Ghosting (No more movement locking!)
RunService.Heartbeat:Connect(function()
    if not ProfileSettings.GlitchActive then 
        return 
    end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    if os.clock() - lastGlobalTick >= FRAME_DURATION then
        lastGlobalTick = os.clock()
        createGhostClone(char)
    end
end)

local function applyLagEffect(track)
    local lastUpdate = 0
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not track or not track.IsPlaying then 
            connection:Disconnect() 
            return 
        end
        
        if ProfileSettings.GlitchActive then
            track:AdjustSpeed(0)
            if os.clock() - lastUpdate >= FRAME_DURATION then
                local skip = 0.15 + (math.random() * 0.1)
                track.TimePosition = track.TimePosition + skip
                lastUpdate = os.clock()
            end
        else
            track:AdjustSpeed(1.0)
        end
    end)
end

-- Hook into Humanoid for Animations and Speed
local function ManageCharacter(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoid or not rootPart then return end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        animator.AnimationPlayed:Connect(applyLagEffect)
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            applyLagEffect(track)
        end
    end

    local speedConnection
    speedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        local targetSpeed = 16
        if ProfileSettings.SpeedMode == "Fast" then
            targetSpeed = 16 * ProfileSettings.CurrentSpeedMultiplier
        else
            targetSpeed = 16 * ProfileSettings.SlowSpeedMultiplier
        end
        
        if math.abs(humanoid.WalkSpeed - targetSpeed) > 1 then
            humanoid.WalkSpeed = targetSpeed
        end
    end)
    humanoid.WalkSpeed = 16 * (ProfileSettings.SpeedMode == "Fast" and ProfileSettings.CurrentSpeedMultiplier or ProfileSettings.SlowSpeedMultiplier)

    local platformConnection
    platformConnection = humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if ProfileSettings.NoRagdollActive and humanoid.PlatformStand then
            humanoid.PlatformStand = false
        end
    end)

    local stateConnection
    stateConnection = humanoid.StateChanged:Connect(function(_, newState)
        if ProfileSettings.NoRagdollActive and (newState == Enum.HumanoidStateType.Physics or newState == Enum.HumanoidStateType.Ragdoll or newState == Enum.HumanoidStateType.FallingDown) then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if newState == Enum.HumanoidStateType.Landed then
            jumpCount = 0
        end
    end)

    local damageConn = RunService.Heartbeat:Connect(function()
        if ProfileSettings.NoDamageActive then
            if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
                humanoid.Health = humanoid.MaxHealth
            end
        end
    end)

    humanoid.Died:Connect(function()
        if speedConnection then speedConnection:Disconnect() end
        if platformConnection then platformConnection:Disconnect() end
        if stateConnection then stateConnection:Disconnect() end
        damageConn:Disconnect()
    end)
end

if LocalPlayer and LocalPlayer.Character then ManageCharacter(LocalPlayer.Character) end
if LocalPlayer then LocalPlayer.CharacterAdded:Connect(ManageCharacter) end

ProximityPromptService.PromptShown:Connect(function(prompt)
    if ProfileSettings.InstantInteractions then
        prompt.HoldDuration = 0
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if input.KeyCode == Enum.KeyCode.Space and ProfileSettings.MultiJumpActive then
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        
        if humanoid and rootPart then
            local state = humanoid:GetState()
            if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
                if jumpCount < maxBonusJumps then
                    jumpCount = jumpCount + 1
                    rootPart.Velocity = Vector3.new(rootPart.Velocity.X, humanoid.JumpPower, rootPart.Velocity.Z)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------
--  3. GRAPHICAL USER INTERFACE
-- ---------------------------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MineAMountainPanel"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 300, 0, 400) 
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.Active = true
MainFrame.Draggable = true 
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local HeaderLabel = Instance.new("TextLabel")
HeaderLabel.Size = UDim2.new(1, 0, 0, 35)
HeaderLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
HeaderLabel.Text = "Mine A Mountain - Glitch Edition"
HeaderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
HeaderLabel.Font = Enum.Font.SourceSansBold
HeaderLabel.TextSize = 14
HeaderLabel.Parent = MainFrame
Instance.new("UICorner", HeaderLabel).CornerRadius = UDim.new(0, 8)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, 0, 1, -35)
ScrollFrame.Position = UDim2.new(0, 0, 0, 35)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 600)
ScrollFrame.ScrollBarThickness = 4
ScrollFrame.Parent = MainFrame

local function createToggle(name, positionY, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.Position = UDim2.new(0.05, 0, 0, positionY)
    Button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    Button.Text = name .. ": OFF"
    Button.TextColor3 = Color3.fromRGB(220, 80, 80)
    Button.Font = Enum.Font.SourceSans
    Button.TextSize = 14
    Button.Parent = ScrollFrame
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)

    local toggled = false
    Button.MouseButton1Click:Connect(function()
        toggled = not toggled
        Button.BackgroundColor3 = toggled and Color3.fromRGB(60, 110, 60) or Color3.fromRGB(45, 45, 45)
        Button.TextColor3 = toggled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 80, 80)
        Button.Text = name .. (toggled and ": ON" or ": OFF")
        callback(toggled)
    end)
end

local function createButton(name, positionY, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.Position = UDim2.new(0.05, 0, 0, positionY)
    Button.BackgroundColor3 = Color3.fromRGB(60, 60, 120)
    Button.Text = name
    Button.TextColor3 = Color3.fromRGB(255, 255, 255)
    Button.Parent = ScrollFrame
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)
    Button.MouseButton1Click:Connect(callback)
end

createToggle("Auto Buy Bombs", 10, function(s) ProfileSettings.AutoBuyActive = s end)
createToggle("Instant E-Mining", 50, function(s) ProfileSettings.InstantInteractions = s end)
createToggle("Infinite Multi-Jump", 90, function(s) ProfileSettings.MultiJumpActive = s end)
createToggle("No Ragdoll", 130, function(s) ProfileSettings.NoRagdollActive = s end)
createToggle("No Damage", 170, function(s) ProfileSettings.NoDamageActive = s end)
createToggle("Player ESP", 210, function(s) ProfileSettings.PlayerESPActive = s end)
createToggle("Glitch Lag FX", 250, function(s) 
    ProfileSettings.GlitchActive = s 
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local animator = LocalPlayer.Character.Humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(s and 0 or 1.0)
            end
        end
    end
end)

-- Speed Mode Selector
local ModeFrame = Instance.new("Frame")
ModeFrame.Size = UDim2.new(0.9, 0, 0, 40)
ModeFrame.Position = UDim2.new(0.05, 0, 0, 300)
ModeFrame.BackgroundTransparency = 1
ModeFrame.Parent = ScrollFrame

local FastBtn = Instance.new("TextButton", ModeFrame)
FastBtn.Size = UDim2.new(0.48, 0, 1, 0)
FastBtn.Position = UDim2.new(0, 0, 0, 0)
FastBtn.Text = "FAST MODE"
FastBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 60)
FastBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", FastBtn)

local SlowBtn = Instance.new("TextButton", ModeFrame)
SlowBtn.Size = UDim2.new(0.48, 0, 1, 0)
SlowBtn.Position = UDim2.new(0.52, 0, 0, 0)
SlowBtn.Text = "SLOW MODE"
SlowBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SlowBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", SlowBtn)

-- Slider 1: Speed Multiplier (Fast)
local SpeedSliContainer = Instance.new("Frame")
SpeedSliContainer.Size = UDim2.new(0.9, 0, 0, 45)
SpeedSliContainer.Position = UDim2.new(0.05, 0, 0, 350)
SpeedSliContainer.BackgroundTransparency = 0.2
SpeedSliContainer.Parent = ScrollFrame

local SpeedSliLabel = Instance.new("TextLabel")
SpeedSliLabel.Size = UDim2.new(1, 0, 0, 20)
SpeedSliLabel.BackgroundTransparency = 1
SpeedSliLabel.Text = "Walk Speed: 1.0x"
SpeedSliLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedSliLabel.Font = Enum.Font.SourceSans
SpeedSliLabel.TextSize = 13
SpeedSliLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedSliLabel.Parent = SpeedSliContainer

local SpeedSliTrack = Instance.new("Frame")
SpeedSliTrack.Size = UDim2.new(1, 0, 0, 6)
SpeedSliTrack.Position = UDim2.new(0, 0, 0, 28)
SpeedSliTrack.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SpeedSliTrack.Parent = SpeedSliContainer
Instance.new("UICorner", SpeedSliTrack).CornerRadius = UDim.new(0, 3)

local SpeedSliBtn = Instance.new("TextButton")
SpeedSliBtn.Size = UDim2.new(0, 14, 0, 14)
SpeedSliBtn.Position = UDim2.new(0, 0, 0.5, -7)
SpeedSliBtn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
SpeedSliBtn.Text = ""
SpeedSliBtn.Parent = SpeedSliTrack
Instance.new("UICorner", SpeedSliBtn).CornerRadius = UDim.new(1, 0)

-- Slider 2: Slow Speed Multiplier (Snail)
local SlowSliContainer = Instance.new("Frame")
SlowSliContainer.Size = UDim2.new(0.9, 0, 0, 45)
SlowSliContainer.Position = UDim2.new(0.05, 0, 0, 400)
SlowSliContainer.BackgroundTransparency = 1
SlowSliContainer.Parent = ScrollFrame

local SlowSliLabel = Instance.new("TextLabel")
SlowSliLabel.Size = UDim2.new(1, 0, 0, 20)
SlowSliLabel.BackgroundTransparency = 1
SlowSliLabel.Text = "Slow Speed: 1.0x"
SlowSliLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SlowSliLabel.Font = Enum.Font.SourceSans
SlowSliLabel.TextSize = 13
SlowSliLabel.TextXAlignment = Enum.TextXAlignment.Left
SlowSliLabel.Parent = SlowSliContainer

local SlowSliTrack = Instance.new("Frame")
SlowSliTrack.Size = UDim2.new(1, 0, 0, 6)
SlowSliTrack.Position = UDim2.new(0, 0, 0, 28)
SlowSliTrack.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SlowSliTrack.Parent = SlowSliContainer
Instance.new("UICorner", SlowSliTrack).CornerRadius = UDim.new(0, 3)

local SlowSliBtn = Instance.new("TextButton")
SlowSliBtn.Size = UDim2.new(0, 14, 0, 14)
SlowSliBtn.Position = UDim2.new(1, -7, 0.5, -7)
SlowSliBtn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
SlowSliBtn.Text = ""
SlowSliBtn.Parent = SlowSliTrack
Instance.new("UICorner", SlowSliBtn).CornerRadius = UDim.new(1, 0)

local isSliDragging = false
local isSlowSliDragging = false

local function updateSpeedSlider(input)
    local trackWidth = SpeedSliTrack.AbsoluteSize.X
    local relativeX = input.Position.X - SpeedSliTrack.AbsolutePosition.X
    local percentage = math.clamp(relativeX / trackWidth, 0, 1)
    local rawValue = 1.0 + (percentage * 4.0)
    local snapValue = math.floor((rawValue * 2) + 0.5) / 2
    local finalPercentage = (snapValue - 1.0) / 4.0
    
    SpeedSliBtn.Position = UDim2.new(finalPercentage, -7, 0.5, -7)
    SpeedSliLabel.Text = "Walk Speed: " .. string.format("%.1f", snapValue) .. "x"
    ProfileSettings.CurrentSpeedMultiplier = snapValue
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid").WalkSpeed = 16 * snapValue
    end
end

local function updateSlowSlider(input)
    local trackWidth = SlowSliTrack.AbsoluteSize.X
    local relativeX = input.Position.X - SlowSliTrack.AbsolutePosition.X
    local percentage = math.clamp(relativeX / trackWidth, 0, 1)
    -- Right (1.0) = Normal, Left (0.0) = 0.25x
    local rawValue = 0.25 + (percentage * 0.75)
    local snapValue = math.floor((rawValue * 20) + 0.5) / 20
    local finalPercentage = (snapValue - 0.25) / 0.75
    
    SlowSliBtn.Position = UDim2.new(finalPercentage, -7, 0.5, -7)
    SlowSliLabel.Text = "Slow Speed: " .. string.format("%.2f", snapValue) .. "x"
    ProfileSettings.SlowSpeedMultiplier = snapValue
    
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid").WalkSpeed = 16 * snapValue
    end
end

SpeedSliBtn.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and ProfileSettings.SpeedMode == "Fast" then isSliDragging = true end
end)
SlowSliBtn.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and ProfileSettings.SpeedMode == "Slow" then isSlowSliDragging = true end
end)
UserInputService.InputChanged:Connect(function(input)
    if isSliDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateSpeedSlider(input) end
    if isSlowSliDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateSlowSlider(input) end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isSliDragging = false isSlowSliDragging = false end
end)

FastBtn.MouseButton1Click:Connect(function()
    ProfileSettings.SpeedMode = "Fast"
    FastBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 60)
    SlowBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    SpeedSliContainer.BackgroundTransparency = 0.2
    SlowSliContainer.BackgroundTransparency = 1
end)

SlowBtn.MouseButton1Click:Connect(function()
    ProfileSettings.SpeedMode = "Slow"
    SlowBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 60)
    FastBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    SlowSliContainer.BackgroundTransparency = 0.2
    SpeedSliContainer.BackgroundTransparency = 1
end)

createButton("TELEPORT TO SPAWN", 460, function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local spawn = workspace:FindFirstChild("SpawnLocation", true)
        if spawn then
            TweenService:Create(char.HumanoidRootPart, TweenInfo.new(0.5), {CFrame = spawn.CFrame + Vector3.new(0, 3, 0)}):Play()
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if not gameProcessedEvent and input.KeyCode == Enum.KeyCode.Insert then MainFrame.Visible = not MainFrame.Visible end
end)
