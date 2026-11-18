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
	DashTime           = 0.2,  -- seconds the dash lasts (30 studs = 150 studs/s)
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
-- Q dashes DashDistance studs the way the character is facing, with no
-- cooldown. Roblox can't author an animation asset at runtime, so the dash
-- pose is driven straight through the character's Motor6D joints instead.
local InfDash = { run = nil, lastEnd = 0 }

-- Degrees. Every rotation is about the parent part's X axis: a positive angle
-- swings a limb forward, a negative one swings it back. The leaning body
-- carries the legs with it, so the legs end up at leftHip - lean (forward)
-- and rightHip - lean (further back).
local DASH_POSE = { lean = 14, leftHip = 38, rightHip = -24 }
local POSE_IN, POSE_OUT = 0.06, 0.14        -- ease-in / ease-out, seconds

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The three joints that carry the pose, for either rig type
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
		add("LeftUpperLeg", "LeftHip", "left")
		add("RightUpperLeg", "RightHip", "right")
	else
		add("HumanoidRootPart", "RootJoint", "lean")
		add("Torso", "Left Hip", "left")
		add("Torso", "Right Hip", "right")
	end
	return found
end

local function posedC0(entry, weight)
	local degrees = DASH_POSE.rightHip
	if entry.role == "lean" then
		degrees = -DASH_POSE.lean           -- negative about X pitches the body forward
	elseif entry.role == "left" then
		degrees = DASH_POSE.leftHip
	end
	local base = entry.base
	-- Rotate about the joint's own pivot, in the parent part's axes, so this is
	-- right whatever orientation a rig's C0 happens to have (R6 differs from R15).
	return CFrame.new(base.Position)
		* CFrame.Angles(math.rad(degrees) * weight, 0, 0)
		* (base - base.Position)
end

local function stopMove(run)
	if not run.mover then return end
	run.mover:Destroy()
	run.mover = nil
	if run.attachment then
		run.attachment:Destroy()
		run.attachment = nil
	end
	if run.root.Parent then
		-- keep falling, but drop the dash momentum so we don't skate off afterwards
		local v = run.root.AssemblyLinearVelocity
		run.root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	end
end

function InfDash.cancel()
	local run = InfDash.run
	if not run then return end
	InfDash.run = nil
	InfDash.lastEnd = os.clock()
	if run.conn then run.conn:Disconnect() end
	stopMove(run)
	for _, entry in ipairs(run.joints) do
		if entry.joint.Parent then entry.joint.C0 = entry.base end
	end
end

function InfDash.start()
	if InfDash.run or os.clock() - InfDash.lastEnd < Config.DashCooldown then return end

	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.Sit then return end

	-- Forward = the way the character faces, flattened onto the ground
	local look = root.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	-- Stop short of walls: rays from head, chest and feet; the nearest hit wins.
	-- (At ~150 studs/s a thin wall could otherwise be tunnelled straight through.)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true         -- triggers and decor don't block a dash

	local distance = Config.DashDistance
	for _, height in ipairs({ 1.5, 0, -2 }) do
		local origin = root.Position + Vector3.new(0, height, 0)
		local hit = workspace:Raycast(origin, dir * (Config.DashDistance + 2), params)
		if hit then distance = math.min(distance, math.max(hit.Distance - 2, 0)) end   -- 2 = body radius
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
	mover.VectorVelocity = dir * (distance / Config.DashTime)
	mover.Parent = root

	local run = {
		root = root,
		attachment = attachment,
		mover = mover,
		joints = dashJoints(char, humanoid),
		startedAt = os.clock(),
	}
	InfDash.run = run

	-- Only exists for the length of one dash: ease the pose in, hold it while
	-- moving, ease it back out, then restore every joint exactly.
	run.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - run.startedAt
		if t >= Config.DashTime then stopMove(run) end

		local weight = smooth(t / POSE_IN) * (1 - smooth((t - Config.DashTime) / POSE_OUT))
		for _, entry in ipairs(run.joints) do
			if entry.joint.Parent then entry.joint.C0 = posedC0(entry, weight) end
		end

		if t >= Config.DashTime + POSE_OUT or not root.Parent or humanoid.Health <= 0 then
			InfDash.cancel()
		end
	end)
end

RootJanitor.connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or Binds.session or not State.InfDashActive then return end
	if input.KeyCode == Config.DashKey then InfDash.start() end
end)

RootJanitor.add({ clean = function() InfDash.cancel() end })

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
		State.InfDashActive = v
		if not v then InfDash.cancel() end
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

-- Auto-reload across teleports (Universal-Misc.lua)
if queue_on_teleport then
	queue_on_teleport([[
		repeat task.wait() until game:IsLoaded()
		task.wait(2)
		if _G.__ZenGlitchJanitor then
			pcall(function() _G.__ZenGlitchJanitor.clean() end)
			_G.__ZenGlitchJanitor = nil
		end

		-- NOTE: this points at upstream. If you are running the refined
		-- copy, re-point URL at your own hosted file — otherwise the
		-- next teleport silently reverts every fix in this build.
		local URL = "https://raw.githubusercontent.com/perpy08/RBXScripts/refs/heads/main/Universal-Misc.2.lua"
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
