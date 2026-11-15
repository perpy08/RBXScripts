--[[
=====================================================================
  ZEN GLITCH · UNIVERSAL MISC
  Refined build (LuaU · LocalScript)
---------------------------------------------------------------------
  · Single Misc panel - World//Zero and FPS modules removed
  · Multi Jump with optional, nested SAFE LANDING
  · Safe landing: normal fall until ~5 studs above ground,
    then vertical velocity is zeroed for a soft touchdown
  · Event-driven ESP (no per-frame polling)
  · One shared Heartbeat for ghost trail + animation jitter
  · Per-character janitor -> zero connection leaks on respawn
  · Persistence: ZenGlitch_Misc.json (State restored on load)
  · Auto-reload: Universal-Misc.lua on teleport
=====================================================================
]]

-- Services ------------------------------------------------------------
local Players                = game:GetService("Players")
local UserInputService       = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService           = game:GetService("TweenService")
local RunService             = game:GetService("RunService")
local Lighting               = game:GetService("Lighting")
local Debris                 = game:GetService("Debris")
local HttpService            = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Config --------------------------------------------------------------
local Config = {
	BaseWalkSpeed      = 16,
	MinSpeedMultiplier = 0.1,
	MaxSpeedMultiplier = 5,
	GhostFrameTime     = 0.33,
	GhostLifetime      = 0.35,
	AnimSkipBase       = 0.15,
	ToggleKey          = Enum.KeyCode.RightShift,
	SaveFile           = "ZenGlitch_Misc.json",
}

-- Persistence ---------------------------------------------------------
local function loadSaved()
	local ok, data = pcall(function() return readfile(Config.SaveFile) end)
	if not ok or not data then return nil end
	local ok2, parsed = pcall(function() return HttpService:JSONDecode(data) end)
	return ok2 and parsed or nil
end

local _saved = loadSaved()

-- State ---------------------------------------------------------------
local State = {
	InstantInteractions    = false,
	MultiJumpActive        = false,
	SafeLandActive         = false, -- nested under Multi Jump
	PlayerESPActive        = false,
	KillGlowActive         = false,
	GlitchActive           = false,
	CurrentSpeedMultiplier = 1.0,
	SlowSpeedMultiplier    = 1.0,
	AttackSpeedMultiplier  = 1.0,
	SpeedMode              = "Fast", -- "Fast" | "Slow"
}
if _saved then
	local src = _saved.State or _saved
	for k, v in pairs(src) do
		if State[k] ~= nil then State[k] = v end
	end
end

local Runtime = { alive = true }

-- Janitor -------------------------------------------------------------
local function newJanitor()
	local items = {}
	local j = {}
	function j.add(item) table.insert(items, item) return item end
	function j.connect(signal, fn)
		local conn = signal:Connect(fn)
		table.insert(items, conn)
		return conn
	end
	function j.clean()
		for _, item in ipairs(items) do
			if typeof(item) == "RBXScriptConnection" then item:Disconnect()
			elseif typeof(item) == "Instance" then item:Destroy()
			elseif type(item) == "table" and item.clean then item.clean() end
		end
		table.clear(items)
	end
	return j
end

local RootJanitor = newJanitor()
if _G.__ZenGlitchJanitor then
	pcall(function() _G.__ZenGlitchJanitor.clean() end)
end
_G.__ZenGlitchJanitor = RootJanitor
RootJanitor.add({ clean = function() Runtime.alive = false end })

-- Save loop -----------------------------------------------------------
local function saveSettings()
	pcall(function()
		writefile(Config.SaveFile, HttpService:JSONEncode({ State = State }))
	end)
end
task.spawn(function()
	while Runtime.alive do
		saveSettings()
		task.wait(5)
	end
end)

local function activeMultiplier()
	if State.SpeedMode == "Fast" then
		return State.CurrentSpeedMultiplier
	end
	return 1 / math.max(State.SlowSpeedMultiplier, 0.01)
end

-- =====================================================================
--  1 · ESP (event-driven)
-- =====================================================================
local ESP = {}

local function buildESP(character, player)
	local root = character:WaitForChild("HumanoidRootPart", 3)
	if not root then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "PlayerHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.Enabled = State.PlayerESPActive
	highlight.Parent = character

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerLabel"
	billboard.Size = UDim2.fromOffset(120, 24)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = State.PlayerESPActive

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.Text = player.DisplayName
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	billboard.Parent = root
end

function ESP.setEnabled(on)
	State.PlayerESPActive = on
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local highlight = char:FindFirstChild("PlayerHighlight")
			local root = char:FindFirstChild("HumanoidRootPart")
			local label = root and root:FindFirstChild("PlayerLabel")
			if highlight then highlight.Enabled = on end
			if label then label.Enabled = on end
		end
	end
end

local function watchPlayer(player)
	if player == LocalPlayer then return end
	RootJanitor.connect(player.CharacterAdded, function(character)
		if character:FindFirstChild("PlayerHighlight") then return end
		buildESP(character, player)
	end)
	if player.Character then
		task.spawn(buildESP, player.Character, player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
RootJanitor.connect(Players.PlayerAdded, watchPlayer)

-- =====================================================================
--  2 · CHARACTER (speed · attack speed · multi jump)
-- =====================================================================
local currentHumanoid = nil

local CORE_ANIMS = { "walk", "run", "idle", "jump", "fall", "climb", "swim", "sit", "toolnone" }

local function applyAttackSpeed(track)
	if State.AttackSpeedMultiplier == 1.0 then return end
	local name = string.lower(track.Name)
	for _, core in ipairs(CORE_ANIMS) do
		if string.find(name, core) then return end
	end
	task.spawn(function()
		track:AdjustSpeed(State.AttackSpeedMultiplier)
		task.wait()
		if track.IsPlaying then
			track:AdjustSpeed(State.AttackSpeedMultiplier)
		end
	end)
end

local function targetWalkSpeed(humanoid)
	local base = humanoid:GetAttribute("ZenBaseSpeed") or Config.BaseWalkSpeed
	return base * activeMultiplier()
end

local function refreshSpeed(humanoid)
	if not humanoid or humanoid.Parent == nil then return end
	local target = targetWalkSpeed(humanoid)
	if math.abs(humanoid.WalkSpeed - target) > 0.05 then
		humanoid.WalkSpeed = target
	end
end

local function setupCharacter(character)
	local janitor = newJanitor()
	RootJanitor.add(janitor)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then janitor.clean() return end
	currentHumanoid = humanoid

	if not humanoid:GetAttribute("ZenBaseSpeed") then
		humanoid:SetAttribute("ZenBaseSpeed", humanoid.WalkSpeed)
	end
	refreshSpeed(humanoid)

	janitor.connect(humanoid.Died, function() janitor.clean() end)
	janitor.connect(character.Destroying, function() janitor.clean() end)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		janitor.connect(animator.AnimationPlayed, applyAttackSpeed)
	end

	local applying = false
	janitor.connect(humanoid:GetPropertyChangedSignal("WalkSpeed"), function()
		if applying then return end
		local target = targetWalkSpeed(humanoid)
		if math.abs(humanoid.WalkSpeed - target) > 1 then
			applying = true
			humanoid.WalkSpeed = target
			applying = false
		end
	end)
end

if LocalPlayer.Character then task.spawn(setupCharacter, LocalPlayer.Character) end
RootJanitor.connect(LocalPlayer.CharacterAdded, setupCharacter)

-- Multi Jump · held-Space flight + optional precision safe landing -----
RootJanitor.connect(RunService.Heartbeat, function()
	if not State.MultiJumpActive then return end

	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	-- Hold Space to fly / stay airborne
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		rootPart.AssemblyLinearVelocity = Vector3.new(
			rootPart.AssemblyLinearVelocity.X,
			humanoid.JumpPower * 0.8,
			rootPart.AssemblyLinearVelocity.Z
		)
		return
	end

	-- Optional safe landing
	-- Normal fall speed until we are ~5 studs above a landable surface,
	-- then the downward velocity is zeroed so the final drop is harmless.
	if State.SafeLandActive then
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y < -20 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }

			-- RootPart sits ~3 studs above the feet: 3 + 5 = 8 stud probe
			local hit = workspace:Raycast(rootPart.Position, Vector3.new(0, -8, 0), params)
			if hit then
				rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
			end
		end
	end
end)

-- =====================================================================
--  3 · GLITCH ENGINE (one shared Heartbeat)
-- =====================================================================
local STRIP_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true,
	Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
	Fire = true, Smoke = true, Sparkles = true,
	BillboardGui = true, SurfaceGui = true, Decal = true, Texture = true,
}

local lastGhostTick = 0
local jitteredTracks = setmetatable({}, { __mode = "k" })
local restorePending = false

local function createGhostClone(character)
	local prev = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(character.Clone, character)
	character.Archivable = prev
	if not ok or not clone then return end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:Destroy() end
	local animator = clone:FindFirstChildWhichIsA("Animator", true)
	if animator then animator:Destroy() end

	local fade = TweenInfo.new(Config.GhostLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	for _, node in ipairs(clone:GetDescendants()) do
		if node:IsA("BasePart") then
			node.Anchored = true
			node.CanCollide = false
			node.CanTouch = false
			node.CanQuery = false
			node.CastShadow = false
			node.Transparency = math.max(node.Transparency, 0.55)
			local c = node.Color
			node.Color = Color3.new(c.R * 0.6, c.G * 0.85, c.B)
			TweenService:Create(node, fade, {
				Transparency = 1,
				Size = node.Size * 0.82,
			}):Play()
		elseif STRIP_CLASSES[node.ClassName] then
			node:Destroy()
		end
	end

	clone.Parent = workspace
	Debris:AddItem(clone, Config.GhostLifetime)
end

local function watchAnimations(animator, janitor)
	local function attach(track)
		jitteredTracks[track] = { lastSkip = 0 }
	end
	janitor.connect(animator.AnimationPlayed, attach)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		attach(track)
	end
end

-- Attach animation watching to the current character and every respawn
local function attachAnimationWatch(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then watchAnimations(animator, RootJanitor) end
end

if LocalPlayer.Character then
	task.spawn(attachAnimationWatch, LocalPlayer.Character)
end
RootJanitor.connect(LocalPlayer.CharacterAdded, attachAnimationWatch)

RootJanitor.connect(RunService.Heartbeat, function()
	if not State.GlitchActive then
		if restorePending then
			restorePending = false
			for track in pairs(jitteredTracks) do
				if track.IsPlaying then track:AdjustSpeed(1) end
			end
		end
		return
	end
	restorePending = true

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	local mult = math.clamp(activeMultiplier(), Config.MinSpeedMultiplier, Config.MaxSpeedMultiplier)

	if humanoid and rootPart then
		local moving = humanoid.MoveDirection.Magnitude > 0
			or rootPart.AssemblyLinearVelocity.Magnitude > 0.1
		if moving and now - lastGhostTick >= Config.GhostFrameTime / mult then
			lastGhostTick = now
			createGhostClone(character)
		end
	end

	local skipEvery = Config.AnimSkipBase / mult
	for track, meta in pairs(jitteredTracks) do
		if track.IsPlaying then
			track:AdjustSpeed(0)
			if now - meta.lastSkip >= skipEvery then
				meta.lastSkip = now
				local skip = 0.1 + math.random() * 0.1
				local length = math.max(track.Length, 0.05)
				track.TimePosition = (track.TimePosition + skip) % length
			end
		end
	end
end)

-- =====================================================================
--  4 · INSTANT INTERACTIONS
-- =====================================================================
local Prompts = {}
local originalHoldTimes = setmetatable({}, { __mode = "k" })

local function neuterPrompt(prompt)
	if prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then
		originalHoldTimes[prompt] = prompt.HoldDuration
		prompt.HoldDuration = 0
	end
end

RootJanitor.connect(ProximityPromptService.PromptShown, function(prompt)
	if State.InstantInteractions then neuterPrompt(prompt) end
end)

function Prompts.setEnabled(on)
	State.InstantInteractions = on
	if on then
		task.spawn(function()
			for _, node in ipairs(workspace:GetDescendants()) do
				if node:IsA("ProximityPrompt") then neuterPrompt(node) end
			end
		end)
	else
		for prompt, hold in pairs(originalHoldTimes) do
			if prompt.Parent then prompt.HoldDuration = hold end
		end
		table.clear(originalHoldTimes)
	end
end

-- =====================================================================
--  5 · ZEN GLOW
-- =====================================================================
local Glow = {}

local bloom = Instance.new("BloomEffect")
bloom.Name = "ZenBloom"
bloom.Intensity = 0.6
bloom.Size = 32
bloom.Threshold = 0.95
bloom.Enabled = State.KillGlowActive
bloom.Parent = Lighting

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "ZenTint"
tint.Saturation = 0.2
tint.Contrast = 0.05
tint.TintColor = Color3.fromRGB(214, 255, 232)
tint.Enabled = State.KillGlowActive
tint.Parent = Lighting

RootJanitor.add(bloom)
RootJanitor.add(tint)

function Glow.setEnabled(on)
	State.KillGlowActive = on
	bloom.Enabled = on
	tint.Enabled = on
end

-- =====================================================================
--  6 · CONTROL PANEL (single Misc column)
-- =====================================================================
local THEME = {
	bg     = Color3.fromRGB(13, 15, 14),
	panel  = Color3.fromRGB(20, 23, 22),
	stroke = Color3.fromRGB(38, 46, 42),
	accent = Color3.fromRGB(124, 255, 171),
	text   = Color3.fromRGB(232, 242, 236),
	dim    = Color3.fromRGB(143, 163, 154),
	off    = Color3.fromRGB(45, 55, 50),
}

local function new(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then inst[key] = value end
	end
	inst.Parent = parent
	return inst
end

local PanelGui = Instance.new("ScreenGui")
PanelGui.Name = "ZenGlitchPanel"
PanelGui.ResetOnSpawn = false
PanelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
PanelGui.DisplayOrder = 999

local panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.fromOffset(276, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0, 24, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
	Active = true,
}, PanelGui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
new("UIStroke", { Color = THEME.stroke, Thickness = 1 }, panel)

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = THEME.panel,
	BorderSizePixel = 0,
}, panel)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, header)

new("TextLabel", {
	Size = UDim2.new(1, -72, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = THEME.accent,
	Text = "ZEN GLITCH  ·  MISC",
}, header)

local minBtn = new("TextButton", {
	Size = UDim2.fromOffset(22, 22),
	Position = UDim2.new(1, -50, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = THEME.off,
	TextColor3 = THEME.text,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	Text = "–",
	AutoButtonColor = false,
}, header)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, minBtn)

local closeBtn = new("TextButton", {
	Size = UDim2.fromOffset(22, 22),
	Position = UDim2.new(1, -24, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = THEME.off,
	TextColor3 = Color3.fromRGB(255, 100, 100),
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	Text = "×",
	AutoButtonColor = false,
}, header)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

local content = new("Frame", {
	Name = "Content",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(0, 40),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, content)

local function addSectionLabel(text)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.dim,
		Text = string.upper(text),
	}, content)
end

-- Toggle factory (parent defaults to content; optional indent + visibility)
local function addToggle(label, get, set, opts)
	opts = opts or {}
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
		Visible = (opts.visible ~= false),
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

	new("TextLabel", {
		Size = UDim2.new(1, -58, 1, 0),
		Position = UDim2.fromOffset(11, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = (opts.muted and THEME.dim or THEME.text),
		Text = label,
	}, row)

	local switch = new("TextButton", {
		Size = UDim2.fromOffset(38, 20),
		Position = UDim2.new(1, -48, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = THEME.off,
		Text = "",
		AutoButtonColor = false,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, switch)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0, 3, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, switch)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local function paint()
		local on = get()
		switch.BackgroundColor3 = on and THEME.accent or THEME.off
		TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Position = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end

	switch.MouseButton1Click:Connect(function()
		set(not get())
		paint()
	end)
	paint()
	return row
end

-- Stepper factory
local stepperRegistry = {}

local function addStepper(label, id, get, set, minV, maxV, step)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

	local title = new("TextLabel", {
		Size = UDim2.new(1, -118, 1, 0),
		Position = UDim2.fromOffset(11, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.text,
		Text = label,
	}, row)

	local group = new("Frame", {
		Size = UDim2.new(0, 100, 1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
	}, row)

	local value = new("TextLabel", {
		Size = UDim2.new(0, 42, 1, 0),
		Position = UDim2.new(0, 30, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = THEME.accent,
		Text = string.format("%.2fx", get()),
	}, group)

	local function bump(dir)
		if id == "fast" and State.SpeedMode ~= "Fast" then return end
		if id == "slow" and State.SpeedMode ~= "Slow" then return end
		local v = math.clamp(math.floor((get() + dir * step) * 100 + 0.5) / 100, minV, maxV)
		set(v)
		value.Text = string.format("%.2fx", v)
		if (id == "fast" or id == "slow") and currentHumanoid then
			refreshSpeed(currentHumanoid)
		end
	end

	local minus = new("TextButton", {
		Size = UDim2.fromOffset(24, 22), Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.off,
		TextColor3 = THEME.text, Font = Enum.Font.GothamBold,
		TextSize = 12, Text = "-", AutoButtonColor = false,
	}, group)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, minus)

	local plus = new("TextButton", {
		Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = THEME.off,
		TextColor3 = THEME.text, Font = Enum.Font.GothamBold,
		TextSize = 12, Text = "+", AutoButtonColor = false,
	}, group)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, plus)

	minus.MouseButton1Click:Connect(function() bump(-1) end)
	plus.MouseButton1Click:Connect(function() bump(1) end)

	stepperRegistry[id] = { title = title, val = value, minus = minus, plus = plus }
end

local function updateStepperVisuals()
	for id, ui in pairs(stepperRegistry) do
		local isActive = (id == "atk") or (State.SpeedMode:lower() == id)
		local trans = isActive and 0 or 0.6
		ui.title.TextTransparency = trans
		ui.val.TextTransparency = trans
		ui.minus.BackgroundTransparency = math.min(1, 0.45 + trans)
		ui.minus.TextTransparency = trans
		ui.plus.BackgroundTransparency = math.min(1, 0.45 + trans)
		ui.plus.TextTransparency = trans
		ui.minus.Active = isActive
		ui.plus.Active = isActive
	end
end

-- Wiring --------------------------------------------------------------
addSectionLabel("automation")
addToggle("instant interact",
	function() return State.InstantInteractions end,
	Prompts.setEnabled
)

addSectionLabel("movement")

-- Multi Jump + nested Safe Landing
local safeLandRow
addToggle("multi jump",
	function() return State.MultiJumpActive end,
	function(v)
		State.MultiJumpActive = v
		-- Safe Landing is nested: it only appears while Multi Jump is on.
		-- Its value is preserved (and ignored while Multi Jump is off).
		if safeLandRow then safeLandRow.Visible = v end
	end
)

safeLandRow = addToggle("↳ safe landing",
	function() return State.SafeLandActive end,
	function(v) State.SafeLandActive = v end,
	{ muted = true, visible = State.MultiJumpActive }
)

addStepper("fast speed", "fast",
	function() return State.CurrentSpeedMultiplier end,
	function(v) State.CurrentSpeedMultiplier = v end,
	1.0, 5, 0.25)
addStepper("slow speed", "slow",
	function() return State.SlowSpeedMultiplier end,
	function(v) State.SlowSpeedMultiplier = v end,
	1.0, 5, 0.25)

local modeBtn = new("TextButton", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = THEME.off,
	TextColor3 = THEME.accent,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	Text = "MODE: " .. string.upper(State.SpeedMode),
	AutoButtonColor = false,
}, content)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, modeBtn)
modeBtn.MouseButton1Click:Connect(function()
	State.SpeedMode = (State.SpeedMode == "Fast") and "Slow" or "Fast"
	modeBtn.Text = "MODE: " .. string.upper(State.SpeedMode)
	updateStepperVisuals()
	if currentHumanoid then refreshSpeed(currentHumanoid) end
end)
updateStepperVisuals()

addSectionLabel("combat")
addStepper("attack speed", "atk",
	function() return State.AttackSpeedMultiplier end,
	function(v) State.AttackSpeedMultiplier = v end,
	0.25, 5, 0.25)

addSectionLabel("visuals")
addToggle("player esp",
	function() return State.PlayerESPActive end,
	ESP.setEnabled)
addToggle("zen glow",
	function() return State.KillGlowActive end,
	Glow.setEnabled)
addToggle("glitch trail",
	function() return State.GlitchActive end,
	function(v) State.GlitchActive = v end)

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 10,
	TextColor3 = THEME.dim,
	Text = "ALT / RightShift toggle · × unload",
}, content)

-- Dragging ------------------------------------------------------------
local dragging, dragStart, startPos = false, nil, nil

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

RootJanitor.connect(UserInputService.InputChanged, function(input)
	if not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local delta = input.Position - dragStart
	panel.Position = UDim2.new(
		startPos.X.Scale, startPos.X.Offset + delta.X,
		startPos.Y.Scale, startPos.Y.Offset + delta.Y
	)
end)

-- Minimize / unload / keybind -----------------------------------------
minBtn.MouseButton1Click:Connect(function()
	content.Visible = not content.Visible
	minBtn.Text = content.Visible and "–" or "+"
end)

closeBtn.MouseButton1Click:Connect(function()
	saveSettings()
	RootJanitor.clean()
	_G.__ZenGlitchJanitor = nil
	print("[ZenGlitch] Misc unloaded — every connection and instance cleaned")
end)

RootJanitor.connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Config.ToggleKey
		or input.KeyCode == Enum.KeyCode.LeftAlt
		or input.KeyCode == Enum.KeyCode.RightAlt then
		panel.Visible = not panel.Visible
	end
end)

-- Boot ----------------------------------------------------------------
RootJanitor.add(PanelGui)
PanelGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Persist immediately so a fresh reload keeps the panel's setup
saveSettings()

-- Auto-reload across teleports (Universal-Misc.lua)
if queue_on_teleport then
	queue_on_teleport([[
		repeat task.wait() until game:IsLoaded()
		task.wait(2)
		if _G.__ZenGlitchJanitor then
			pcall(function() _G.__ZenGlitchJanitor.clean() end)
			_G.__ZenGlitchJanitor = nil
		end
		local ok, res = pcall(game.HttpGet, game,
			"https://raw.githubusercontent.com/perpy08/RBXScripts/main/Universal-Misc.lua")
		if ok and res then
			local fn = loadstring(res)
			if fn then fn() end
		end
	]])
end

print("[ZenGlitch] Universal Misc loaded — Alt / RightShift toggles the panel")
