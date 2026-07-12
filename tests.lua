-- =====================================================================
--  MINE A MOUNTAIN: UNIVERSAL SAFE AUTOMATION PANEL (ZEN GLITCH EDITION)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") 
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

-- Main State Flags
local ProfileSettings = {
    AutoBuyActive = false,
    InstantInteractions = false,
    MultiJumpActive = false,
    NoRagdollActive = false,
    NoDamageActive = false,
    PlayerESPActive = false,
    KillGlowActive = false, 
    GlitchActive = false, 
    CurrentSpeedMultiplier = 1.0,
    SlowSpeedMultiplier = 1.0,
    SpeedMode = "Fast" -- "Fast" or "Slow"
}

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

-- DYNAMIC GLITCH ENGINE
local BASE_FRAME_DURATION = 0.33
local lastGlobalTick = 0

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
            local originalColor = part.Color
            part.Color = Color3.new(originalColor.R * 0.7, originalColor.G * 0.7, originalColor.B * 0.7)
            TweenService:Create(part, TweenInfo.new(0.3), {Transparency = 1, Size = part.Size * 0.8}):Play()
        elseif part:IsA("Decal") or part:IsA("Texture") then
            part:Destroy()
        end
    end
    
    clone.Parent = workspace
    game:GetService("Debris"):AddItem(clone, 0.3)
end

RunService.Heartbeat:Connect(function()
    if not ProfileSettings.GlitchActive then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end

    local isMoving = humanoid.MoveDirection.Magnitude > 0 or rootPart.Velocity.Magnitude > 0.1
    if not isMoving then return end
    
    local currentMult = (ProfileSettings.SpeedMode == "Fast") and ProfileSettings.CurrentSpeedMultiplier or ProfileSettings.SlowSpeedMultiplier
    local dynamicDuration = BASE_FRAME_DURATION / math.clamp(currentMult, 0.1, 5)
    
    if os.clock() - lastGlobalTick >= dynamicDuration then
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
            local currentMult = (ProfileSettings.SpeedMode == "Fast") and ProfileSettings.CurrentSpeedMultiplier or ProfileSettings.SlowSpeedMultiplier
            local skipInterval = 0.15 / math.clamp(currentMult, 0.1, 5)
            
            if os.clock() - lastUpdate >= skipInterval then
                local skip = 0.1 + (math.random() * 0.1)
                track.TimePosition = track.TimePosition + skip
                lastUpdate = os.clock()
            end
        else
            track:AdjustSpeed(1.0)
        end
    end)
end

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
        if ProfileSettings.NoRagdollActive then
            if (newState == Enum.HumanoidStateType.Physics or newState == Enum.HumanoidStateType.Ragdoll or newState == Enum.HumanoidStateType.FallingDown) then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                rootPart.Velocity = Vector3.new(0,0,0)
            end
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

-- Infinite Flight / Soft Land Logic
RunService.Heartbeat:Connect(function()
    if not ProfileSettings.MultiJumpActive then return end
    
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end

    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        rootPart.Velocity = Vector3.new(rootPart.Velocity.X, humanoid.JumpPower * 0.8, rootPart.Velocity.Z)
    end

    if rootPart.Velocity.Y < -40 then 
        local ray = Ray.new(rootPart.Position, Vector3.new(0, -15, 0))
        local part = workspace:FindPartOnRay(ray, char)
        if part then
            rootPart.Velocity = Vector3.new(rootPart.Velocity.X, -2, rootPart.Velocity.Z)
        end
    end
end)

-- ---------------------------------------------------------------------
--  SUPREME ANTI-RAGDOLL & GLOW KILLER
-- ---------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    -- RELENTLESS RAGDOLL EXTERMINATOR (Fixing the torso flop)
    if ProfileSettings.NoRagdollActive then
        local char = LocalPlayer.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local rootPart = char:FindFirstChild("HumanoidRootPart")
            
            -- Force stand and state spam to prevent flopping
            if humanoid then
                humanoid.PlatformStand = false
                if humanoid:GetState() == Enum.HumanoidStateType.Ragdoll or humanoid:GetState() == Enum.HumanoidStateType.Physics then
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
            
            if rootPart and rootPart.Velocity.Magnitude > 50 and humanoid and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
                -- Dampen erratic physics movement if ragdolled
                rootPart.Velocity = rootPart.Velocity * 0.9
            end

            for _, obj in ipairs(char:GetDescendants()) do
                if obj:IsA("BallSocketConstraint") or obj:IsA("HingeConstraint") or obj:IsA("SpringConstraint") or 
                   obj:IsA("Solder") or obj.Name:find("Ragdoll") or obj.Name:find("Blueprint") or obj.Name:find("RagdollSystem") then
                    obj:Destroy()
                end
            end
        end
    end

    -- GLOW KILLER CORE
    if ProfileSettings.KillGlowActive then
        for _, part in ipairs(workspace:GetDescendants()) do
            if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
                part.Material = Enum.Material.SmoothPlastic
            end
        end
        for _, effect in ipairs(Lighting:GetChildren()) do
            if (effect:IsA("BloomEffect") or effect:IsA("BlurEffect")) and effect.Enabled then
                effect.Enabled = false
            end
        end
    end
end)

-- ---------------------------------------------------------------------
--  3. GRAPHICAL USER INTERFACE (ZEN PASTEL EDITION)
-- ---------------------------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MineAMountainPanel"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 550) 
MainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(230, 255, 230) 
MainFrame.Active = true
MainFrame.Draggable = true 
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local HeaderLabel = Instance.new("TextLabel")
HeaderLabel.Size = UDim2.new(1, 0, 0, 40)
HeaderLabel.BackgroundColor3 = Color3.fromRGB(180, 230, 180) 
HeaderLabel.Text = "Mine A Mountain - Zen Edition"
HeaderLabel.TextColor3 = Color3.fromRGB(60, 120, 60)
HeaderLabel.Font = Enum.Font.SourceSansBold
HeaderLabel.TextSize = 16
HeaderLabel.Parent = MainFrame
Instance.new("UICorner", HeaderLabel).CornerRadius = UDim.new(0, 12)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, 0, 1, -40)
ScrollFrame.Position = UDim2.new(0, 0, 0, 40)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 600) 
ScrollFrame.ScrollBarThickness = 4
ScrollFrame.Parent = MainFrame

local function createToggle(name, positionY, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.Position = UDim2.new(0.05, 0, 0, positionY)
    Button.BackgroundColor3 = Color3.fromRGB(240, 255, 240)
    Button.Text = name .. ": OFF"
    Button.TextColor3 = Color3.fromRGB(80, 150, 80)
    Button.Font = Enum.Font.SourceSans
    Button.TextSize = 14
    Button.Parent = ScrollFrame
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 6)

    local toggled = false
    Button.MouseButton1Click:Connect(function()
        toggled = not toggled
        Button.BackgroundColor3 = toggled and Color3.fromRGB(160, 220, 160) or Color3.fromRGB(240, 255, 240)
        Button.TextColor3 = toggled and Color3.fromRGB(40, 100, 40) or Color3.fromRGB(80, 150, 80)
        Button.Text = name .. (toggled and ": ON" or ": OFF")
        callback(toggled)
    end)
    return Button
end

local function createButton(name, positionY, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.Position = UDim2.new(0.05, 0, 0, positionY)
    Button.BackgroundColor3 = Color3.fromRGB(180, 230, 180)
    Button.Text = name
    Button.TextColor3 = Color3.fromRGB(60, 120, 60)
    Button.Parent = ScrollFrame
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 6)
    Button.MouseButton1Click:Connect(callback)
end

createToggle("Auto Buy Bombs", 10, function(s) ProfileSettings.AutoBuyActive = s end)
createToggle("Instant E-Mining", 50, function(s) ProfileSettings.InstantInteractions = s end)
createToggle("Infinite Multi-Jump", 90, function(s) ProfileSettings.MultiJumpActive = s end)
createToggle("No Ragdoll", 130, function(s) ProfileSettings.NoRagdollActive = s end)
createToggle("No Damage", 170, function(s) ProfileSettings.NoDamageActive = s end)
createToggle("Player ESP", 210, function(s) ProfileSettings.PlayerESPActive = s end)
createToggle("Kill Glow/Sparkles", 250, function(s) ProfileSettings.KillGlowActive = s end)
createToggle("Glitch Lag FX", 290, function(s) 
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

local ModeFrame = Instance.new("Frame")
ModeFrame.Size = UDim2.new(0.9, 0, 0, 40)
ModeFrame.Position = UDim2.new(0.05, 0, 0, 330)
ModeFrame.BackgroundTransparency = 1
ModeFrame.Parent = ScrollFrame

local FastBtn = Instance.new("TextButton", ModeFrame)
FastBtn.Size = UDim2.new(0.48, 0, 1, 0)
FastBtn.Position = UDim2.new(0, 0, 0, 0)
FastBtn.Text = "FAST MODE"
FastBtn.BackgroundColor3 = Color3.fromRGB(160, 220, 160)
FastBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", FastBtn)

local SlowBtn = Instance.new("TextButton", ModeFrame)
SlowBtn.Size = UDim2.new(0.48, 0, 1, 0)
SlowBtn.Position = UDim2.new(0.52, 0, 0, 0)
SlowBtn.Text = "SLOW MODE"
SlowBtn.BackgroundColor3 = Color3.fromRGB(210, 240, 210)
SlowBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", SlowBtn)

local function createSlider(name, positionY, min, max, default, callback)
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(0.9, 0, 0, 45)
    Container.Position = UDim2.new(0.05, 0, 0, positionY)
    Container.BackgroundTransparency = 0.2
    Container.Parent = ScrollFrame

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 0, 20)
    Label.BackgroundTransparency = 1
    Label.Text = name .. ": " .. default .. "x"
    Label.TextColor3 = Color3.new(0, 0, 0)
    Label.Font = Enum.Font.SourceSans
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Container

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, 0, 0, 6)
    Track.Position = UDim2.new(0, 0, 0, 28)
    Track.BackgroundColor3 = Color3.fromRGB(180, 210, 180)
    Track.Parent = Container
    Instance.new("UICorner", Track).CornerRadius = UDim.new(0, 3)

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 14, 0, 14)
    Btn.Position = UDim2.new(0, 0, 0.5, -7)
    Btn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    Btn.Text = ""
    Btn.Parent = Track
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(1, 0)

    local isDragging = false
    
    Btn.InputBegan:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then isDragging = true end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local relativeX = input.Position.X - Track.AbsolutePosition.X
            local percentage = math.clamp(relativeX / Track.AbsoluteSize.X, 0, 1)
            local value = min + (percentage * (max - min))
            
            Btn.Position = UDim2.new((value - min) / (max - min), -7, 0.5, -7)
            Label.Text = name .. ": " .. string.format("%.2f", value) .. "x"
            callback(value)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDragging = false end
    end)
end

createSlider("Walk Speed", 330, 1, 5, 1, function(v)
    ProfileSettings.CurrentSpeedMultiplier = v
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        LocalPlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 16 * v
    end
end)

createSlider("Slow Speed", 380, 1, 0.25, 1, function(v)
    ProfileSettings.SlowSpeedMultiplier = v
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        LocalPlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 16 * v
    end
end)

createButton("TELEPORT TO SPAWN", 430, function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local spawn = workspace:FindFirstChild("SpawnLocation", true)
        if spawn then
            TweenService:Create(char.HumanoidRootPart, TweenInfo.new(0.5), {CFrame = spawn.CFrame + Vector3.new(0, 3, 0)}):Play()
        end
    end
end)

FastBtn.MouseButton1Click:Connect(function()
    ProfileSettings.SpeedMode = "Fast"
    FastBtn.BackgroundColor3 = Color3.fromRGB(140, 200, 140)
    SlowBtn.BackgroundColor3 = Color3.fromRGB(210, 240, 210)
end)

SlowBtn.MouseButton1Click:Connect(function()
    ProfileSettings.SpeedMode = "Slow"
    SlowBtn.BackgroundColor3 = Color3.fromRGB(140, 200, 140)
    FastBtn.BackgroundColor3 = Color3.fromRGB(210, 240, 210)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if not gameProcessedEvent and input.KeyCode == Enum.KeyCode.Insert then MainFrame.Visible = not MainFrame.Visible end
end)
