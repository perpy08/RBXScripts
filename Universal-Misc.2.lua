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
  · Auto-reload: Universal-Misc.2.lua on teleport
  · Rev B: attack speed removed; Inf Dash (Q) + AutoCast (any key / mouse button) added
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
	MaxSpeedMultiplier = 10, -- walk speed can boost up to x10
	GhostFrameTime     = 0.33,
	GhostLifetime      = 0.35,
	AnimSkipBase       = 0.15,
	ToggleKey          = Enum.KeyCode.RightShift,
	GhostMinInterval   = 0.06, -- floor on ghost spawn, whatever the multiplier
	GhostMaxLive       = 8,    -- concurrent ghost clones in workspace
	DashKey            = Enum.KeyCode.Q,
	DashDistance       = 30,   -- studs covered by one dash
	DashTime           = 0.6,  -- seconds the dash + pose run (30 studs = 50 studs/s)
	DashHoldEnd        = 0.75, -- fraction of an airborne dash that holds altitude
	DashCooldown       = 0.05, -- "infinite": just debounces key repeat
	AutoCastMinSeconds = 0.02, -- floor for the interval (the frame rate caps it anyway)
	AutoCastTapSeconds = 0.03, -- how long each injected press is held down
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
	InfDashActive          = false,
	AutoCastActive         = false,
	AutoCastInterval       = 0.5,      -- seconds (the panel shows s or ms)
	AutoCastUnit           = "s",      -- "s" | "ms", display only
	AutoCastMode           = "toggle", -- "toggle" | "hold"
	AutoCastActivation     = {},       -- a bind table; empty = unbound
	AutoCastTarget         = {},
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
local dirty = true          -- always flush once on boot

local function markDirty() dirty = true end

task.spawn(function()
	while Runtime.alive do
		if dirty then
			dirty = false
			saveSettings()
		end
		task.wait(1)        -- checks a flag; writes only when State moved
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

local function buildESP(character, player, jan)
	local root = character:WaitForChild("HumanoidRootPart", 3)
	if not root then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "PlayerHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.Enabled = State.PlayerESPActive
	highlight.Parent = character
	if jan then jan.add(highlight) end

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
	if jan then jan.add(billboard) end
end

function ESP.setEnabled(on)
	State.PlayerESPActive = on
	markDirty()
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

local playerESP = {}              -- player -> janitor that owns their ESP

local function clearESP(player)
	local jan = playerESP[player]
	if jan then
		jan.clean()
		playerESP[player] = nil
	end
end

local function watchPlayer(player)
	if player == LocalPlayer then return end
	local jan = newJanitor()
	RootJanitor.add(jan)
	playerESP[player] = jan

	jan.connect(player.CharacterAdded, function(character)
		if character:FindFirstChild("PlayerHighlight") then return end
		buildESP(character, player, jan)
	end)
	jan.connect(player.CharacterRemoving, function(character)
		local h = character:FindFirstChild("PlayerHighlight")
		if h then h:Destroy() end
	end)
	if player.Character then
		task.spawn(buildESP, player.Character, player, jan)
	end
end

for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
RootJanitor.connect(Players.PlayerAdded, watchPlayer)
RootJanitor.connect(Players.PlayerRemoving, clearESP)

-- =====================================================================
--  2 · CHARACTER (speed · multi jump)
-- =====================================================================
local currentHumanoid = nil

-- Locomotion animations we must never accelerate
local CORE_ANIMS = {
	"walk", "run", "idle", "jump", "fall", "climb", "swim", "sit",
	"toolnone", "pose", "emote", "dance", "land", "straf",
}

local function isCoreAnim(name)
	name = string.lower(name or "")
	for _, core in ipairs(CORE_ANIMS) do
		-- Token match: "run" hits "run_01" and "Run", but not
		-- "RunningSlash", which is a skill and should still glitch.
		if name == core
			or string.find(name, "^" .. core .. "[^%a]")
			or string.find(name, "[^%a]" .. core .. "$") then
			return true
		end
	end
	return false
end

-- One tolerance shared by every walk-speed comparison. Two different
-- thresholds (0.05 and 1.0) is what made refreshSpeed and the watchdog
-- disagree with each other.
local SPEED_EPSILON = 0.1

-- Shared raycast params for the safe-landing probe: allocated once
-- instead of every heartbeat, and re-bound to the current character
-- inside setupCharacter().
local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Exclude

local function targetWalkSpeed(humanoid)
	local base = humanoid:GetAttribute("ZenBaseSpeed") or Config.BaseWalkSpeed
	return base * activeMultiplier()
end

local function refreshSpeed(humanoid)
	if not humanoid or humanoid.Parent == nil then return end
	local target = targetWalkSpeed(humanoid)
	if math.abs(humanoid.WalkSpeed - target) > SPEED_EPSILON then
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

	-- bind the shared safe-landing probe to this character
	landParams.FilterDescendantsInstances = { character }

	janitor.connect(humanoid.Died, function() janitor.clean() end)
	janitor.connect(character.Destroying, function() janitor.clean() end)

	local applying = false
	janitor.connect(humanoid:GetPropertyChangedSignal("WalkSpeed"), function()
		if applying then return end
		if math.abs(humanoid.WalkSpeed - targetWalkSpeed(humanoid)) <= SPEED_EPSILON then
			return
		end
		if activeMultiplier() == 1 then
			-- Not boosting: the game just moved the goalposts, so adopt
			-- them instead of reverting a sprint power-up next frame.
			humanoid:SetAttribute("ZenBaseSpeed", humanoid.WalkSpeed)
			return
		end
		applying = true
		humanoid.WalkSpeed = targetWalkSpeed(humanoid)
		applying = false
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

	local vel = rootPart.AssemblyLinearVelocity

	-- Hold Space to fly / stay airborne. When the experience uses the
	-- JumpHeight model, JumpPower reads 0 and this branch would do
	-- nothing at all — derive the lift from JumpHeight instead.
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		local lift = humanoid.UseJumpPower
			and humanoid.JumpPower
			or math.sqrt(2 * workspace.Gravity * math.max(humanoid.JumpHeight, 3))
		rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, lift * 0.8, vel.Z)
		return
	end

	-- Optional safe landing: normal fall until the last 6 studs, then a
	-- squared decay bleeds the downward speed off for a soft touchdown.
	-- landParams is built once above and re-bound per character, so
	-- this costs no allocation per frame.
	if State.SafeLandActive and vel.Y < -25 then
		local hit = workspace:Raycast(rootPart.Position, Vector3.new(0, -9, 0), landParams)
		if hit then
			local clearance = hit.Distance - 3    -- root sits ~3 studs above the feet
			if clearance < 6 then
				local t = math.clamp(clearance / 6, 0, 1) -- 1 = untouched, 0 = touchdown
				rootPart.AssemblyLinearVelocity =
					Vector3.new(vel.X, vel.Y * t * t, vel.Z)
			end
		end
	end
end)

-- =====================================================================
--  3 · GLITCH ENGINE (one shared Heartbeat)
-- =====================================================================
local STRIP_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true,
	-- a cloned Tool left in workspace is pickup-able by other players,
	-- and cloned highlights / prompts / lights double-draw on the ghost
	Tool = true, Highlight = true, ProximityPrompt = true,
	PointLight = true, SpotLight = true, SurfaceLight = true,
	Sound = true, ParticleEmitter = true, Trail = true, Beam = true,
	Fire = true, Smoke = true, Sparkles = true,
	BillboardGui = true, SurfaceGui = true, Decal = true, Texture = true,
}

local lastGhostTick = 0
local liveGhosts = 0             -- capped by Config.GhostMaxLive
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
	liveGhosts = liveGhosts + 1
	clone.Destroying:Once(function()
		liveGhosts = math.max(0, liveGhosts - 1)
	end)
end

local function watchAnimations(animator, janitor)
	if not animator then return end
	local function attach(track)
		-- Never jitter locomotion: freezing walk/run/idle leaves the
		-- character sliding around in a held pose while Glitch is on.
		if isCoreAnim(track.Name) then return end
		jitteredTracks[track] = { lastSkip = 0, original = track.Speed }
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
			for track, meta in pairs(jitteredTracks) do
				pcall(function()
					if track.IsPlaying then
						track:AdjustSpeed(meta.original or 1)
					end
				end)
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
		local interval = math.max(Config.GhostMinInterval, Config.GhostFrameTime / mult)
		if moving
			and now - lastGhostTick >= interval
			and liveGhosts < Config.GhostMaxLive then
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
	markDirty()
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
	markDirty()
	bloom.Enabled = on
	tint.Enabled = on
end

-- =====================================================================
--  5a · INPUT BINDINGS (shared by AutoCast)
-- =====================================================================
-- A bind is a small table so it survives the JSON save file:
--   { kind = "key",   name   = "Q" }     keyboard key or gamepad button (an Enum.KeyCode name)
--   { kind = "mouse", button = 1 }       Mouse 1 / 2 / 3  (left / right / middle)
--   { kind = "vk",    vk     = 0x05 }    Mouse 4 / 5 (the side buttons), see below
--
-- Roblox has no UserInputType for a mouse's side buttons, so a plain script
-- can never see them. Where the executor provides iskeypressed() they are
-- polled by Windows virtual-key code instead (0x05 = X1, 0x06 = X2).
-- No iskeypressed? Remap the side buttons to F13-F15 in your mouse software:
-- Roblox does report those as ordinary keys.
local Binds = { session = nil, justBound = -1e9 }   -- "never": clicks right after load must still work

local VK_X1, VK_X2 = 0x05, 0x06
local SIDE_NAMES  = { [VK_X1] = "Mouse 4 (side)", [VK_X2] = "Mouse 5 (side)" }
local MOUSE_NAMES = { "Mouse 1 (left)", "Mouse 2 (right)", "Mouse 3 (middle)" }
local MOUSE_TYPES = {
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.MouseButton3,
}

Binds.sideSupported = type(iskeypressed) == "function"

-- Windows virtual-key codes, only used when VirtualInputManager is unavailable
-- and the executor offers keypress() / keyrelease() instead.
local VK_CODES = {
	Space = 0x20, Return = 0x0D, Backspace = 0x08, Tab = 0x09, Escape = 0x1B,
	LeftShift = 0xA0, RightShift = 0xA1, LeftControl = 0xA2, RightControl = 0xA3,
	LeftAlt = 0xA4, RightAlt = 0xA5, CapsLock = 0x14,
	Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28,
	Insert = 0x2D, Delete = 0x2E, Home = 0x24, End = 0x23, PageUp = 0x21, PageDown = 0x22,
}
do
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for i = 0, 9 do
		VK_CODES[digits[i + 1]] = 0x30 + i
		VK_CODES["Keypad" .. digits[i + 1]] = 0x60 + i
	end
	for i = 0, 25 do VK_CODES[string.char(65 + i)] = 0x41 + i end
	for i = 1, 12 do VK_CODES["F" .. i] = 0x6F + i end
end

-- VirtualInputManager is how a script injects input. It needs an elevated
-- identity, so it is looked up once and every call into it is pcall'd.
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local function keyCodeOf(name)
	if type(name) ~= "string" then return nil end
	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	return ok and code or nil
end

function Binds.valid(b)
	if type(b) ~= "table" then return false end
	if b.kind == "key" then return keyCodeOf(b.name) ~= nil end
	if b.kind == "mouse" then return MOUSE_TYPES[b.button] ~= nil end
	if b.kind == "vk" then return SIDE_NAMES[b.vk] ~= nil end
	return false
end

function Binds.name(b)
	if not Binds.valid(b) then return nil end
	if b.kind == "mouse" then return MOUSE_NAMES[b.button] end
	if b.kind == "vk" then return SIDE_NAMES[b.vk] end
	return b.name
end

function Binds.same(a, b)
	if not (Binds.valid(a) and Binds.valid(b)) or a.kind ~= b.kind then return false end
	return a.name == b.name and a.button == b.button and a.vk == b.vk
end

-- Turn a raw input into a bind: any keyboard key, any gamepad button, the three
-- mouse buttons Roblox can report. Anything else (movement, scroll) is ignored.
function Binds.fromInput(input)
	local t = input.UserInputType
	for i, mouseType in ipairs(MOUSE_TYPES) do
		if t == mouseType then return { kind = "mouse", button = i } end
	end
	if t == Enum.UserInputType.Keyboard or string.find(t.Name, "^Gamepad") then
		if input.KeyCode ~= Enum.KeyCode.Unknown then
			return { kind = "key", name = input.KeyCode.Name }
		end
	end
	return nil
end

-- Does this input event belong to that bind? ("vk" binds never arrive as events)
function Binds.matches(b, input)
	if b.kind == "mouse" then return input.UserInputType == MOUSE_TYPES[b.button] end
	if b.kind == "key" then
		return input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name == b.name
	end
	return false
end

-- Polled state of a side button (only meaningful for "vk" binds)
function Binds.isDown(b)
	if not Binds.sideSupported then return false end
	if type(isrbxactive) == "function" then
		local ok, active = pcall(isrbxactive)
		if ok and not active then return false end      -- game window isn't focused
	end
	local ok, down = pcall(iskeypressed, b.vk)
	return ok and down == true
end

-- Press or release a bind. Returns true if something accepted the event.
function Binds.send(b, down)
	if not Binds.valid(b) then return false end

	if b.kind == "key" then
		local code = keyCodeOf(b.name)
		if VIM and pcall(function() VIM:SendKeyEvent(down, code, false, game) end) then
			return true
		end
		local fn = down and keypress or keyrelease
		local vk = VK_CODES[b.name]
		return vk ~= nil and type(fn) == "function" and (pcall(fn, vk))
	end

	if b.kind == "mouse" then
		if VIM then
			local at = UserInputService:GetMouseLocation()
			if pcall(function() VIM:SendMouseButtonEvent(at.X, at.Y, b.button - 1, down, game, 1) end) then
				return true
			end
		end
		local press, release
		if b.button == 1 then press, release = mouse1press, mouse1release
		elseif b.button == 2 then press, release = mouse2press, mouse2release end
		local fn = down and press or release
		return type(fn) == "function" and (pcall(fn))
	end

	-- Mouse 4 / 5 as an *output*: best effort through the executor, unverified
	local fn = down and keypress or keyrelease
	return type(fn) == "function" and (pcall(fn, b.vk))
end

-- Capture ---------------------------------------------------------------
-- The next input of any kind becomes the bind. Esc cancels.
function Binds.endSession()
	local s = Binds.session
	if not s then return nil end
	Binds.session = nil
	if s.input then s.input:Disconnect() end
	if s.poll then s.poll:Disconnect() end
	return s
end

function Binds.cancelCapture()
	local s = Binds.endSession()
	if s and s.onCancel then s.onCancel() end
end

function Binds.beginCapture(onBind, onCancel)
	Binds.cancelCapture()               -- one capture at a time; the old box repaints itself
	local s = { onCancel = onCancel }
	Binds.session = s

	local function finish(bind)
		if Binds.session ~= s then return end
		Binds.endSession()
		Binds.justBound = os.clock()
		onBind(bind)
	end

	s.input = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			Binds.cancelCapture()
			return
		end
		local bind = Binds.fromInput(input)
		if bind then finish(bind) end
	end)

	-- Mouse 4 / 5 never arrive as input events, so watch for them directly
	if Binds.sideSupported then
		s.poll = RunService.Heartbeat:Connect(function()
			for _, vk in ipairs({ VK_X1, VK_X2 }) do
				if Binds.isDown({ vk = vk }) then
					finish({ kind = "vk", vk = vk })
					return
				end
			end
		end)
	end
end

RootJanitor.add({ clean = function() Binds.endSession() end })

-- =====================================================================
--  5b · AUTOCAST ENGINE
-- =====================================================================
-- Presses State.AutoCastTarget every State.AutoCastInterval seconds while
-- "casting". The activation bind starts and stops it (toggle) or runs it only
-- while held (hold). Nothing runs per frame unless a cast is in progress, or
-- the activation is a polled side button.
local AutoCast = {
	casting  = false,
	held     = nil,     -- the bind we currently hold down, so it can always be released
	tapStamp = 0,
	nextFire = 0,
	actDown  = false,   -- last polled state of a side-button activation
	conn     = nil,
	onChange = nil,     -- UI hooks, set by the panel
	onNote   = nil,
}

-- Saved JSON can be stale or hand-edited: keep only what we understand.
State.InfDashActive  = State.InfDashActive == true
State.AutoCastActive = State.AutoCastActive == true
if not Binds.valid(State.AutoCastActivation) then State.AutoCastActivation = {} end
if not Binds.valid(State.AutoCastTarget) then State.AutoCastTarget = {} end
if State.AutoCastUnit ~= "s" and State.AutoCastUnit ~= "ms" then State.AutoCastUnit = "s" end
if State.AutoCastMode ~= "toggle" and State.AutoCastMode ~= "hold" then State.AutoCastMode = "toggle" end
State.AutoCastInterval = math.clamp(tonumber(State.AutoCastInterval) or 0.5, Config.AutoCastMinSeconds, 3600)

local function changed()
	if AutoCast.onChange then AutoCast.onChange() end
end

local function notify(text)
	if AutoCast.onNote then AutoCast.onNote(text) end
end

-- Interval ----------------------------------------------------------------
function AutoCast.interval()
	return math.max(Config.AutoCastMinSeconds, tonumber(State.AutoCastInterval) or 0.5)
end

-- The number as shown in the box, in the unit the user picked
function AutoCast.number()
	local s = AutoCast.interval()
	if State.AutoCastUnit == "ms" then
		return string.format("%d", math.floor(s * 1000 + 0.5))
	end
	return string.format("%g", math.floor(s * 1000 + 0.5) / 1000)
end

function AutoCast.format()
	return AutoCast.number() .. " " .. State.AutoCastUnit
end

-- "0.5", ".25", "250ms", "1,5 s" -> seconds, unit. A suffix beats the unit chip.
function AutoCast.parseInterval(text)
	text = string.lower(tostring(text or ""))
	text = string.gsub(text, ",", ".")
	local num, unit = string.match(text, "^%s*(%d*%.?%d+)%s*(m?s?)%s*$")
	local value = num and tonumber(num)
	if not value or unit == "m" then return nil end
	if unit == "" then unit = State.AutoCastUnit end
	local seconds = (unit == "ms") and value / 1000 or value
	return math.clamp(seconds, Config.AutoCastMinSeconds, 3600), unit
end

-- Pressing --------------------------------------------------------------
function AutoCast.releaseHeld()
	local bind = AutoCast.held
	if bind then
		AutoCast.held = nil
		Binds.send(bind, false)
	end
end

-- One press: down now, up a few frames later, so games that poll IsKeyDown
-- (not just InputBegan) still see it.
function AutoCast.tap()
	local target = State.AutoCastTarget
	AutoCast.releaseHeld()              -- never leave a previous press hanging
	if not Binds.send(target, true) then return false end
	AutoCast.held = target
	local stamp = os.clock()
	AutoCast.tapStamp = stamp
	task.delay(math.min(Config.AutoCastTapSeconds, AutoCast.interval() * 0.5), function()
		if AutoCast.held == target and AutoCast.tapStamp == stamp then
			AutoCast.releaseHeld()
		end
	end)
	return true
end

-- Scheduling ------------------------------------------------------------
-- The Heartbeat is connected only while it has work: a cast in progress, or
-- an activation bound to a side button (which has to be polled).
function AutoCast.sync()
	local polling = State.AutoCastActive and State.AutoCastActivation.kind == "vk"
	local needed = State.AutoCastActive and (AutoCast.casting or polling)
	if needed and not AutoCast.conn then
		AutoCast.conn = RunService.Heartbeat:Connect(AutoCast.step)
	elseif not needed and AutoCast.conn then
		AutoCast.conn:Disconnect()
		AutoCast.conn = nil
	end
end

function AutoCast.start()
	if AutoCast.casting or not State.AutoCastActive then return end
	if not Binds.valid(State.AutoCastTarget) then
		notify("bind a target key first")
		return
	end
	AutoCast.casting = true
	AutoCast.nextFire = os.clock()      -- the first press is immediate
	AutoCast.sync()
	changed()
end

function AutoCast.stop()
	local was = AutoCast.casting
	AutoCast.casting = false
	AutoCast.releaseHeld()
	AutoCast.sync()
	if was then changed() end
end

-- What the activation bind does when it goes down / up
function AutoCast.activate(down)
	if not State.AutoCastActive then return end
	if State.AutoCastMode == "hold" then
		if down then AutoCast.start() else AutoCast.stop() end
	elseif down then
		if AutoCast.casting then AutoCast.stop() else AutoCast.start() end
	end
end

function AutoCast.step()
	-- Mouse 4 / 5 never raise an event, so an activation bound to one is polled here
	local act = State.AutoCastActivation
	if act.kind == "vk" then
		local down = Binds.isDown(act)
		if down ~= AutoCast.actDown then
			AutoCast.actDown = down
			AutoCast.activate(down)
		end
	end

	if not AutoCast.casting then return end
	local now = os.clock()
	if now < AutoCast.nextFire then return end

	if not AutoCast.tap() then
		AutoCast.stop()
		notify("can't send " .. (Binds.name(State.AutoCastTarget) or "that key") .. " from here")
		return
	end

	-- advance by whole intervals so the average rate is exact; if a long hitch
	-- put us more than one interval behind, resync instead of firing a burst
	local gap = AutoCast.interval()
	AutoCast.nextFire = AutoCast.nextFire + gap
	if now - AutoCast.nextFire > gap then AutoCast.nextFire = now + gap end
end

-- Settings --------------------------------------------------------------
function AutoCast.setEnabled(on)
	State.AutoCastActive = on
	if not on then AutoCast.stop() end
	AutoCast.sync()
	changed()
	markDirty()
end

-- Returns true, or false plus a reason. The same key can't be both halves:
-- the injected press would trigger its own activation.
function AutoCast.setBind(slot, bind)
	local other = (slot == "activation") and State.AutoCastTarget or State.AutoCastActivation
	if Binds.same(bind, other) then
		return false, "already used as the " .. ((slot == "activation") and "target" or "activation") .. " key"
	end
	if slot == "activation" then
		State.AutoCastActivation = bind
		-- a side button that is still held down can't count as a fresh press
		AutoCast.actDown = (bind.kind == "vk") and Binds.isDown(bind)
	else
		AutoCast.releaseHeld()
		State.AutoCastTarget = bind
	end
	markDirty()
	AutoCast.sync()
	changed()
	return true
end

function AutoCast.shutdown()
	AutoCast.casting = false
	AutoCast.releaseHeld()
	if AutoCast.conn then
		AutoCast.conn:Disconnect()
		AutoCast.conn = nil
	end
end

-- Input ----------------------------------------------------------------
RootJanitor.connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or Binds.session or not State.AutoCastActive then return end
	if os.clock() - Binds.justBound < 0.15 then return end      -- the very press that just set the bind
	if Binds.matches(State.AutoCastActivation, input) then AutoCast.activate(true) end
end)

RootJanitor.connect(UserInputService.InputEnded, function(input)
	-- no gameProcessed check: a release must always be able to stop a held cast
	if State.AutoCastActive and State.AutoCastMode == "hold"
		and Binds.matches(State.AutoCastActivation, input) then
		AutoCast.activate(false)
	end
end)

RootJanitor.add({ clean = function() AutoCast.shutdown() end })
AutoCast.sync()

-- =====================================================================
--  5c · INF DASH
-- =====================================================================
-- Q dashes DashDistance studs in whichever horizontal direction you are
-- moving (or straight ahead if you are standing still), with no cooldown:
--   · Anti-trip: disables FallingDown / Ragdoll states and locks root
--     upright with an AlignOrientation + zeroed angular velocity so the
--     character never trips or stumbles during or after a dash.
--   · Phase-through: ignores players and NPCs in the wall probe and disables
--     CanCollide on their body parts on RunService.Stepped for the duration
--     of the dash, restoring every part when the dash finishes.
--   · Vertical hold: an airborne dash holds altitude for the first 75% of
--     its length, then gravity resumes for the final 25%.
--   · Directional pose: applied on RunService.Stepped (right after the
--     Animator steps), wiping Transform on posed joints for the full 0.6 s.
local InfDash = { run = nil, lastEnd = 0 }

-- Degrees in Part0's local axes (+X right, +Y up, -Z forward).
-- Around +X: negative pitches the torso forward, positive swings a hanging leg forward.
-- Around +Z: negative banks the torso right, positive banks it left.
local DASH_POSE = {
	lean     = 18,  -- root tilt toward the dash direction
	waist    = 10,  -- extra upper-torso lean on R15 so the tilt reads clearly
	leftHip  = 38,  -- left leg forward
	rightHip = -26, -- right leg back
	knee     = -18, -- slight knee bend on R15 so the legs don't look stiff
	arm      = -24, -- arms swept slightly opposite the dash
}
local POSE_IN, POSE_OUT = 0.08, 0.10        -- ease-in / ease-out inside Config.DashTime

-- Own character limb parts whose CanCollide is suppressed mid-dash so a
-- tilted leg or foot never snags a floor seam and trips the rig.
local SELF_LIMBS = {
	LeftFoot = true, RightFoot = true,
	LeftLowerLeg = true, RightLowerLeg = true,
	LeftUpperLeg = true, RightUpperLeg = true,
	LeftHand = true, RightHand = true,
	LeftLowerArm = true, RightLowerArm = true,
	LeftUpperArm = true, RightUpperArm = true,
	["Left Leg"] = true, ["Right Leg"] = true,
	["Left Arm"] = true, ["Right Arm"] = true,
}

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Vertical hold, in two acts. For the first DashHoldEnd (75%) of an airborne
-- dash the constraint pins Y velocity to 0 (MaxAxesForce.Y = huge against
-- VectorVelocity.Y = 0) so you carry the distance flat instead of nose-diving.
-- At the 75% mark the Y force limit drops to 0, gravity takes over from a
-- standstill, and the final 25% of the dash is a normal fall — so the drop
-- starts where you expect it and not before. Grounded dashes never hold
-- (slopes and steps keep working), and an active hold-Space hover (multi
-- jump) keeps owning vertical the whole way through.
local function applyVerticalHold(mover, humanoid, t)
	local hovering = State.MultiJumpActive
		and UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local holdWindow = (t or 0) < Config.DashTime * Config.DashHoldEnd
	local hold = holdWindow and (not hovering)
		and humanoid.FloorMaterial == Enum.Material.Air
	mover.MaxAxesForce = Vector3.new(math.huge, hold and math.huge or 0, math.huge)
end

-- Prevent the Humanoid from entering FallingDown / Ragdoll (the states that
-- make a character trip and stumble around when moving fast over seams).
local function setAntiTrip(humanoid, enabled)
	if not humanoid or not humanoid.Parent then return end
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not enabled)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not enabled)
	end)
	if enabled then
		-- Read the state's *name* inside the pcall: PlatformStand is not a
		-- member of Enum.HumanoidStateType on every engine build, and
		-- indexing it directly crashed the boot. Comparing the name string
		-- also sidesteps type() returning "userdata" for EnumItems.
		local ok, stateName = pcall(function() return humanoid:GetState().Name end)
		if ok and (stateName == "FallingDown"
			or stateName == "Ragdoll"
			or stateName == "PlatformStand") then
			humanoid.PlatformStand = false
			pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Running) end)
		end
	end
end

-- If `inst` belongs to a player character or an NPC rig, return that Model.
local function actorModelOf(inst, selfChar)
	local node = inst
	while node and node ~= workspace do
		if node:IsA("Model") and node ~= selfChar then
			if node:FindFirstChildOfClass("Humanoid")
				or node:FindFirstChildOfClass("AnimationController") then
				return node
			end
		end
		node = node.Parent
	end
	return nil
end

local function ghostPart(run, part)
	if not part or not part:IsA("BasePart") then return end
	if run.ghostedParts[part] == nil then
		run.ghostedParts[part] = part.CanCollide
	end
	part.CanCollide = false
end

local function ghostModel(run, model)
	if not model or run.ghostedModels[model] then return end
	run.ghostedModels[model] = true
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			ghostPart(run, desc)
		end
	end
end

-- Gather nearby players and NPCs so we can pass right through them.
local function collectPhaseTargets(run, char, root)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			ghostModel(run, player.Character)
		end
	end

	local maxRange = Config.DashDistance + 20
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("Humanoid") or desc:IsA("AnimationController") then
			local model = desc.Parent
			if model and model:IsA("Model") and model ~= char and not run.ghostedModels[model] then
				local pivot = model:FindFirstChild("HumanoidRootPart")
					or model.PrimaryPart
					or model:FindFirstChildWhichIsA("BasePart")
				if not pivot or (pivot.Position - root.Position).Magnitude <= maxRange then
					ghostModel(run, model)
				end
			end
		end
	end

	-- Suppress CanCollide on our own limbs so tilted legs never snag the floor
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") and (SELF_LIMBS[desc.Name] or desc:FindFirstAncestorOfClass("Accessory") or desc:FindFirstAncestorOfClass("Tool")) then
			ghostPart(run, desc)
		end
	end
end

-- Re-assert CanCollide = false every Stepped frame (Humanoid re-enables
-- Torso / UpperTorso / LowerTorso collision each step).
local function maintainPhase(run, char, root)
	if workspace.GetPartBoundsInRadius then
		local ok, parts = pcall(workspace.GetPartBoundsInRadius, workspace, root.Position, 10)
		if ok and parts then
			for _, part in ipairs(parts) do
				local model = actorModelOf(part, char)
				if model then ghostModel(run, model) end
			end
		end
	end
	for part in pairs(run.ghostedParts) do
		if part.Parent then
			part.CanCollide = false
		end
	end
end

-- Whichever horizontal direction the player is currently going:
--   1. Humanoid.MoveDirection (works for WASD, shift-lock, thumbsticks)
--   2. Held WASD / arrow keys relative to the camera if MoveDirection hasn't ticked yet
--   3. Character facing direction when standing completely still
local function dashDirection(humanoid, root)
	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	if flatMove.Magnitude > 0.01 then
		return flatMove.Unit
	end

	local cam = workspace.CurrentCamera
	local basis = (cam and cam.CFrame) or root.CFrame
	local fwd = Vector3.new(basis.LookVector.X, 0, basis.LookVector.Z)
	local right = Vector3.new(basis.RightVector.X, 0, basis.RightVector.Z)
	local wish = Vector3.new(0, 0, 0)
	if fwd.Magnitude > 0.01 then
		fwd = fwd.Unit
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			wish = wish + fwd
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			wish = wish - fwd
		end
	end
	if right.Magnitude > 0.01 then
		right = right.Unit
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			wish = wish + right
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			wish = wish - right
		end
	end
	if wish.Magnitude > 0.01 then
		return wish.Unit
	end

	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.01 then
		return flatLook.Unit
	end
	return nil
end

-- Joints that carry the dash pose, for either rig type
local function dashJoints(char, humanoid)
	local found = {}
	local function add(partName, jointName, role)
		local part = char:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint and joint:IsA("Motor6D") then
			table.insert(found, { joint = joint, base = joint.C0, role = role })
		end
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		add("LowerTorso", "Root", "lean")
		add("UpperTorso", "Waist", "waist")
		add("LeftUpperLeg", "LeftHip", "left")
		add("RightUpperLeg", "RightHip", "right")
		add("LeftLowerLeg", "LeftKnee", "knee")
		add("RightLowerLeg", "RightKnee", "knee")
		add("LeftUpperArm", "LeftShoulder", "arm")
		add("RightUpperArm", "RightShoulder", "arm")
	else
		add("HumanoidRootPart", "RootJoint", "lean")
		add("Torso", "Left Hip", "left")
		add("Torso", "Right Hip", "right")
		add("Torso", "Left Shoulder", "arm")
		add("Torso", "Right Shoulder", "arm")
	end
	return found
end

-- Rotation in Part0's axes (+X right, +Y up, -Z forward), scaled by weight.
-- fwdDot (+1 ahead, -1 behind) and rightDot (+1 right, -1 left) tilt the
-- character toward the world-space dash direction regardless of facing.
local function posedRotation(entry, weight, fwdDot, rightDot)
	local pitch, roll = 0, 0
	local role = entry.role
	if role == "lean" then
		pitch = -fwdDot * DASH_POSE.lean
		roll  = -rightDot * DASH_POSE.lean
	elseif role == "waist" then
		pitch = -fwdDot * DASH_POSE.waist
		roll  = -rightDot * DASH_POSE.waist
	elseif role == "left" then
		pitch = DASH_POSE.leftHip
		roll  = -rightDot * (DASH_POSE.lean * 0.35)
	elseif role == "right" then
		pitch = DASH_POSE.rightHip
		roll  = -rightDot * (DASH_POSE.lean * 0.35)
	elseif role == "knee" then
		pitch = DASH_POSE.knee
	elseif role == "arm" then
		local dirSign = (math.abs(fwdDot) >= 0.1) and fwdDot or 1
		pitch = dirSign * DASH_POSE.arm
	end
	return CFrame.Angles(math.rad(pitch) * weight, 0, math.rad(roll) * weight)
end

local function applyJointPose(entry, weight, fwdDot, rightDot)
	local base = entry.base
	local baseRot = base - base.Position
	local rot = posedRotation(entry, weight, fwdDot, rightDot)
	-- Wipe the Animator's walk/run keyframe on this joint first
	pcall(function() entry.joint.Transform = CFrame.new() end)
	local ok = pcall(function()
		entry.joint.C0 = CFrame.new(base.Position) * rot * baseRot
	end)
	if not ok then
		-- Fallback when C0 is locked (AvatarJointUpgrade): conjugate into Transform
		pcall(function() entry.joint.Transform = baseRot:Inverse() * rot * baseRot end)
	end
end

local function stopMove(run)
	if run.gyro then
		run.gyro:Destroy()
		run.gyro = nil
	end
	if run.mover then
		run.mover:Destroy()
		run.mover = nil
	end
	if run.attachment then
		run.attachment:Destroy()
		run.attachment = nil
	end
	if run.root and run.root.Parent then
		-- keep vertical velocity, drop horizontal dash momentum and any spin
		local v = run.root.AssemblyLinearVelocity
		run.root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		run.root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
end

function InfDash.setEnabled(on)
	State.InfDashActive = on
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then setAntiTrip(humanoid, on) end
	if not on then InfDash.cancel() end
end

function InfDash.cancel()
	local run = InfDash.run
	if not run then return end
	InfDash.run = nil
	InfDash.lastEnd = os.clock()
	if run.stepConn then run.stepConn:Disconnect() end
	if run.conn then run.conn:Disconnect() end
	stopMove(run)
	if run.humanoid and run.humanoid.Parent then
		if run.autoRotate ~= nil then
			run.humanoid.AutoRotate = run.autoRotate
		end
		setAntiTrip(run.humanoid, State.InfDashActive)
	end
	if run.ghostedParts then
		for part, origCollide in pairs(run.ghostedParts) do
			if part.Parent then
				pcall(function() part.CanCollide = origCollide end)
			end
		end
	end
	for _, entry in ipairs(run.joints) do
		if entry.joint.Parent then
			pcall(function() entry.joint.C0 = entry.base end)
			pcall(function() entry.joint.Transform = CFrame.new() end)
		end
	end
end

function InfDash.start()
	if InfDash.run or os.clock() - InfDash.lastEnd < Config.DashCooldown then return end

	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.Sit then return end

	setAntiTrip(humanoid, true)

	local dir = dashDirection(humanoid, root)
	if not dir then return end

	-- Stop short of real walls, but ignore every player character and NPC
	local exclude = { char }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true

	local distance = Config.DashDistance
	for _, height in ipairs({ 1.5, 0, -1.2 }) do
		local origin = root.Position + Vector3.new(0, height, 0)
		for _ = 1, 12 do
			local hit = workspace:Raycast(origin, dir * (Config.DashDistance + 2), params)
			if not hit then break end
			local actor = actorModelOf(hit.Instance, char)
			if actor then
				table.insert(exclude, actor)
				params.FilterDescendantsInstances = exclude
			else
				-- Ignore walkable slopes/ramps (Normal.Y > 0.5) so inclines don't block the dash
				if not hit.Normal or hit.Normal.Y <= 0.5 then
					distance = math.min(distance, math.max(hit.Distance - 2, 0))
				end
				break
			end
		end
	end
	if distance < 1 then return end

	-- Horizontal-only velocity: gravity and jumping keep working mid-dash
	local attachment = Instance.new("Attachment")
	attachment.Name = "ZenDashAttachment"
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Name = "ZenDash"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	mover.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	mover.VectorVelocity = dir * (distance / Config.DashTime)   -- dir is horizontal, so Y is 0
	mover.Parent = root
	applyVerticalHold(mover, humanoid, 0)

	-- Lock root upright so floor seams or bumps can never tip or spin the character
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then flatLook = dir else flatLook = flatLook.Unit end

	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "ZenDashGyro"
	gyro.Attachment0 = attachment
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.RigidityEnabled = true
	gyro.MaxTorque = math.huge
	gyro.Responsiveness = 200
	gyro.CFrame = CFrame.new(Vector3.new(0, 0, 0), flatLook)
	gyro.Parent = root

	root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	local prevAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	local run = {
		humanoid = humanoid,
		autoRotate = prevAutoRotate,
		root = root,
		dir = dir,
		attachment = attachment,
		mover = mover,
		gyro = gyro,
		joints = dashJoints(char, humanoid),
		ghostedParts = {},
		ghostedModels = {},
		startedAt = os.clock(),
	}
	InfDash.run = run

	collectPhaseTargets(run, char, root)

	-- Runs for the entire Config.DashTime (0.6 s): keep phasing through
	-- players/NPCs, keep root upright, hold the directional tilt, then restore.
	local function stepDash()
		if InfDash.run ~= run then return end
		local t = os.clock() - run.startedAt
		if t >= Config.DashTime or not root.Parent or humanoid.Health <= 0 then
			InfDash.cancel()
			return
		end

		setAntiTrip(humanoid, true)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		maintainPhase(run, char, root)
		-- re-asserted every frame: running off a ledge starts the hold,
		-- touching down mid-dash releases it, and the hold window itself
		-- expires at DashHoldEnd so the last quarter of the dash falls
		applyVerticalHold(run.mover, humanoid, t)

		local fadeOutStart = math.max(POSE_IN, Config.DashTime - POSE_OUT)
		local weight = smooth(t / POSE_IN) * (1 - smooth((t - fadeOutStart) / POSE_OUT))

		local curLook = root.CFrame.LookVector
		local right = root.CFrame.RightVector
		local fwdDot = math.clamp(curLook.X * run.dir.X + curLook.Z * run.dir.Z, -1, 1)
		local rightDot = math.clamp(right.X * run.dir.X + right.Z * run.dir.Z, -1, 1)

		for _, entry in ipairs(run.joints) do
			if entry.joint.Parent then
				applyJointPose(entry, weight, fwdDot, rightDot)
			end
		end
	end

	if RunService.Stepped then
		run.stepConn = RunService.Stepped:Connect(stepDash)
	end
	run.conn = RunService.Heartbeat:Connect(stepDash)
end

RootJanitor.connect(LocalPlayer.CharacterAdded, function(char)
	if not State.InfDashActive then return end
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid and State.InfDashActive then
		setAntiTrip(humanoid, true)
	end
end)
if State.InfDashActive and LocalPlayer.Character then
	local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then setAntiTrip(humanoid, true) end
end

RootJanitor.connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or Binds.session or not State.InfDashActive then return end
	if input.KeyCode == Config.DashKey then InfDash.start() end
end)

RootJanitor.add({
	clean = function()
		InfDash.cancel()
		local char = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then setAntiTrip(humanoid, false) end
	end,
})

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
		if id == "fast" or id == "slow" then
			if currentHumanoid then refreshSpeed(currentHumanoid) end
		end
		markDirty()
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
		markDirty()
		-- Safe Landing is nested: it only appears while Multi Jump is on.
		-- Its value is preserved (and ignored while Multi Jump is off).
		if safeLandRow then safeLandRow.Visible = v end
	end
)

safeLandRow = addToggle("↳ safe landing",
	function() return State.SafeLandActive end,
	function(v)
		State.SafeLandActive = v
		markDirty()
	end,
	{ muted = true, visible = State.MultiJumpActive }
)

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
	if currentHumanoid then refreshSpeed(currentHumanoid) end
	markDirty()
end)
updateStepperVisuals()

addSectionLabel("combat")
addToggle("inf dash · " .. Config.DashKey.Name,
	function() return State.InfDashActive end,
	function(v)
		InfDash.setEnabled(v)
		markDirty()
	end
)

-- AutoCast: the toggle, then a dropdown holding its three inputs
local autoCastBox
addToggle("autocast",
	function() return State.AutoCastActive end,
	function(v)
		AutoCast.setEnabled(v)
		if not v then Binds.cancelCapture() end
		if autoCastBox then autoCastBox.Visible = v end
	end
)

do
	autoCastBox = new("Frame", {
		Name = "AutoCastOptions",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.bg,
		BorderSizePixel = 0,
		Visible = State.AutoCastActive,
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, autoCastBox)
	new("UIStroke", { Color = THEME.stroke, Thickness = 1 }, autoCastBox)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, autoCastBox)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, autoCastBox)

	local function row(labelText, order)
		local r = new("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, autoCastBox)
		new("TextLabel", {
			Size = UDim2.new(0, 64, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = THEME.dim,
			Text = labelText,
		}, r)
		return r
	end

	-- right-aligned control; xOffset shifts it left to make room for a neighbour
	local function field(parent, className, width, xOffset, props)
		props.Size = UDim2.fromOffset(width, 24)
		props.Position = UDim2.new(1, xOffset, 0.5, 0)
		props.AnchorPoint = Vector2.new(1, 0.5)
		props.BackgroundColor3 = THEME.off
		props.TextColor3 = props.TextColor3 or THEME.text
		props.Font = Enum.Font.GothamBold
		props.TextSize = props.TextSize or 11
		props.BorderSizePixel = 0
		local f = new(className, props, parent)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, f)
		return f
	end

	local function flash(inst)
		inst.BackgroundColor3 = Color3.fromRGB(122, 46, 46)
		TweenService:Create(inst, TweenInfo.new(0.6), { BackgroundColor3 = THEME.off }):Play()
	end

	-- status line + footnote (rows 4 and 5) ----------------------------
	local statusLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = THEME.dim,
		Text = "",
	}, autoCastBox)

	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Font = Enum.Font.Gotham,
		TextSize = 9,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.dim,
		Text = Binds.sideSupported
			and "Esc cancels a capture · Mouse 4/5 are read through iskeypressed"
			or "Esc cancels a capture · no iskeypressed here, so Mouse 4/5 can't be seen (remap them to F13-F15)",
	}, autoCastBox)

	local noteText, noteUntil = nil, 0
	local function refreshStatus()
		local act = Binds.name(State.AutoCastActivation)
		local tgt = Binds.name(State.AutoCastTarget)
		local text, color = nil, THEME.dim
		if AutoCast.casting then
			text = "● casting · every " .. AutoCast.format() .. " → " .. (tgt or "?")
			color = THEME.accent
		elseif noteText and os.clock() < noteUntil then
			text, color = noteText, Color3.fromRGB(255, 130, 130)
		elseif not (act and tgt) then
			text = "bind both keys to arm"
		elseif State.AutoCastMode == "hold" then
			text = "ready · hold " .. act
		else
			text = "ready · press " .. act
		end
		statusLabel.Text = text
		statusLabel.TextColor3 = color
	end

	local function note(text)
		noteText, noteUntil = text, os.clock() + 3.5
		refreshStatus()
		task.delay(3.6, refreshStatus)
	end

	-- 1 · interval --------------------------------------------------------
	local intervalRow = row("interval", 1)
	local unitBtn = field(intervalRow, "TextButton", 34, 0, {
		Text = "", TextColor3 = THEME.accent, AutoButtonColor = false,
	})
	local intervalBox = field(intervalRow, "TextBox", 132, -38, {
		Text = "",
		PlaceholderText = "0.5  or  500ms",
		PlaceholderColor3 = THEME.dim,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local function showInterval()
		intervalBox.Text = AutoCast.number()
		unitBtn.Text = State.AutoCastUnit
	end

	intervalBox.FocusLost:Connect(function()
		local seconds, unit = AutoCast.parseInterval(intervalBox.Text)
		if seconds then
			State.AutoCastInterval = seconds
			State.AutoCastUnit = unit
			markDirty()
		else
			flash(intervalBox)
		end
		showInterval()
		refreshStatus()
	end)

	unitBtn.MouseButton1Click:Connect(function()
		State.AutoCastUnit = (State.AutoCastUnit == "s") and "ms" or "s"
		markDirty()
		showInterval()
		refreshStatus()
	end)

	-- click the box, then press anything: key, mouse button, side button ------
	local function keyBox(parent, slot, width, xOffset)
		local btn = field(parent, "TextButton", width, xOffset, { Text = "", AutoButtonColor = false })
		local ring = new("UIStroke", { Color = THEME.accent, Thickness = 1, Enabled = false }, btn)

		local function paint()
			local name = Binds.name((slot == "activation") and State.AutoCastActivation or State.AutoCastTarget)
			btn.Text = name or "click to bind"
			btn.TextColor3 = name and THEME.text or THEME.dim
			ring.Enabled = false
		end

		btn.MouseButton1Click:Connect(function()
			-- if this very click was the capture (Mouse 1 just got bound), don't start another
			if os.clock() - Binds.justBound < 0.35 then return end
			intervalBox:ReleaseFocus()
			btn.Text = "press any key…"
			btn.TextColor3 = THEME.accent
			ring.Enabled = true
			Binds.beginCapture(function(bind)
				local ok, why = AutoCast.setBind(slot, bind)
				paint()
				if not ok then
					flash(btn)
					note(why)
				end
				refreshStatus()
			end, paint)
		end)

		paint()
	end

	-- 2 · activation key (+ toggle / hold) ---------------------------------
	local activationRow = row("activation", 2)
	local modeBtn = field(activationRow, "TextButton", 48, 0, {
		Text = "", TextColor3 = THEME.accent, TextSize = 10, AutoButtonColor = false,
	})
	keyBox(activationRow, "activation", 118, -52)

	local function showMode()
		modeBtn.Text = string.upper(State.AutoCastMode)
	end

	modeBtn.MouseButton1Click:Connect(function()
		State.AutoCastMode = (State.AutoCastMode == "toggle") and "hold" or "toggle"
		AutoCast.stop()
		markDirty()
		showMode()
		refreshStatus()
	end)

	-- 3 · target key -------------------------------------------------------
	keyBox(row("target", 3), "target", 170, 0)

	AutoCast.onChange = refreshStatus
	AutoCast.onNote = note
	showInterval()
	showMode()
	refreshStatus()
end

addSectionLabel("visuals")
addToggle("player esp",
	function() return State.PlayerESPActive end,
	ESP.setEnabled)
addToggle("zen glow",
	function() return State.KillGlowActive end,
	Glow.setEnabled)
addToggle("glitch trail",
	function() return State.GlitchActive end,
	function(v)
		State.GlitchActive = v
		markDirty()
	end)

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

-- Unload has to undo the world before it severs anything: connections
-- are cheap to drop, but a boosted WalkSpeed, a frozen animation, a
-- neutered prompt, a half-posed dash and someone else's red outline
-- all outlive them.
local function unload(reason)
	if not Runtime.alive then return end
	Runtime.alive = false          -- stops the save loop
	saveSettings()

	-- 1 · walk every side effect back
	Prompts.setEnabled(false)      -- restores HoldDuration on prompts
	InfDash.cancel()               -- frees the mover and puts the joints back
	AutoCast.shutdown()            -- releases a held key, stops the loop
	Binds.endSession()             -- abandons an open key capture
	for track, meta in pairs(jitteredTracks) do
		pcall(function()
			if track.IsPlaying then track:AdjustSpeed(meta.original or 1) end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local h = char:FindFirstChild("PlayerHighlight")
			if h then h:Destroy() end
			local root = char:FindFirstChild("HumanoidRootPart")
			local tag = root and root:FindFirstChild("PlayerLabel")
			if tag then tag:Destroy() end
		end
	end
	if currentHumanoid and currentHumanoid.Parent then
		currentHumanoid.WalkSpeed =
			currentHumanoid:GetAttribute("ZenBaseSpeed") or Config.BaseWalkSpeed
		currentHumanoid:SetAttribute("ZenBaseSpeed", nil)
	end

	-- 2 · only now cut the connections
	RootJanitor.clean()
	_G.__ZenGlitchJanitor = nil
	print("[ZenGlitch] unloaded cleanly — " .. tostring(reason))
end

closeBtn.MouseButton1Click:Connect(function() unload("panel close") end)

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

-- Auto-reload across teleports (Universal-Misc.2.lua)
if queue_on_teleport then
	queue_on_teleport([[
		repeat task.wait() until game:IsLoaded()
		task.wait(2)
		if _G.__ZenGlitchJanitor then
			pcall(function() _G.__ZenGlitchJanitor.clean() end)
			_G.__ZenGlitchJanitor = nil
		end

		-- Auto-reload across teleports (Universal-Misc.2.lua)
		local URL = "https://raw.githubusercontent.com/perpy08/RBXScripts/main/Universal-Misc.2.lua"
		local src
		if type(request) == "function" then          -- executor-native first
			local ok, res = pcall(request, { Url = URL, Method = "GET" })
			if ok and res and res.Body then src = res.Body end
		end
		if not src then                              -- then the legacy path
			local ok, body = pcall(game.HttpGet, game, URL)
			if ok and body then src = body end
		end
		if src then
			local fn, err = loadstring(src)
			if fn then fn()
			else warn("[ZenGlitch] reload compile failed: " .. tostring(err)) end
		else
			warn("[ZenGlitch] reload fetch failed — continuing without auto-reload")
		end
	]])
end

print("[ZenGlitch] Universal Misc loaded — Alt / RightShift toggles the panel")
 
