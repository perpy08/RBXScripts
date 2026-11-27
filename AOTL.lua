local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

-- ═══════════════════════════════════════════════════════════
--  CONFIG
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
	FolderNames = {
		Monsters = true,

		Angels = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(120, 210, 255),
		},

		Snipers = true,
		SovietRiflemen = true,

		RedPeppers = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(255, 140, 40),
			MaxDistance = 0,
			MinBoxSize = 8,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
		},

		Landmines = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(150, 150, 150),
			MaxDistance = 0,
			MinBoxSize = 9,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
			StateColors = {
				Armed = Color3.fromRGB(255, 60, 60),
			},
		},

		Tripwires = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(150, 150, 150),
			MaxDistance = 0,
			MinBoxSize = 2,
			TagTextSize = 11,
			TagPadX = 4,
			TagPadY = 1,
			StateColors = {
				Armed = Color3.fromRGB(255, 130, 0),
			},
		},

		Deadlights = {
			RequireHumanoid = false,
			BoxColor = Color3.fromRGB(180, 120, 255),
			MinBoxSize = 10,
		},

		LittleGirl = {
			BoxColor = Color3.fromRGB(255, 105, 180),
		},

		QuestGivers = {
			BoxColor = Color3.fromRGB(255, 105, 180),
		},
	},

	BoxColor        = Color3.fromRGB(255, 64, 64),
	BoxThickness    = 2,
	BoxTransparency = 0.15,

	TagBackground   = Color3.fromRGB(18, 18, 18),
	TagTextColor    = Color3.fromRGB(255, 255, 255),
	TagTextSize     = 14,
	TagPadX         = 6,
	TagPadY         = 2,
	TagOffset       = 6,

	CornerRadius    = 4,
	MaxDistance     = 600,
	RescanInterval  = 0.2,

	ShowDistance    = true,
	TagFormat       = "%s [%dm]",

	GuiToggleKey = Enum.KeyCode.Insert,

	AngelAlert = {
		Enabled            = true,
		Folder             = "Angels",
		Radius             = 75,
		Text               = "ANGEL",
		Color              = Color3.fromRGB(120, 210, 255),
		ShowBanner         = true,
		ShowOffscreenArrow = true,
		LockCamera         = true,
		EdgeMargin         = 28,
	},

	ShoppingList = {
		"canned beans", "bread", "rice", "cookies", "cereal",
		"flour", "soda", "water", "milk", "tomato sauce",
		"cooking oil", "potatoes", "oranges", "strawberries",
		"grapes", "cucumbers", "broccoli", "bananas", "eggs", "garlic",
	},

	ItemESP = {
		Enabled      = true,
		BoxColor     = Color3.fromRGB(80, 255, 120),
		TagTextSize  = 13,
		MinBoxSize   = 8,
		MaxDistance   = 0,
		ScanInterval = 0.5,
	},
}

-- ═══════════════════════════════════════════════════════════
--  SINGLE-INSTANCE GUARD
-- ═══════════════════════════════════════════════════════════

if _G.AislesOfTheLocust and _G.AislesOfTheLocust.Destroy then
	pcall(function() _G.AislesOfTheLocust:Destroy() end)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "AislesOfTheLocust"
screenGui.ResetOnSpawn     = false
screenGui.IgnoreGuiInset   = true
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder     = 100
screenGui.Enabled          = true
screenGui.Parent           = playerGui

-- ═══════════════════════════════════════════════════════════
--  LAYERS — ESP overlays go on overlayLayer, HUD on hudLayer
-- ═══════════════════════════════════════════════════════════

local function makeLayer(name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = screenGui
	return f
end

local overlayLayer = makeLayer("OverlayLayer")
local alertLayer   = makeLayer("AlertLayer")
local hudLayer     = makeLayer("HudLayer")

-- ═══════════════════════════════════════════════════════════
--  UI HELPERS
-- ═══════════════════════════════════════════════════════════

local HUD_WIDTH = 190

local function makeBox(color)
	local frame = Instance.new("Frame")
	frame.Name = "Box"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 1

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = color or CONFIG.BoxColor
	stroke.Thickness = CONFIG.BoxThickness
	stroke.Transparency = CONFIG.BoxTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = frame

	return frame
end

local function makeTag(opts)
	local o = opts or {}
	local textSize = o.TagTextSize or CONFIG.TagTextSize
	local padX = o.TagPadX or CONFIG.TagPadX
	local padY = o.TagPadY or CONFIG.TagPadY

	local label = Instance.new("TextLabel")
	label.Name = "Tag"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = CONFIG.TagBackground
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = CONFIG.TagTextColor
	label.TextSize = textSize
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Visible = false
	label.ZIndex = 2

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft  = UDim.new(0, padX)
	pad.PaddingRight = UDim.new(0, padX)
	pad.PaddingTop   = UDim.new(0, padY)
	pad.PaddingBottom = UDim.new(0, padY)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = label

	return label
end

-- ═══════════════════════════════════════════════════════════
--  FOG & DARKNESS
-- ═══════════════════════════════════════════════════════════

local savedFog = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd, FogColor = Lighting.FogColor }
local savedBrt = { Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient }
local fogOff, darkOff = false, false

local function removeFog()
	if fogOff then return end
	savedFog.FogStart = Lighting.FogStart
	savedFog.FogEnd   = Lighting.FogEnd
	savedFog.FogColor = Lighting.FogColor
	Lighting.FogStart = 1e9
	Lighting.FogEnd   = 1e9
	Lighting.FogColor = Color3.new(0, 0, 0)
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("Atmosphere") then c.Density = 0 end
	end
	fogOff = true
end

local function restoreFog()
	if not fogOff then return end
	Lighting.FogStart = savedFog.FogStart
	Lighting.FogEnd   = savedFog.FogEnd
	Lighting.FogColor = savedFog.FogColor
	fogOff = false
end

local function removeDarkness()
	if darkOff then return end
	savedBrt.Brightness     = Lighting.Brightness
	savedBrt.Ambient        = Lighting.Ambient
	savedBrt.OutdoorAmbient = Lighting.OutdoorAmbient
	Lighting.Brightness     = 3
	Lighting.Ambient        = Color3.fromRGB(200, 200, 200)
	Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("ColorCorrectionEffect") then
			c.Brightness = 0.15; c.Contrast = 0.1
		end
	end
	darkOff = true
end

local function restoreDarkness()
	if not darkOff then return end
	Lighting.Brightness     = savedBrt.Brightness
	Lighting.Ambient        = savedBrt.Ambient
	Lighting.OutdoorAmbient = savedBrt.OutdoorAmbient
	darkOff = false
end

-- ═══════════════════════════════════════════════════════════
--  COMPACT HUD — fixed 190px wide, top-right
-- ═══════════════════════════════════════════════════════════

local hudFrame = Instance.new("Frame")
hudFrame.Name = "Hud"
hudFrame.AnchorPoint = Vector2.new(1, 0)
hudFrame.Position = UDim2.new(1, -10, 0, 10)
hudFrame.Size = UDim2.fromOffset(HUD_WIDTH, 0)
hudFrame.AutomaticSize = Enum.AutomaticSize.Y
hudFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
hudFrame.BackgroundTransparency = 0.06
hudFrame.BorderSizePixel = 0
hudFrame.ZIndex = 10
hudFrame.ClipsDescendants = false
hudFrame.Parent = hudLayer

do
	Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 6)
	local s = Instance.new("UIStroke", hudFrame)
	s.Color = Color3.fromRGB(50, 50, 58); s.Thickness = 1
	local p = Instance.new("UIPadding", hudFrame)
	p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8)
	p.PaddingTop  = UDim.new(0, 6); p.PaddingBottom = UDim.new(0, 6)
	local l = Instance.new("UIListLayout", hudFrame)
	l.Padding = UDim.new(0, 3); l.SortOrder = Enum.SortOrder.LayoutOrder
end

-- helper: single-line label
local function hudLabel(text, order, color, size)
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, size or 13)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.Text = text
	t.TextColor3 = color or Color3.fromRGB(220, 220, 225)
	t.TextSize = size or 11
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.ZIndex = 11
	t.Parent = hudFrame
	return t
end

-- helper: thin separator
local function hudSep(order)
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	f.BorderSizePixel = 0
	f.ZIndex = 11
	f.Parent = hudFrame
end

-- helper: toggle row
local function hudToggle(label, order, cb)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 16)
	row.BackgroundTransparency = 1
	row.ZIndex = 11
	row.Parent = hudFrame

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -34, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Gotham
	lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(180, 180, 190)
	lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 11
	lbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, 0, 0, 0)
	btn.Size = UDim2.fromOffset(30, 14)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 9
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.AutoButtonColor = true
	btn.ZIndex = 12
	btn.Parent = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)

	local state = false
	local function refresh()
		btn.Text = state and "ON" or "OFF"
		btn.BackgroundColor3 = state and Color3.fromRGB(40, 160, 70) or Color3.fromRGB(60, 60, 70)
	end
	refresh()

	btn.MouseButton1Click:Connect(function()
		state = not state
		refresh()
		cb(state)
	end)

	return { getState = function() return state end }
end

-- ── Build the HUD ────────────────────────────────────────

hudLabel("Aisles of the Locust", 0, Color3.fromRGB(240, 240, 245), 12)

local hudStatus = Instance.new("TextLabel")
hudStatus.LayoutOrder = 1
hudStatus.Size = UDim2.new(1, 0, 0, 56)
hudStatus.BackgroundTransparency = 1
hudStatus.Font = Enum.Font.Code
hudStatus.Text = ""
hudStatus.TextColor3 = Color3.fromRGB(160, 165, 175)
hudStatus.TextSize = 10
hudStatus.TextXAlignment = Enum.TextXAlignment.Left
hudStatus.TextYAlignment = Enum.TextYAlignment.Top
hudStatus.ZIndex = 11
hudStatus.Parent = hudFrame

hudSep(2)
local fogT  = hudToggle("Remove Fog", 3, function(on) if on then removeFog() else restoreFog() end end)
local darkT = hudToggle("Remove Darkness", 4, function(on) if on then removeDarkness() else restoreDarkness() end end)

hudSep(5)
hudLabel("Shopping List Items", 6, Color3.fromRGB(80, 255, 120), 11)

-- ── Dropdown + TP ────────────────────────────────────────

local dropRow = Instance.new("Frame")
dropRow.LayoutOrder = 7
dropRow.Size = UDim2.new(1, 0, 0, 20)
dropRow.BackgroundTransparency = 1
dropRow.ZIndex = 11
dropRow.Parent = hudFrame

local dropBtn = Instance.new("TextButton")
dropBtn.Size = UDim2.new(1, -36, 1, 0)
dropBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
dropBtn.Font = Enum.Font.Gotham
dropBtn.TextSize = 10
dropBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
dropBtn.TextXAlignment = Enum.TextXAlignment.Left
dropBtn.TextTruncate = Enum.TextTruncate.AtEnd
dropBtn.Text = " No items..."
dropBtn.AutoButtonColor = true
dropBtn.ZIndex = 12
dropBtn.Parent = dropRow
Instance.new("UICorner", dropBtn).CornerRadius = UDim.new(0, 3)
Instance.new("UIStroke", dropBtn).Color = Color3.fromRGB(50, 50, 58)
local dp = Instance.new("UIPadding", dropBtn)
dp.PaddingLeft = UDim.new(0, 4); dp.PaddingRight = UDim.new(0, 14)

-- arrow glyph
local arrow = Instance.new("TextLabel")
arrow.AnchorPoint = Vector2.new(1, 0.5)
arrow.Position = UDim2.new(1, -2, 0.5, 0)
arrow.Size = UDim2.fromOffset(10, 10)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBold
arrow.Text = "v"
arrow.TextColor3 = Color3.fromRGB(120, 120, 130)
arrow.TextSize = 9
arrow.ZIndex = 13
arrow.Parent = dropBtn

local tpBtn = Instance.new("TextButton")
tpBtn.AnchorPoint = Vector2.new(1, 0)
tpBtn.Position = UDim2.new(1, 0, 0, 0)
tpBtn.Size = UDim2.fromOffset(32, 20)
tpBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
tpBtn.Font = Enum.Font.GothamBold
tpBtn.TextSize = 9
tpBtn.Text = "TP"
tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpBtn.AutoButtonColor = true
tpBtn.ZIndex = 12
tpBtn.Parent = dropRow
Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 3)

-- ── Popup (parented to screenGui, NOT hudFrame) ──────────

local selectedItem = nil
local detectedItems = {}
local popupOpen = false

local popupFrame = Instance.new("ScrollingFrame")
popupFrame.Name = "Popup"
popupFrame.Size = UDim2.fromOffset(HUD_WIDTH, 0)
popupFrame.AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y
popupFrame.CanvasSize = UDim2.fromOffset(0, 0)
popupFrame.ScrollBarThickness = 3
popupFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
popupFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
popupFrame.BackgroundTransparency = 0.02
popupFrame.BorderSizePixel = 0
popupFrame.Visible = false
popupFrame.ZIndex = 30
popupFrame.Parent = screenGui  -- on screenGui directly, not hudFrame
Instance.new("UICorner", popupFrame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", popupFrame).Color = Color3.fromRGB(50, 50, 58)
local popLay = Instance.new("UIListLayout", popupFrame)
popLay.Padding = UDim.new(0, 1); popLay.SortOrder = Enum.SortOrder.LayoutOrder

local function positionPopup()
	-- place popup just below the dropdown row
	local abs = dropRow.AbsolutePosition
	local sz  = dropRow.AbsoluteSize
	popupFrame.Position = UDim2.fromOffset(abs.X, abs.Y + sz.Y + 2)
end

local function closePopup()
	popupOpen = false
	popupFrame.Visible = false
end

local function refreshPopup()
	for _, c in ipairs(popupFrame:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end

	local list = detectedItems
	if #list == 0 then
		local e = Instance.new("TextButton")
		e.Size = UDim2.new(1, 0, 0, 20)
		e.BackgroundTransparency = 1
		e.Font = Enum.Font.Gotham
		e.Text = "  No items detected"
		e.TextColor3 = Color3.fromRGB(90, 90, 100)
		e.TextSize = 10
		e.TextXAlignment = Enum.TextXAlignment.Left
		e.AutoButtonColor = false
		e.ZIndex = 31
		e.Parent = popupFrame
		popupFrame.Size = UDim2.fromOffset(HUD_WIDTH, 22)
		return
	end

	for idx, item in ipairs(list) do
		local o = Instance.new("TextButton")
		o.LayoutOrder = idx
		o.Size = UDim2.new(1, 0, 0, 20)
		o.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		o.BackgroundTransparency = 0.1
		o.Font = Enum.Font.Gotham
		o.Text = string.format(" %s [%dm]", item.name, math.floor(item.dist + 0.5))
		o.TextColor3 = Color3.fromRGB(80, 255, 120)
		o.TextSize = 10
		o.TextXAlignment = Enum.TextXAlignment.Left
		o.TextTruncate = Enum.TextTruncate.AtEnd
		o.AutoButtonColor = true
		o.ZIndex = 31
		o.Parent = popupFrame

		o.MouseButton1Click:Connect(function()
			selectedItem = item.instance
			dropBtn.Text = string.format(" %s [%dm]", item.name, math.floor(item.dist + 0.5))
			closePopup()
		end)
	end

	popupFrame.Size = UDim2.fromOffset(HUD_WIDTH, math.min(#list * 21, 160))
end

dropBtn.MouseButton1Click:Connect(function()
	if popupOpen then
		closePopup()
	else
		positionPopup()
		refreshPopup()
		popupOpen = true
		popupFrame.Visible = true
	end
end)

-- ── Teleport ─────────────────────────────────────────────

local function getItemPosition(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local ok, p = pcall(function() return inst:GetPivot().Position end)
		return ok and p or nil
	end
	return nil
end

tpBtn.MouseButton1Click:Connect(function()
	if not selectedItem or not selectedItem.Parent then return end
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pos = getItemPosition(selectedItem)
	if not pos then return end
	hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end)

-- ═══════════════════════════════════════════════════════════
--  ITEM SCANNER
-- ═══════════════════════════════════════════════════════════

local shoppingLookup = {}
for _, name in ipairs(CONFIG.ShoppingList) do
	shoppingLookup[name:lower()] = true
end

local itemTracked = {}

local function matchesShoppingList(instanceName)
	local lower = instanceName:lower()
	-- remove non-alphanumeric for fuzzy compare
	local clean = lower:gsub("[^%a%d]", "")
	for listName in pairs(shoppingLookup) do
		local cleanList = listName:gsub("[^%a%d]", "")
		if clean == cleanList then return true end
		if clean:find(cleanList, 1, true) then return true end
		if cleanList:find(clean, 1, true) and #clean >= 3 then return true end
	end
	return false
end

local function createItemOverlay(inst)
	if itemTracked[inst] then return end
	local box = makeBox(CONFIG.ItemESP.BoxColor)
	box.Parent = overlayLayer

	local tag = makeTag({ TagTextSize = CONFIG.ItemESP.TagTextSize, TagPadX = 4, TagPadY = 1 })
	tag.TextColor3 = Color3.fromRGB(80, 255, 120)
	tag.Text = inst.Name
	tag.Parent = overlayLayer

	itemTracked[inst] = {
		box = box, stroke = box:FindFirstChild("Stroke"), tag = tag,
		minSize = CONFIG.ItemESP.MinBoxSize,
		maxDistance = CONFIG.ItemESP.MaxDistance,
	}
end

local function destroyItemOverlay(inst)
	local e = itemTracked[inst]
	if not e then return end
	if e.box then e.box:Destroy() end
	if e.tag then e.tag:Destroy() end
	itemTracked[inst] = nil
end

local function scanForItems(refPos)
	if not CONFIG.ItemESP.Enabled then return end

	local found = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		local ok2, nameOk = pcall(function()
			return d.Parent and (d:IsA("BasePart") or d:IsA("Model")) and matchesShoppingList(d.Name)
		end)
		if ok2 and nameOk then
			found[d] = true
			createItemOverlay(d)
		end
	end

	for inst in pairs(itemTracked) do
		if not found[inst] or not inst.Parent then
			destroyItemOverlay(inst)
		end
	end

	-- rebuild sorted list
	local list = {}
	for inst in pairs(itemTracked) do
		if inst.Parent then
			local pos = getItemPosition(inst)
			local dist = pos and refPos and (pos - refPos).Magnitude or 9999
			table.insert(list, { name = inst.Name, instance = inst, dist = dist })
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	detectedItems = list

	if selectedItem and not itemTracked[selectedItem] then
		selectedItem = nil
	end
	if not selectedItem and #list > 0 then
		selectedItem = list[1].instance
	end

	if selectedItem then
		for _, item in ipairs(list) do
			if item.instance == selectedItem then
				dropBtn.Text = string.format(" %s [%dm]", item.name, math.floor(item.dist + 0.5))
				break
			end
		end
	else
		dropBtn.Text = " No items..."
	end

	if popupOpen then refreshPopup() end
end

-- ═══════════════════════════════════════════════════════════
--  ENTITY ESP
-- ═══════════════════════════════════════════════════════════

local targetFolders = {}
local tracked = {}
local DEFAULT_FOLDER_OPTS = { RequireHumanoid = true }
local Overlay -- forward declare

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local function updateHud()
	hudStatus.Text = table.concat({
		"GUI    : " .. (Overlay and Overlay.GuiVisible and "ON" or "OFF") .. "  (Insert)",
		"ESP    : " .. (Overlay and Overlay.Enabled and "ON" or "OFF"),
		"Folders: " .. countKeys(targetFolders),
		"Tracked: " .. countKeys(tracked),
		"Items  : " .. #detectedItems,
	}, "\n")
end

local function registerFolder(folder, opts)
	targetFolders[folder] = opts or true
end

local function unregisterFolder(folder)
	targetFolders[folder] = nil
end

local function resolveFolderOptions(opts)
	return type(opts) == "table" and opts or DEFAULT_FOLDER_OPTS
end

local function collectModels(folder, reqHum)
	local out = {}
	for _, d in ipairs(folder:GetChildren()) do
		if d:IsA("Model") then
			if not reqHum or d:FindFirstChildOfClass("Humanoid") then
				table.insert(out, d)
			end
		end
		if d:IsA("Folder") then
			for _, m in ipairs(d:GetChildren()) do
				if m:IsA("Model") and (not reqHum or m:FindFirstChildOfClass("Humanoid")) then
					table.insert(out, m)
				end
			end
		end
	end
	return out
end

local function createOverlay(model, meta)
	local o = resolveFolderOptions(meta.opts)
	local box = makeBox(o.BoxColor)
	box.Parent = overlayLayer

	local tag = makeTag(o)
	tag.Text = model.Name
	tag.Parent = overlayLayer

	tracked[model] = {
		box = box, stroke = box:FindFirstChild("Stroke"), tag = tag,
		lastDist = nil, lastName = nil, lastShowDist = nil, lastFmt = nil,
		maxDistance = o.MaxDistance,
		minSize = (o.MinBoxSize and o.MinBoxSize > 0) and o.MinBoxSize or nil,
		baseColor = o.BoxColor or CONFIG.BoxColor,
		stateColors = o.StateColors,
		stateAttribute = o.StateAttribute or "State",
		lastStateColor = nil,
		isAngel = meta.folder and meta.folder.Name == CONFIG.AngelAlert.Folder or false,
	}
end

local function destroyOverlay(model)
	local e = tracked[model]
	if not e then return end
	if e.box then e.box:Destroy() end
	if e.tag then e.tag:Destroy() end
	tracked[model] = nil
end

local function hideEntry(e)
	if e.box then e.box.Visible = false end
	if e.tag then e.tag.Visible = false end
end

-- ── Angel alert UI ───────────────────────────────────────

local alertArrow = Instance.new("TextLabel")
alertArrow.Name = "AngelArrow"
alertArrow.AnchorPoint = Vector2.new(0.5, 0.5)
alertArrow.Size = UDim2.fromOffset(64, 64)
alertArrow.BackgroundTransparency = 1
alertArrow.Font = Enum.Font.GothamBold
alertArrow.Text = "^"
alertArrow.TextColor3 = CONFIG.AngelAlert.Color
alertArrow.TextSize = 44
alertArrow.TextStrokeColor3 = Color3.new(0, 0, 0)
alertArrow.TextStrokeTransparency = 0.4
alertArrow.Visible = false
alertArrow.ZIndex = 5
alertArrow.Parent = alertLayer

local alertBanner = Instance.new("TextLabel")
alertBanner.Name = "AngelNotice"
alertBanner.AnchorPoint = Vector2.new(0.5, 0)
alertBanner.Position = UDim2.new(0.5, 0, 0, 84)
alertBanner.AutomaticSize = Enum.AutomaticSize.XY
alertBanner.BackgroundColor3 = CONFIG.TagBackground
alertBanner.BackgroundTransparency = 0.1
alertBanner.Font = Enum.Font.GothamBold
alertBanner.TextColor3 = CONFIG.AngelAlert.Color
alertBanner.TextSize = 20
alertBanner.TextStrokeTransparency = 0.6
alertBanner.Visible = false
alertBanner.ZIndex = 6
alertBanner.Parent = alertLayer
do
	local p2 = Instance.new("UIPadding", alertBanner)
	p2.PaddingLeft = UDim.new(0, 10); p2.PaddingRight = UDim.new(0, 10)
	p2.PaddingTop = UDim.new(0, 4); p2.PaddingBottom = UDim.new(0, 4)
	Instance.new("UICorner", alertBanner).CornerRadius = UDim.new(0, CONFIG.CornerRadius)
end

local alert = { target = nil, aim = nil, dist = nil }
local ANGEL_LOOK_BIND = "AislesAngelLock"

local function clearAlert()
	alert.target, alert.aim, alert.dist = nil, nil, nil
	alertArrow.Visible = false
	alertBanner.Visible = false
end

local function hideAllVisuals()
	for _, e in pairs(tracked) do hideEntry(e) end
	for _, e in pairs(itemTracked) do hideEntry(e) end
	clearAlert()
end

-- ── Reconcile ────────────────────────────────────────────

local function reconcile()
	local desired = {}
	local changed = false

	for folder, opts in pairs(targetFolders) do
		if folder.Parent then
			local reqHum = resolveFolderOptions(opts).RequireHumanoid ~= false
			for _, model in ipairs(collectModels(folder, reqHum)) do
				desired[model] = { opts = opts, folder = folder }
			end
		else
			targetFolders[folder] = nil
			changed = true
		end
	end

	for model, meta in pairs(desired) do
		if not tracked[model] then
			createOverlay(model, meta)
			changed = true
		end
	end

	for model in pairs(tracked) do
		if not desired[model] or not model.Parent then
			destroyOverlay(model)
			changed = true
		end
	end

	if changed then updateHud() end
end

-- ── Folder discovery ─────────────────────────────────────

local function noteFolder(d)
	if not d:IsA("Folder") then return end
	local opts = CONFIG.FolderNames[d.Name]
	if opts then
		registerFolder(d, opts)
		updateHud()
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do noteFolder(d) end

-- ═══════════════════════════════════════════════════════════
--  PROJECTION (3D -> 2D)
-- ═══════════════════════════════════════════════════════════

local CORNERS = {}
for xi = -1, 1, 2 do for yi = -1, 1, 2 do for zi = -1, 1, 2 do
	table.insert(CORNERS, Vector3.new(xi, yi, zi))
end end end

local function projectBox(camera, cf, size, viewport, minSz)
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local x0, y0 = math.huge, math.huge
	local x1, y1 = -math.huge, -math.huge
	local any = false

	for _, s in ipairs(CORNERS) do
		local w = (cf * CFrame.new(s.X * hx, s.Y * hy, s.Z * hz)).Position
		local sp = camera:WorldToViewportPoint(w)
		if sp.Z > 0 then
			any = true
			if sp.X < x0 then x0 = sp.X end
			if sp.X > x1 then x1 = sp.X end
			if sp.Y < y0 then y0 = sp.Y end
			if sp.Y > y1 then y1 = sp.Y end
		end
	end
	if not any then return nil end

	x0 = math.clamp(x0, 0, viewport.X)
	x1 = math.clamp(x1, 0, viewport.X)
	y0 = math.clamp(y0, 0, viewport.Y)
	y1 = math.clamp(y1, 0, viewport.Y)

	if minSz then
		if (x1 - x0) <= 0 and (y1 - y0) <= 0 then return nil end
		if (x1 - x0) < minSz then
			local cx = (x0 + x1) * 0.5
			x0 = math.clamp(cx - minSz * 0.5, 0, viewport.X)
			x1 = math.clamp(cx + minSz * 0.5, 0, viewport.X)
		end
		if (y1 - y0) < minSz then
			local cy = (y0 + y1) * 0.5
			y0 = math.clamp(cy - minSz * 0.5, 0, viewport.Y)
			y1 = math.clamp(cy + minSz * 0.5, 0, viewport.Y)
		end
		if (x1 - x0) <= 0 or (y1 - y0) <= 0 then return nil end
	elseif (x1 - x0) < 1 or (y1 - y0) < 1 then
		return nil
	end

	return x0, y0, x1, y1
end

local function projectModel(camera, model, viewport, minSz)
	local ok, cf, sz = pcall(function() local c, s = model:GetBoundingBox() return c, s end)
	if not ok or not cf then return nil end
	return projectBox(camera, cf, sz, viewport, minSz)
end

local function projectPart(camera, part, viewport, minSz)
	return projectBox(camera, part.CFrame, part.Size, viewport, minSz)
end

-- ═══════════════════════════════════════════════════════════
--  ANGEL ALERT LOGIC
-- ═══════════════════════════════════════════════════════════

local function aimPosition(model)
	local r = model:FindFirstChild("Root") or model.PrimaryPart
	if r and r:IsA("BasePart") then return r.Position end
	local h = model:FindFirstChild("Head")
	if h and h:IsA("BasePart") then return h.Position end
	local ok, piv = pcall(function() return model:GetPivot().Position end)
	return ok and piv or nil
end

local function findNearestAngel(refPos, radius)
	local best, bPos, bDist, count = nil, nil, nil, 0
	for model, entry in pairs(tracked) do
		if entry.isAngel and model.Parent then
			local ok, piv = pcall(function() return model:GetPivot().Position end)
			if ok then
				local d = (piv - refPos).Magnitude
				if d <= radius then
					count += 1
					if not bDist or d < bDist then
						best, bPos, bDist = model, piv, d
					end
				end
			end
		end
	end
	return best, bPos, bDist, count
end

local function updateAngelAlert(camera, viewport, refPos)
	local cfg = CONFIG.AngelAlert
	if not cfg.Enabled then clearAlert(); return end

	local model, pivot, dist, count = findNearestAngel(refPos, cfg.Radius)
	if not model then clearAlert(); return end

	local aim = aimPosition(model) or pivot
	alert.target, alert.aim, alert.dist = model, aim, dist

	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)

	if cfg.ShowBanner then
		local t = count > 1
			and string.format("%s x%d  %dm", cfg.Text, count, math.floor(dist + 0.5))
			or  string.format("%s  %dm", cfg.Text, math.floor(dist + 0.5))
		alertBanner.Text = t
		alertBanner.TextColor3 = cfg.Color
		alertBanner.TextTransparency = 0.1 + 0.35 * pulse
		alertBanner.Visible = true
	else
		alertBanner.Visible = false
	end

	if not cfg.ShowOffscreenArrow then alertArrow.Visible = false; return end

	local vp = camera:WorldToViewportPoint(aim)
	local margin = cfg.EdgeMargin
	if vp.Z > 0 and vp.X >= margin and vp.X <= viewport.X - margin
		and vp.Y >= margin and vp.Y <= viewport.Y - margin then
		alertArrow.Visible = false; return
	end

	local rel = camera.CFrame:PointToObjectSpace(aim)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 1e-3 then dir = Vector2.new(0, -1) end
	dir = dir.Unit
	local center = Vector2.new(viewport.X, viewport.Y) * 0.5
	local half = Vector2.new(viewport.X * 0.5 - margin, viewport.Y * 0.5 - margin)
	local scale = math.min(half.X / math.max(math.abs(dir.X), 1e-4), half.Y / math.max(math.abs(dir.Y), 1e-4))
	local pos = center + dir * scale

	alertArrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	alertArrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
	alertArrow.TextColor3 = cfg.Color
	alertArrow.TextTransparency = 0.05 + 0.35 * pulse
	alertArrow.TextStrokeTransparency = 0.4 + 0.3 * pulse
	alertArrow.Visible = true
end

local function formatTagText(name, dist)
	if not CONFIG.ShowDistance then return name end
	local ok, t = pcall(string.format, CONFIG.TagFormat, name, dist)
	return ok and t or string.format("%s [%dm]", name, dist)
end

-- ═══════════════════════════════════════════════════════════
--  OVERLAY OBJECT
-- ═══════════════════════════════════════════════════════════

Overlay = {
	Enabled    = true,
	GuiVisible = true,
	Config     = CONFIG,
	_connections = {},
}

function Overlay:SetEnabled(on)
	self.Enabled = on and true or false
	if not self.Enabled then hideAllVisuals() end
	updateHud()
end

function Overlay:ToggleEnabled()
	self:SetEnabled(not self.Enabled)
end

function Overlay:SetGuiVisible(on)
	self.GuiVisible = on and true or false
	if self.GuiVisible then
		screenGui.Enabled = true
	else
		hideAllVisuals()
		screenGui.Enabled = false
	end
	updateHud()
end

function Overlay:ToggleGui()
	self:SetGuiVisible(not self.GuiVisible)
end

function Overlay:Rescan() reconcile() end

function Overlay:Destroy()
	for _, conn in ipairs(self._connections) do
		pcall(function() conn:Disconnect() end)
	end
	self._connections = {}
	for m in pairs(tracked) do destroyOverlay(m) end
	for i in pairs(itemTracked) do destroyItemOverlay(i) end
	table.clear(targetFolders); table.clear(tracked); table.clear(itemTracked)
	pcall(function() RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND) end)
	clearAlert(); restoreFog(); restoreDarkness()
	if screenGui then screenGui:Destroy() end
	if _G.AislesOfTheLocust == self then _G.AislesOfTheLocust = nil end
end

-- ═══════════════════════════════════════════════════════════
--  CONNECTIONS
-- ═══════════════════════════════════════════════════════════

table.insert(Overlay._connections, Workspace.DescendantAdded:Connect(noteFolder))
table.insert(Overlay._connections, Workspace.DescendantRemoving:Connect(function(d)
	if targetFolders[d] then unregisterFolder(d); reconcile(); updateHud() end
end))

table.insert(Overlay._connections, UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == CONFIG.GuiToggleKey then
		Overlay:ToggleGui()
	end
end))

-- ═══════════════════════════════════════════════════════════
--  RENDER LOOP
-- ═══════════════════════════════════════════════════════════

local lastScan, lastItemScan = 0, 0
local visualsHidden = false

table.insert(Overlay._connections, RunService.RenderStepped:Connect(function()
	local now = os.clock()

	-- always reconcile even when hidden so tracked stays current
	if now - lastScan >= CONFIG.RescanInterval then
		lastScan = now
		reconcile()
	end

	if not Overlay.Enabled or not Overlay.GuiVisible then
		if not visualsHidden then hideAllVisuals(); visualsHidden = true end
		return
	end
	visualsHidden = false

	local camera = Workspace.CurrentCamera
	if not camera then hideAllVisuals(); return end

	local viewport = camera.ViewportSize
	local camPos   = camera.CFrame.Position
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = root and root.Position or camPos

	-- item scan (slower)
	if now - lastItemScan >= CONFIG.ItemESP.ScanInterval then
		lastItemScan = now
		scanForItems(refPos)
		updateHud()
	end

	-- entity ESP
	for model, entry in pairs(tracked) do
		local box, tag = entry.box, entry.tag
		local hide = false

		if entry.stateColors and entry.stroke then
			local st = model:GetAttribute(entry.stateAttribute)
			local col = (st and entry.stateColors[st]) or entry.baseColor
			if entry.lastStateColor ~= col then
				entry.lastStateColor = col; entry.stroke.Color = col
			end
		end

		local ok, pivot = pcall(function() return model:GetPivot().Position end)
		if not ok then
			hide = true
		else
			local dist = (pivot - refPos).Magnitude
			local shown = math.floor(dist + 0.5)
			local maxD = entry.maxDistance
			if maxD == nil then maxD = CONFIG.MaxDistance end
			if maxD > 0 and dist > maxD then hide = true end

			if not hide then
				local nm = model.Name
				if entry.lastName ~= nm or entry.lastDist ~= shown
					or entry.lastShowDist ~= CONFIG.ShowDistance or entry.lastFmt ~= CONFIG.TagFormat then
					entry.lastName = nm; entry.lastDist = shown
					entry.lastShowDist = CONFIG.ShowDistance; entry.lastFmt = CONFIG.TagFormat
					tag.Text = formatTagText(nm, shown)
				end
			end
		end

		if not hide then
			local x0, y0, x1, y1 = projectModel(camera, model, viewport, entry.minSize)
			if not x0 then hide = true
			else
				local w, h = x1 - x0, y1 - y0
				box.Position = UDim2.fromOffset(x0, y0)
				box.Size = UDim2.fromOffset(w, h)
				box.Visible = true
				tag.Position = UDim2.fromOffset(x0 + w * 0.5, y0 - CONFIG.TagOffset)
				tag.Visible = true
			end
		end

		if hide then hideEntry(entry) end
	end

	-- item ESP
	for inst, entry in pairs(itemTracked) do
		local box, tag = entry.box, entry.tag
		local hide = false

		if not inst.Parent then hide = true
		else
			local pos = getItemPosition(inst)
			if not pos then hide = true
			else
				local dist = (pos - refPos).Magnitude
				local maxD = entry.maxDistance or 0
				if maxD > 0 and dist > maxD then hide = true end
				if not hide then
					tag.Text = string.format("%s [%dm]", inst.Name, math.floor(dist + 0.5))
				end
			end
		end

		if not hide then
			local x0, y0, x1, y1
			if inst:IsA("Model") then
				x0, y0, x1, y1 = projectModel(camera, inst, viewport, entry.minSize)
			else
				x0, y0, x1, y1 = projectPart(camera, inst, viewport, entry.minSize)
			end
			if not x0 then hide = true
			else
				local w, h = x1 - x0, y1 - y0
				box.Position = UDim2.fromOffset(x0, y0)
				box.Size = UDim2.fromOffset(w, h)
				box.Visible = true
				tag.Position = UDim2.fromOffset(x0 + w * 0.5, y0 - CONFIG.TagOffset)
				tag.Visible = true
			end
		end

		if hide then hideEntry(entry) end
	end

	updateAngelAlert(camera, viewport, refPos)
end))

-- camera lock
pcall(function() RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND) end)
RunService:BindToRenderStep(ANGEL_LOOK_BIND, Enum.RenderPriority.Camera.Value + 1, function()
	local cfg = CONFIG.AngelAlert
	if not Overlay.Enabled or not Overlay.GuiVisible or not cfg.Enabled or not cfg.LockCamera then return end
	local tgt, aim = alert.target, alert.aim
	if not tgt or not aim or not tgt.Parent then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local origin = cam.CFrame.Position
	if (aim - origin).Magnitude < 0.05 then return end
	cam.CFrame = CFrame.lookAt(origin, aim)
end)

-- ═══════════════════════════════════════════════════════════
--  STARTUP
-- ═══════════════════════════════════════════════════════════

_G.AislesOfTheLocust = Overlay
updateHud()
reconcile()

do
	local char = LocalPlayer.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	local ref = r and r.Position or (Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position or Vector3.zero)
	scanForItems(ref)
end

print("[AislesOfTheLocust] active | Insert = toggle GUI | " .. #detectedItems .. " items found")
