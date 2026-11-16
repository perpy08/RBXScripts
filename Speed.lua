--[[
=====================================================================
  ZEN GLITCH · SPEED
  Refined build (LuaU · LocalScript)
---------------------------------------------------------------------
  Features:
    · Walk speed  - fast / slow modes, multipliers up to x10
    · Sprint aware - Shift-held speed inherits the same multiplier
    · Zen Glow    - cached Bloom + ColorCorrection, toggled cheaply
    · Glitch trail- stripped ghost clones, one shared Heartbeat
    · Persistence - ZenGlitch_Speed.json, restored on load
    · Auto-reload - Speed.lua on teleport
    · Race Speed  - hold-to-boost gas pedal, x1 .. x10, coasts back down
                    final = game speed x walk multiplier x race
=====================================================================
]]

-- Services ------------------------------------------------------------
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local Lighting         = game:GetService("Lighting")
local Debris           = game:GetService("Debris")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Config --------------------------------------------------------------
local Config = {
	BaseWalkSpeed      = 16,      -- fallback only; the real base is read from the Humanoid
	MaxSpeedMultiplier = 10,      -- walk / sprint ceiling
	MinSpeedMultiplier = 0.1,
	SprintFactor       = 1.6,     -- used only when the game never raises WalkSpeed
	MaxRawFactor       = 6,       -- ignore absurd raw values to avoid feedback loops
	MaxRaceSpeed       = 10,      -- pedal ceiling (x1 .. x10)
	MaxAbsoluteSpeed   = 250000,  -- hard ceiling we will ever write
	GhostFrameTime     = 0.33,
	GhostLifetime      = 0.35,
	AnimSkipBase       = 0.15,
	ToggleKey          = Enum.KeyCode.RightShift,
	SaveFile           = "ZenGlitch_Speed.json",
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
	CurrentSpeedMultiplier = 1.0,
	SlowSpeedMultiplier    = 1.0,
	SpeedMode              = "Fast", -- "Fast" | "Slow"
	RaceSpeed              = 0,      -- 0 = race boost inactive, else 0.5..10
	KillGlowActive         = false,
	GlitchActive           = false,
	CameraLockActive       = false,
}
if _saved then
	local src = _saved.State or _saved
	for k, v in pairs(src) do
		if State[k] ~= nil then State[k] = v end
	end
end

-- The pedal is a live input: never restore it pre-boosted
State.RaceSpeed = 0

local Runtime = { alive = true }

-- Janitor -------------------------------------------------------------
local function newJanitor()
	local items, j = {}, {}
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
if _G.__ZenGlitchSpeedJanitor then
	pcall(function() _G.__ZenGlitchSpeedJanitor.clean() end)
end
_G.__ZenGlitchSpeedJanitor = RootJanitor
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

-- Multiplier helpers --------------------------------------------------
local function activeMultiplier()
	if State.SpeedMode == "Fast" then
		return State.CurrentSpeedMultiplier
	end
	-- Slow mode is inverted: higher multiplier = slower movement
	return 1 / math.max(State.SlowSpeedMultiplier, 0.01)
end

-- =====================================================================
--  1 · SPEED ENGINE  (observe the game's raw speed, then scale it)
-- =====================================================================
local SHIFT_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift }

local Speed = {
	walkRaw    = nil,   -- the game's own normal walk speed
	sprintRaw  = nil,   -- the game's own sprint speed (learned)
	lastWritten = nil,  -- last value we pushed into WalkSpeed
	writing    = false, -- true while our own write is in flight
	hadBoost   = false, -- true while we are actively overriding speed
	humanoid   = nil,
}

local function shiftHeld()
	for _, key in ipairs(SHIFT_KEYS) do
		if UserInputService:IsKeyDown(key) then return true end
	end
	return false
end

local function baseRaw(humanoid)
	return humanoid:GetAttribute("ZenBaseSpeed") or Config.BaseWalkSpeed
end

local function clampRaw(humanoid, raw)
	local base = math.max(baseRaw(humanoid), 1)
	local maxRaw = base * Config.MaxRawFactor
	return math.clamp(raw, base * 0.25, maxRaw)
end

-- The single source of truth for what WalkSpeed should be right now.
-- Race Speed stacks ON TOP of the in-game speed:
--   game's raw speed  x  walk/slow multiplier  x  race multiplier
-- A race value of 0 means "inactive" (multiplier 1, not 0).
-- Pedal position reads directly as the multiplier (3x on the meter = x3),
-- with a floor of 1 so the low end is a true "off" instead of slowing you.
local function raceMultiplier()
	local r = math.clamp(State.RaceSpeed or 0, 0, Config.MaxRaceSpeed)
	if r <= 0 then return 1 end
	return math.max(1, r)
end

local function desiredSpeed(humanoid)
	local mult   = activeMultiplier()
	local base   = baseRaw(humanoid)
	local sprint = shiftHeld()
	local raw

	if sprint then
		raw = Speed.sprintRaw or (base * Config.SprintFactor)
	else
		raw = Speed.walkRaw or base
	end

	raw = clampRaw(humanoid, raw)
	return math.clamp(raw * mult * raceMultiplier(), 0, Config.MaxAbsoluteSpeed)
end

local function writeSpeed(humanoid)
	if not humanoid or humanoid.Parent == nil then return end

	local mult = activeMultiplier()
	local sprinting = shiftHeld()

	-- Idle state: hand control back to the game so we never fight
	-- a game's own speed system when no boost is requested.
	local raceOn = (State.RaceSpeed or 0) > 0
	if mult == 1 and not sprinting and not raceOn and not Speed.hadBoost then return end

	local target = desiredSpeed(humanoid)
	local rawBase = Speed.walkRaw or baseRaw(humanoid)

	-- Never drag a sprint back down to our guess before we've learned its
	-- real value. The handler above will capture it on the game's own write.
	if sprinting and not Speed.sprintRaw and humanoid.WalkSpeed > target + 0.01 then
		return
	end

	if math.abs(humanoid.WalkSpeed - target) > 0.01 then
		Speed.writing = true
		Speed.lastWritten = target
		humanoid.WalkSpeed = target
		Speed.writing = false
		Speed.hadBoost = math.abs(target - rawBase) > 0.01
		if not Speed.hadBoost then Speed.lastWritten = nil end
	else
		-- Already where we want it: stop tracking writes for this value
		Speed.hadBoost = math.abs(target - rawBase) > 0.01
		if not Speed.hadBoost then Speed.lastWritten = nil end
	end
end

local function setupSpeed(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	Speed.humanoid = humanoid
	Speed.walkRaw = humanoid.WalkSpeed
	Speed.sprintRaw = nil
	Speed.lastWritten = nil

	if not humanoid:GetAttribute("ZenBaseSpeed") then
		humanoid:SetAttribute("ZenBaseSpeed", humanoid.WalkSpeed)
	end

	local janitor = newJanitor()
	RootJanitor.add(janitor)

	janitor.connect(humanoid.Died, function()
		janitor.clean()
		if Speed.humanoid == humanoid then Speed.humanoid = nil end
	end)
	janitor.connect(character.Destroying, function() janitor.clean() end)

	-- Learn raw speeds from the game's own writes.
	-- This is what makes sprint inherit the multiplier: when the game sets
	-- its sprint speed, we capture that value and scale it, instead of
	-- stomping it back down to the walk value.
	janitor.connect(humanoid:GetPropertyChangedSignal("WalkSpeed"), function()
		if Speed.writing then return end

		local v = humanoid.WalkSpeed
		if Speed.lastWritten and math.abs(v - Speed.lastWritten) < 0.05 then
			return -- our own echo, ignore
		end

		-- With Race Speed active our writes are in the hundreds/thousands.
		-- Never learn from those; just keep enforcing our target.
		if (State.RaceSpeed or 0) > 0 then
			writeSpeed(humanoid)
			return
		end

		local base = baseRaw(humanoid)
		local raw = clampRaw(humanoid, v)

		-- Treat a write as sprint only when Shift is down, or when the value
		-- matches a sprint speed we already learned. This stops ordinary
		-- speed buffs from being mistaken for a sprint.
		local sprinting = shiftHeld()
		if not sprinting and Speed.sprintRaw
			and v > (Speed.walkRaw or 0) + 0.5
			and math.abs(v - Speed.sprintRaw) < 0.5 then
			sprinting = true
		end

		if sprinting then
			Speed.sprintRaw = math.max(raw, Speed.sprintRaw or 0)
		else
			Speed.walkRaw = raw
			-- Games can also change the base (gear, buffs). Keep the attribute fresh.
			if math.abs(raw - base) > 0.05 and raw < base * 1.5 then
				humanoid:SetAttribute("ZenBaseSpeed", raw)
			end
		end

		writeSpeed(humanoid)
	end)

	writeSpeed(humanoid)
end

if LocalPlayer.Character then task.spawn(setupSpeed, LocalPlayer.Character) end
RootJanitor.connect(LocalPlayer.CharacterAdded, setupSpeed)

-- Continuous enforcement at 30 Hz: instant Shift response, mode changes,
-- and recovery if the game resets WalkSpeed on its own.
task.spawn(function()
	while Runtime.alive do
		local humanoid = Speed.humanoid
		if humanoid and humanoid.Parent and humanoid.Health > 0 then
			writeSpeed(humanoid)
		end
		task.wait(1 / 30)
	end
end)

-- =====================================================================
--  2 · GLITCH ENGINE  (ghost trail + animation jitter, one loop)
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
	if not animator then return end
	local function attach(track) jitteredTracks[track] = { lastSkip = 0 } end
	janitor.connect(animator.AnimationPlayed, attach)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		attach(track)
	end
end

local function attachAnimationWatch(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then watchAnimations(animator, RootJanitor) end
end

if LocalPlayer.Character then task.spawn(attachAnimationWatch, LocalPlayer.Character) end
RootJanitor.connect(LocalPlayer.CharacterAdded, attachAnimationWatch)

RootJanitor.connect(RunService.Heartbeat, function()
	if not State.GlitchActive then
		if restorePending then
			restorePending = false
			for track in pairs(jitteredTracks) do
				if track.IsPlaying then pcall(function() track:AdjustSpeed(1) end) end
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
		if moving and now - lastGhostTick >= Config.GhostFrameTime / math.max(mult, 0.1) then
			lastGhostTick = now
			createGhostClone(character)
		end
	end

	local skipEvery = Config.AnimSkipBase / math.max(mult, 0.1)
	for track, meta in pairs(jitteredTracks) do
		if track.IsPlaying then
			pcall(function() track:AdjustSpeed(0) end)
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
--  3 · ZEN GLOW  (cached effects, toggled once)
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
--  3.5 · CAMERA LOCK
-- =====================================================================
local CameraLock = { conn = nil }
RootJanitor.add({ clean = function() CameraLock.setEnabled(false) end })

function CameraLock.setEnabled(on)
	State.CameraLockActive = on
	if on then
		if not CameraLock.conn then
			CameraLock.conn = RunService.RenderStepped:Connect(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				local char = LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local cam = workspace.CurrentCamera
				if root and cam then
					local look = cam.CFrame.LookVector
					local dir = Vector3.new(look.X, 0, look.Z)
					if dir.Magnitude > 0.001 then
						root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
					end
				end
			end)
		end
	else
		if CameraLock.conn then
			CameraLock.conn:Disconnect()
			CameraLock.conn = nil
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end
CameraLock.setEnabled(State.CameraLockActive)

-- =====================================================================
--  4 · CONTROL PANEL
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

-- Where can our GUI live without the game deleting it? Order matters:
--   1. gethui()   - executor-hidden container, invisible to game scripts
--   2. CoreGui    - protected on most executors (syn.protect_gui if present)
--   3. PlayerGui  - last resort: many games purge unknown ScreenGuis here,
--                   which was the "speed works, GUI missing" bug.
local function resolveGuiParent()
	if type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and typeof(hui) == "Instance" then
			return hui, "gethui()"
		end
	end
	local coreGui = game:GetService("CoreGui")
	local probe = Instance.new("ScreenGui")
	local ok = pcall(function() probe.Parent = coreGui end)
	if ok then
		pcall(function() if syn and syn.protect_gui then syn.protect_gui(probe) end end)
		pcall(function() if protectgui then protectgui(probe) end end)
		probe:Destroy()
		return coreGui, "CoreGui"
	end
	probe:Destroy()
	return LocalPlayer:WaitForChild("PlayerGui"), "PlayerGui"
end
local GuiParent, GuiParentName = resolveGuiParent()

local PanelGui = Instance.new("ScreenGui")
PanelGui.Name = "ZenGlitchSpeedPanel"
PanelGui.ResetOnSpawn = false
PanelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
PanelGui.DisplayOrder = 999
-- Parent FIRST, build after: previously the GUI was parented at the very end
-- of the script, so one silent error anywhere below = panel never showed.
PanelGui.Parent = GuiParent

local panel = new("Frame", {
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
	Text = "ZEN GLITCH  ·  SPEED",
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

local function addToggle(label, get, set)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = THEME.panel,
		BorderSizePixel = 0,
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

	new("TextLabel", {
		Size = UDim2.new(1, -58, 1, 0),
		Position = UDim2.fromOffset(11, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.text,
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
	switch.MouseButton1Click:Connect(function() set(not get()); paint() end)
	paint()
end

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
		if Speed.humanoid then writeSpeed(Speed.humanoid) end
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
		local isActive = (State.SpeedMode:lower() == id)
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

-- (The draggable slider was retired in favour of the BOOST pedal below.)

-- Wiring --------------------------------------------------------------
addSectionLabel("walk speed")
addStepper("fast speed", "fast",
	function() return State.CurrentSpeedMultiplier end,
	function(v) State.CurrentSpeedMultiplier = v end,
	1.0, 10, 0.25)
addStepper("slow speed", "slow",
	function() return State.SlowSpeedMultiplier end,
	function(v) State.SlowSpeedMultiplier = v end,
	1.0, 10, 0.25)

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
	if Speed.humanoid then writeSpeed(Speed.humanoid) end
end)
updateStepperVisuals()

local sprintRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = THEME.panel,
	BorderSizePixel = 0,
}, content)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, sprintRow)
local sprintLabel = new("TextLabel", {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.fromOffset(11, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = THEME.dim,
	Text = "sprint: listening…",
}, sprintRow)

-- Live sprint readout so it is obvious that Shift is scaling
task.spawn(function()
	while Runtime.alive do
		local hm = Speed.humanoid
		if hm and hm.Parent then
			local base = baseRaw(hm)
			local sprintRaw = Speed.sprintRaw or (base * Config.SprintFactor)
			local mult = activeMultiplier()
			local raw = shiftHeld() and sprintRaw or (Speed.walkRaw or base)
			local final = raw * mult * raceMultiplier()
			local tag = shiftHeld() and "SPRINT" or "walk"
			sprintLabel.Text = string.format(
				"%s · %.0f x%.2f x%d = %.0f studs/s",
				tag, raw, mult, math.floor(raceMultiplier() + 0.5), final
			)
			sprintLabel.TextColor3 = shiftHeld() and THEME.accent or THEME.dim
		else
			sprintLabel.Text = "sprint: no character"
			sprintLabel.TextColor3 = THEME.dim
		end
		task.wait(0.15)
	end
end)

addSectionLabel("camera")
addToggle("camera lock",
	function() return State.CameraLockActive end,
	CameraLock.setEnabled)

addSectionLabel("visuals")
addToggle("zen glow",
	function() return State.KillGlowActive end,
	Glow.setEnabled)
addToggle("glitch trail",
	function() return State.GlitchActive end,
	function(v) State.GlitchActive = v end)

-- ── RACE SPEED ──────────────────────────────────────────────────────────
local Boost = { holding = false, value = 0, raceToggle = false }
local paintPedal
local setPedalHeld

addSectionLabel("race speed")

-- Race Toggle toggle row (locks Race Speed to x10 when on)
local rtRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = THEME.panel, BorderSizePixel = 0,
}, content)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, rtRow)
new("TextLabel", {
	Size = UDim2.new(1, -58, 1, 0), Position = UDim2.fromOffset(11, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.text,
	Text = "race toggle (walk x10)",
}, rtRow)
local rtSwitch = new("TextButton", {
	Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -48, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.off,
	Text = "", AutoButtonColor = false,
}, rtRow)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, rtSwitch)
local rtKnob = new("Frame", {
	Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 3, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
}, rtSwitch)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, rtKnob)

local function paintRaceToggle()
	local on = Boost.raceToggle
	rtSwitch.BackgroundColor3 = on and THEME.accent or THEME.off
	TweenService:Create(rtKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
		Position = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
	}):Play()
end
rtSwitch.MouseButton1Click:Connect(function()
	Boost.raceToggle = not Boost.raceToggle

	if Boost.raceToggle then
		-- Race toggle ON = slam walk speed multiplier to x10 instantly.
		State.CurrentSpeedMultiplier = Config.MaxSpeedMultiplier
		State.SpeedMode = "Fast"
		-- Update the walk speed stepper readout to reflect x10.
		if stepperRegistry.fast then
			stepperRegistry.fast.val.Text = string.format("%.2fx", State.CurrentSpeedMultiplier)
		end
		updateStepperVisuals()
	else
		-- Race toggle OFF = reset walk speed multiplier back to x1.
		State.CurrentSpeedMultiplier = 1.0
		if stepperRegistry.fast then
			stepperRegistry.fast.val.Text = string.format("%.2fx", State.CurrentSpeedMultiplier)
		end
		updateStepperVisuals()
	end

	paintRaceToggle()
	if Speed.humanoid then writeSpeed(Speed.humanoid) end
end)
paintRaceToggle()

-- Pop-out button
local popBtn = new("TextButton", {
	Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = THEME.off,
	TextColor3 = THEME.text, Font = Enum.Font.GothamBold, TextSize = 11,
	Text = "POP OUT BOOST METER", AutoButtonColor = false,
}, content)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, popBtn)
new("UIStroke", { Color = THEME.stroke, Thickness = 1 }, popBtn)

-- Floating Boost HUD (separate ScreenGui — survives Alt/RightShift hide) --
local boostHudGui = Instance.new("ScreenGui")
boostHudGui.Name = "ZenBoostHUD"
boostHudGui.ResetOnSpawn = false
boostHudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
boostHudGui.DisplayOrder = 1001
boostHudGui.Enabled = false

local hudFrame = new("Frame", {
	Size = UDim2.fromOffset(290, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0.5, -145, 0, 20),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0, Active = true,
}, boostHudGui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, hudFrame)
new("UIStroke", { Color = THEME.accent, Transparency = 0.55, Thickness = 1 }, hudFrame)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, hudFrame)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, hudFrame)

-- Drag handle on HUD header
local hudHeader = new("Frame", {
	Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Active = true,
}, hudFrame)
new("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.dim,
	Text = "RACE BOOST · DRAG TO MOVE",
}, hudHeader)

local hudDrag, hudDragStart, hudStartPos = false, nil, nil
hudHeader.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		hudDrag = true; hudDragStart = input.Position; hudStartPos = hudFrame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then hudDrag = false end
		end)
	end
end)
RootJanitor.connect(UserInputService.InputChanged, function(input)
	if not hudDrag then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local d = input.Position - hudDragStart
	hudFrame.Position = UDim2.new(hudStartPos.X.Scale, hudStartPos.X.Offset + d.X,
		hudStartPos.Y.Scale, hudStartPos.Y.Offset + d.Y)
end)

RootJanitor.add(boostHudGui)
boostHudGui.Parent = GuiParent

-- Shared meter widget factory ------------------------------------------
local ALL_FILLS  = {}
local ALL_VALLBL = {}
local ALL_BTNS   = {}

local function buildMeterWidget(parent)
	-- value label
	local vRow = new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1 }, parent)
	new("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.dim, Text = "RACE BOOST · HOLD",
	}, vRow)
	local vLbl = new("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.dim, Text = "off",
	}, vRow)
	table.insert(ALL_VALLBL, vLbl)

	-- bar
	local bg = new("Frame", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Color3.fromRGB(24, 32, 27), BorderSizePixel = 0,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, bg)
	new("UIStroke", { Color = THEME.accent, Transparency = 0.65, Thickness = 1 }, bg)
	local fl = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = THEME.accent, BorderSizePixel = 0 }, bg)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fl)
	table.insert(ALL_FILLS, fl)

	-- tick scale
	local tRow = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 }, parent)
	for i = 0, Config.MaxRaceSpeed do
		local alpha = i / Config.MaxRaceSpeed
		local anc = (i == 0) and 0 or (i == Config.MaxRaceSpeed) and 1 or 0.5
		new("Frame", { Size = UDim2.fromOffset(2, 5), Position = UDim2.new(alpha, 0, 0, 0),
			AnchorPoint = Vector2.new(anc, 0), BackgroundColor3 = THEME.off, BorderSizePixel = 0 }, tRow)
		new("TextLabel", { Size = UDim2.fromOffset(24, 12), Position = UDim2.new(alpha, 0, 0, 7),
			AnchorPoint = Vector2.new(anc, 0), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = THEME.dim, Text = i .. "x" }, tRow)
	end

	-- button
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(176, 42), Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(52, 120, 80),
		Text = "", AutoButtonColor = false,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)
	local icoF = new("Frame", { Size = UDim2.fromOffset(28, 18),
		Position = UDim2.new(0.5, -52, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 }, btn)
	for i = 1, 3 do
		new("Frame", { Size = UDim2.fromOffset(12 + i * 4, 3),
			Position = UDim2.new(0.5, 0, 0.5, (i - 2) * 6), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.bg, BorderSizePixel = 0, Rotation = -18 }, icoF)
	end
	new("TextLabel", { Size = UDim2.new(1, -68, 1, 0), Position = UDim2.fromOffset(58, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.bg, Text = "BOOST" }, btn)
	table.insert(ALL_BTNS, btn)
	return btn
end

-- Panel card
local pedalCard = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = THEME.panel, BorderSizePixel = 0,
}, content)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, pedalCard)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, pedalCard)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, pedalCard)
local panelBtn = buildMeterWidget(pedalCard)

-- HUD card (inside the floating window)
local hudBtn = buildMeterWidget(hudFrame)

-- Pop-out toggle logic
local meterPopped = false
popBtn.MouseButton1Click:Connect(function()
	meterPopped = not meterPopped
	boostHudGui.Enabled = meterPopped
	pedalCard.Visible = not meterPopped
	popBtn.Text = meterPopped and "COLLAPSE BOOST METER" or "POP OUT BOOST METER"
	popBtn.BackgroundColor3 = meterPopped and THEME.accent or THEME.off
	popBtn.TextColor3 = meterPopped and THEME.bg or THEME.text
end)

-- ── Paint all meter instances ─────────────────────────────────────────
paintPedal = function()
	local alpha = math.clamp(Boost.value / Config.MaxRaceSpeed, 0, 1)
	local on    = Boost.value > 0.01
	local multStr = on and string.format("x%.2f", raceMultiplier()) or "off"
	local btnClr = Boost.holding and Color3.fromRGB(166, 255, 196)
		or (on and THEME.accent or Color3.fromRGB(52, 120, 80))

	for _, fl in ipairs(ALL_FILLS)  do fl.Size = UDim2.fromScale(alpha, 1) end
	for _, lb in ipairs(ALL_VALLBL) do lb.Text = multStr; lb.TextColor3 = on and THEME.accent or THEME.dim end
	for _, bt in ipairs(ALL_BTNS)   do bt.BackgroundColor3 = btnClr end
end

-- ── setPedalHeld + button events ─────────────────────────────────────
setPedalHeld = function(held)
	if Boost.holding == held then return end
	Boost.holding = held
	for _, bt in ipairs(ALL_BTNS) do
		TweenService:Create(bt, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
			Size = held and UDim2.fromOffset(182, 45) or UDim2.fromOffset(176, 42),
		}):Play()
	end
	paintPedal()
end

for _, bt in ipairs(ALL_BTNS) do
	bt.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			setPedalHeld(true)
		end
	end)
	bt.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			setPedalHeld(false)
		end
	end)
end

-- Global release (cursor leaves button while held)
RootJanitor.connect(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		setPedalHeld(false)
	end
end)

-- ── Shift binding for Race Toggle ─────────────────────────────────────
RootJanitor.connect(UserInputService.InputBegan, function(input, gp)
	if gp then return end
	if (input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift)
		and Boost.raceToggle then
		setPedalHeld(true)
	end
end)
RootJanitor.connect(UserInputService.InputEnded, function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift then
		-- Always release the pedal on Shift-up, even if raceToggle was
		-- turned off mid-hold.  Prevents Boost.holding getting stuck true.
		if Boost.holding then
			setPedalHeld(false)
		end
	end
end)

-- ── BOOST PEDAL (hold-to-accelerate, coasts down on release) ----------
local BOOST_RAMP_UP   = 6.0
local BOOST_RAMP_DOWN = 4.0

-- (pedal card built via buildMeterWidget into pedalCard above)

-- Throttle loop
local lastPedalTick = os.clock()
RootJanitor.connect(RunService.RenderStepped, function()
	local now = os.clock()
	local dt = math.min(now - lastPedalTick, 0.1)
	lastPedalTick = now

	local before = Boost.value
	if Boost.holding then
		Boost.value = math.min(Config.MaxRaceSpeed, Boost.value + BOOST_RAMP_UP * dt)
	else
		Boost.value = math.max(0, Boost.value - BOOST_RAMP_DOWN * dt)
	end
	State.RaceSpeed = Boost.value

	if math.abs(Boost.value - before) > 0.0005 then
		paintPedal()
	end
end)

paintPedal()

new("TextLabel", {
	Size = UDim2.new(1, -4, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 9.5,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = THEME.dim,
	Text = "hold BOOST · release to coast off · race toggle sets walk x10",
}, content)

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
	_G.__ZenGlitchSpeedJanitor = nil
	print("[ZenGlitch] Speed unloaded — every connection and instance cleaned")
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
PanelGui.Parent = GuiParent -- re-assert (already parented right after creation)
saveSettings()

-- Watchdog: if the game's anti-cheat purges the panel, fight back.
-- Runtime.alive is false during a real unload, so the × button still cleans up.
RootJanitor.connect(PanelGui.AncestryChanged, function(_, parent)
	if parent or not Runtime.alive then return end
	warn("[ZenGlitch] panel was removed (anti-cheat purge) — attempting recovery via " .. GuiParentName)
	task.defer(function()
		if not Runtime.alive then return end
		-- If the instance was only unparented this puts it straight back.
		local ok = pcall(function() PanelGui.Parent = GuiParent end)
		if ok and PanelGui.Parent then return end
		-- Instance was hard-destroyed: Parent is locked, so rebuild from source.
		-- Capped at 3 rebuilds per session so hostile games can't loop us.
		_G.__ZenGlitchSpeedRebuilds = (_G.__ZenGlitchSpeedRebuilds or 0) + 1
		if _G.__ZenGlitchSpeedRebuilds > 3 then
			warn("[ZenGlitch] panel destroyed too many times — giving up. Re-execute manually.")
			return
		end
		task.wait(1.5)
		if not Runtime.alive then return end
		warn("[ZenGlitch] rebuilding GUI (attempt " .. _G.__ZenGlitchSpeedRebuilds .. "/3)")
		local okGet, res = pcall(game.HttpGet, game,
			"https://raw.githubusercontent.com/perpy08/RBXScripts/main/Speed.lua")
		if okGet and res then
			local fn = loadstring(res)
			if fn then fn() end
		end
	end)
end)

print(string.format("[ZenGlitch] panel alive → parented to %s (%s)",
	PanelGui:GetFullName(), GuiParentName))
task.spawn(function()
	task.wait(1)
	if Runtime.alive and not PanelGui.Parent then
		warn("[ZenGlitch] panel missing 1s after boot — watchdog recovery engaged")
	end
end)

-- Auto-reload across teleports (Speed.lua)
if queue_on_teleport then
	queue_on_teleport([[
		repeat task.wait() until game:IsLoaded()
		task.wait(2)
		if _G.__ZenGlitchSpeedJanitor then
			pcall(function() _G.__ZenGlitchSpeedJanitor.clean() end)
			_G.__ZenGlitchSpeedJanitor = nil
		end
		local ok, res = pcall(game.HttpGet, game,
			"https://raw.githubusercontent.com/perpy08/RBXScripts/main/Speed.lua")
		if ok and res then
			local fn = loadstring(res)
			if fn then fn() end
		end
	]])
end

print("[ZenGlitch] Speed loaded — Alt / RightShift toggles the panel")
