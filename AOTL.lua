local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

-- ══════════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════════

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
	StatusHud = {
		Enabled = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Title = "Aisles of the Locust ESP",
	},

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

	-- ── Shopping list grocery items ──────────────────────────────
	-- Lower-cased names matched against Instance.Name:lower()
	ShoppingList = {
		"canned beans", "bread", "rice", "cookies", "cereal",
		"flour", "soda", "water", "milk", "tomato sauce",
		"cooking oil", "potatoes", "oranges", "strawberries",
		"grapes", "cucumbers", "broccoli", "bananas", "eggs", "garlic",
	},

	ItemESP = {
		Enabled     = true,
		BoxColor    = Color3.fromRGB(80, 255, 120),
		TagTextSize = 13,
		MinBoxSize  = 8,
		MaxDistance  = 0,         -- 0 = unlimited
		ScanInterval = 0.5,      -- seconds between full workspace scans for items
	},
}

-- ══════════════════════════════════════════════════════════════════
--  SINGLE-INSTANCE GUARD
-- ══════════════════════════════════════════════════════════════════

if _G.AislesOfTheLocust and _G.AislesOfTheLocust.Destroy then
	pcall(function()
		_G.AislesOfTheLocust:Destroy()
	end)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AislesOfTheLocust"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Enabled = true
screenGui.Parent = playerGui

-- ══════════════════════════════════════════════════════════════════
--  LAYERS
-- ══════════════════════════════════════════════════════════════════

local function makeLayer(name)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = screenGui
	return frame
end

local overlayLayer = makeLayer("OverlayLayer")
local alertLayer   = makeLayer("AlertLayer")
local hudLayer     = makeLayer("HudLayer")

-- ══════════════════════════════════════════════════════════════════
--  UI HELPERS: BOX & TAG
-- ══════════════════════════════════════════════════════════════════

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
	pad.PaddingLeft = UDim.new(0, padX)
	pad.PaddingRight = UDim.new(0, padX)
	pad.PaddingTop = UDim.new(0, padY)
	pad.PaddingBottom = UDim.new(0, padY)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = label

	return label
end

-- ══════════════════════════════════════════════════════════════════
--  ENVIRONMENT: FOG & DARKNESS REMOVAL
-- ══════════════════════════════════════════════════════════════════

local savedFog = {
	FogStart  = Lighting.FogStart,
	FogEnd    = Lighting.FogEnd,
	FogColor  = Lighting.FogColor,
}
local savedBrightness = {
	Brightness     = Lighting.Brightness,
	Ambient        = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
}
local fogRemoved      = false
local darknessRemoved = false

local function removeFog()
	if fogRemoved then return end
	savedFog.FogStart = Lighting.FogStart
	savedFog.FogEnd   = Lighting.FogEnd
	savedFog.FogColor = Lighting.FogColor
	Lighting.FogStart = 1e9
	Lighting.FogEnd   = 1e9
	Lighting.FogColor = Color3.new(0, 0, 0)

	for _, eff in ipairs(Lighting:GetChildren()) do
		if eff:IsA("Atmosphere") then
			eff.Density = 0
		end
	end
	fogRemoved = true
end

local function restoreFog()
	if not fogRemoved then return end
	Lighting.FogStart = savedFog.FogStart
	Lighting.FogEnd   = savedFog.FogEnd
	Lighting.FogColor = savedFog.FogColor
	fogRemoved = false
end

local function removeDarkness()
	if darknessRemoved then return end
	savedBrightness.Brightness     = Lighting.Brightness
	savedBrightness.Ambient        = Lighting.Ambient
	savedBrightness.OutdoorAmbient = Lighting.OutdoorAmbient
	Lighting.Brightness     = 3
	Lighting.Ambient        = Color3.fromRGB(200, 200, 200)
	Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)

	for _, eff in ipairs(Lighting:GetChildren()) do
		if eff:IsA("ColorCorrectionEffect") then
			eff.Brightness = 0.15
			eff.Contrast   = 0.1
		end
	end
	darknessRemoved = true
end

local function restoreDarkness()
	if not darknessRemoved then return end
	Lighting.Brightness     = savedBrightness.Brightness
	Lighting.Ambient        = savedBrightness.Ambient
	Lighting.OutdoorAmbient = savedBrightness.OutdoorAmbient
	darknessRemoved = false
end

-- ══════════════════════════════════════════════════════════════════
--  HUD PANEL (top-right)
-- ══════════════════════════════════════════════════════════════════

local hudFrame = Instance.new("Frame")
hudFrame.Name = "StatusHud"
hudFrame.AnchorPoint = CONFIG.StatusHud.AnchorPoint
hudFrame.Position = CONFIG.StatusHud.Position
hudFrame.AutomaticSize = Enum.AutomaticSize.XY
hudFrame.BackgroundColor3 = CONFIG.TagBackground
hudFrame.BackgroundTransparency = 0.08
hudFrame.BorderSizePixel = 0
hudFrame.Visible = CONFIG.StatusHud.Enabled
hudFrame.ZIndex = 7
hudFrame.Parent = hudLayer

do
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 68)
	stroke.Thickness = 1
	stroke.Transparency = 0.15
	stroke.Parent = hudFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = hudFrame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = hudFrame
end

local hudList = Instance.new("UIListLayout")
hudList.FillDirection = Enum.FillDirection.Vertical
hudList.Padding = UDim.new(0, 4)
hudList.SortOrder = Enum.SortOrder.LayoutOrder
hudList.Parent = hudFrame

-- ── Title ────────────────────────────────────────────────────────

local hudTitle = Instance.new("TextLabel")
hudTitle.Name = "Title"
hudTitle.LayoutOrder = 0
hudTitle.BackgroundTransparency = 1
hudTitle.AutomaticSize = Enum.AutomaticSize.XY
hudTitle.Font = Enum.Font.GothamBold
hudTitle.Text = CONFIG.StatusHud.Title
hudTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
hudTitle.TextSize = 13
hudTitle.TextXAlignment = Enum.TextXAlignment.Left
hudTitle.ZIndex = 8
hudTitle.Parent = hudFrame

-- ── Status body ──────────────────────────────────────────────────

local hudBody = Instance.new("TextLabel")
hudBody.Name = "Body"
hudBody.LayoutOrder = 1
hudBody.BackgroundTransparency = 1
hudBody.AutomaticSize = Enum.AutomaticSize.XY
hudBody.Font = Enum.Font.Code
hudBody.RichText = false
hudBody.Text = ""
hudBody.TextColor3 = Color3.fromRGB(180, 185, 195)
hudBody.TextSize = 12
hudBody.TextXAlignment = Enum.TextXAlignment.Left
hudBody.TextYAlignment = Enum.TextYAlignment.Top
hudBody.ZIndex = 8
hudBody.Parent = hudFrame

-- ── Separator ────────────────────────────────────────────────────

local function makeSeparator(order)
	local sep = Instance.new("Frame")
	sep.Name = "Separator"
	sep.LayoutOrder = order
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
	sep.BackgroundTransparency = 0.3
	sep.BorderSizePixel = 0
	sep.ZIndex = 8
	sep.Parent = hudFrame
	return sep
end

makeSeparator(2)

-- ══════════════════════════════════════════════════════════════════
--  HUD: TOGGLE BUTTONS — Remove Fog / Remove Darkness
-- ══════════════════════════════════════════════════════════════════

local function makeToggleButton(text, order, startState, onToggle)
	local row = Instance.new("Frame")
	row.Name = text
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 22)
	row.ZIndex = 8
	row.Parent = hudFrame

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.Position = UDim2.new(0, 0, 0.5, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size = UDim2.new(0, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 8
	lbl.Parent = row

	local btn = Instance.new("TextButton")
	btn.Name = "Toggle"
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.Size = UDim2.fromOffset(36, 18)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 10
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.AutoButtonColor = true
	btn.ZIndex = 9
	btn.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn

	local state = startState or false

	local function refresh()
		if state then
			btn.Text = "ON"
			btn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
		else
			btn.Text = "OFF"
			btn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
		end
	end

	refresh()

	btn.MouseButton1Click:Connect(function()
		state = not state
		refresh()
		onToggle(state)
	end)

	return {
		row = row,
		getState = function() return state end,
		setState = function(v)
			state = v
			refresh()
			onToggle(state)
		end,
	}
end

local fogToggle = makeToggleButton("Remove Fog", 3, false, function(on)
	if on then removeFog() else restoreFog() end
end)

local darknessToggle = makeToggleButton("Remove Darkness", 4, false, function(on)
	if on then removeDarkness() else restoreDarkness() end
end)

makeSeparator(5)

-- ══════════════════════════════════════════════════════════════════
--  HUD: SHOPPING LIST LABEL + DROPDOWN + TELEPORT BUTTON
-- ══════════════════════════════════════════════════════════════════

local itemLabel = Instance.new("TextLabel")
itemLabel.Name = "ItemLabel"
itemLabel.LayoutOrder = 6
itemLabel.BackgroundTransparency = 1
itemLabel.AutomaticSize = Enum.AutomaticSize.XY
itemLabel.Font = Enum.Font.GothamBold
itemLabel.Text = "🛒 Shopping List Items"
itemLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
itemLabel.TextSize = 12
itemLabel.TextXAlignment = Enum.TextXAlignment.Left
itemLabel.ZIndex = 8
itemLabel.Parent = hudFrame

local dropdownRow = Instance.new("Frame")
dropdownRow.Name = "DropdownRow"
dropdownRow.LayoutOrder = 7
dropdownRow.BackgroundTransparency = 1
dropdownRow.Size = UDim2.new(1, 0, 0, 26)
dropdownRow.ZIndex = 8
dropdownRow.Parent = hudFrame

-- The "dropdown" is a TextButton that cycles through detected items
-- plus a list popup

local selectedItem = nil     -- currently selected Instance (BasePart or Model)
local detectedItems = {}     -- { {name=string, instance=Instance, dist=number}, ... }

local dropBtn = Instance.new("TextButton")
dropBtn.Name = "Dropdown"
dropBtn.AnchorPoint = Vector2.new(0, 0.5)
dropBtn.Position = UDim2.new(0, 0, 0.5, 0)
dropBtn.Size = UDim2.new(1, -50, 1, 0)
dropBtn.Font = Enum.Font.GothamMedium
dropBtn.TextSize = 11
dropBtn.TextColor3 = Color3.fromRGB(220, 220, 225)
dropBtn.TextXAlignment = Enum.TextXAlignment.Left
dropBtn.TextTruncate = Enum.TextTruncate.AtEnd
dropBtn.Text = "  No items found..."
dropBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
dropBtn.AutoButtonColor = true
dropBtn.ZIndex = 9
dropBtn.Parent = dropdownRow

do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = dropBtn

	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 6)
	p.PaddingRight = UDim.new(0, 20)
	p.Parent = dropBtn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 68)
	stroke.Thickness = 1
	stroke.Parent = dropBtn
end

-- little arrow indicator on the dropdown
local dropArrow = Instance.new("TextLabel")
dropArrow.Name = "Arrow"
dropArrow.AnchorPoint = Vector2.new(1, 0.5)
dropArrow.Position = UDim2.new(1, -4, 0.5, 0)
dropArrow.Size = UDim2.fromOffset(14, 14)
dropArrow.BackgroundTransparency = 1
dropArrow.Font = Enum.Font.GothamBold
dropArrow.Text = "▼"
dropArrow.TextColor3 = Color3.fromRGB(140, 140, 150)
dropArrow.TextSize = 10
dropArrow.ZIndex = 10
dropArrow.Parent = dropBtn

local tpBtn = Instance.new("TextButton")
tpBtn.Name = "Teleport"
tpBtn.AnchorPoint = Vector2.new(1, 0.5)
tpBtn.Position = UDim2.new(1, 0, 0.5, 0)
tpBtn.Size = UDim2.fromOffset(44, 22)
tpBtn.Font = Enum.Font.GothamBold
tpBtn.TextSize = 10
tpBtn.Text = "TP"
tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 220)
tpBtn.AutoButtonColor = true
tpBtn.ZIndex = 9
tpBtn.Parent = dropdownRow

do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = tpBtn
end

-- ── Dropdown popup (scrolling list) ──────────────────────────────

local popupOpen = false

local popupFrame = Instance.new("ScrollingFrame")
popupFrame.Name = "DropdownPopup"
popupFrame.AnchorPoint = Vector2.new(1, 0)
popupFrame.Position = UDim2.new(1, 0, 0, 0)
popupFrame.Size = UDim2.fromOffset(230, 0)   -- height set dynamically
popupFrame.CanvasSize = UDim2.fromOffset(0, 0)
popupFrame.AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y
popupFrame.ScrollBarThickness = 4
popupFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
popupFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
popupFrame.BackgroundTransparency = 0.04
popupFrame.BorderSizePixel = 0
popupFrame.Visible = false
popupFrame.ZIndex = 20
popupFrame.Parent = hudFrame  -- anchored inside the hud so it moves with it

do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = popupFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 68)
	stroke.Thickness = 1
	stroke.Parent = popupFrame

	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Vertical
	lay.Padding = UDim.new(0, 1)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = popupFrame
end

local function closePopup()
	popupOpen = false
	popupFrame.Visible = false
end

local function refreshPopup()
	-- clear children (except layout/corner/stroke)
	for _, c in ipairs(popupFrame:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end

	if #detectedItems == 0 then
		local empty = Instance.new("TextButton")
		empty.LayoutOrder = 0
		empty.Size = UDim2.new(1, 0, 0, 24)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.Text = "  No items detected"
		empty.TextColor3 = Color3.fromRGB(100, 100, 110)
		empty.TextSize = 11
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.AutoButtonColor = false
		empty.ZIndex = 21
		empty.Parent = popupFrame
		return
	end

	for idx, item in ipairs(detectedItems) do
		local opt = Instance.new("TextButton")
		opt.Name = item.name
		opt.LayoutOrder = idx
		opt.Size = UDim2.new(1, 0, 0, 24)
		opt.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
		opt.BackgroundTransparency = 0.1
		opt.Font = Enum.Font.GothamMedium
		opt.Text = string.format("  %s  [%dm]", item.name, math.floor(item.dist + 0.5))
		opt.TextColor3 = Color3.fromRGB(80, 255, 120)
		opt.TextSize = 11
		opt.TextXAlignment = Enum.TextXAlignment.Left
		opt.TextTruncate = Enum.TextTruncate.AtEnd
		opt.AutoButtonColor = true
		opt.ZIndex = 21
		opt.Parent = popupFrame

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 4)
		pad.Parent = opt

		opt.MouseButton1Click:Connect(function()
			selectedItem = item.instance
			dropBtn.Text = string.format("  %s  [%dm]", item.name, math.floor(item.dist + 0.5))
			closePopup()
		end)
	end

	-- cap height
	local totalH = #detectedItems * 25
	popupFrame.Size = UDim2.fromOffset(230, math.min(totalH, 200))
end

local function openPopup()
	refreshPopup()
	popupOpen = true
	popupFrame.Visible = true
end

dropBtn.MouseButton1Click:Connect(function()
	if popupOpen then
		closePopup()
	else
		openPopup()
	end
end)

-- ── Teleport logic ───────────────────────────────────────────────

local function getItemPosition(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local ok, pivot = pcall(function()
			return inst:GetPivot().Position
		end)
		return ok and pivot or nil
	end
	return nil
end

tpBtn.MouseButton1Click:Connect(function()
	if not selectedItem or not selectedItem.Parent then
		return
	end

	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local targetPos = getItemPosition(selectedItem)
	if not targetPos then return end

	-- teleport slightly in front / above the item so we don't clip into it
	local offset = Vector3.new(0, 3, 0)
	hrp.CFrame = CFrame.new(targetPos + offset)
end)

-- ══════════════════════════════════════════════════════════════════
--  ITEM SCANNER — finds shopping-list items in Workspace
-- ══════════════════════════════════════════════════════════════════

-- Build a fast lookup table of lowercase shopping-list names
local shoppingLookup = {}
for _, name in ipairs(CONFIG.ShoppingList) do
	shoppingLookup[name:lower()] = true
end

local itemTracked = {}  -- [Instance] = { box, tag, ... }  — for ESP overlays on items

local function matchesShoppingList(instanceName)
	local lower = instanceName:lower()
	-- direct match
	if shoppingLookup[lower] then
		return true
	end
	-- partial / contains match (item name inside the instance name or vice-versa)
	for listName in pairs(shoppingLookup) do
		if lower:find(listName, 1, true) or listName:find(lower, 1, true) then
			return true
		end
	end
	return false
end

local function createItemOverlay(inst)
	if itemTracked[inst] then return end

	local cfg = CONFIG.ItemESP

	local box = makeBox(cfg.BoxColor)
	box.Parent = overlayLayer

	local tag = makeTag({
		TagTextSize = cfg.TagTextSize,
		TagPadX = 4,
		TagPadY = 1,
	})
	tag.TextColor3 = Color3.fromRGB(80, 255, 120)
	tag.Text = "🛒 " .. inst.Name
	tag.Parent = overlayLayer

	itemTracked[inst] = {
		box    = box,
		stroke = box:FindFirstChild("Stroke"),
		tag    = tag,
		minSize = cfg.MinBoxSize,
		maxDistance = cfg.MaxDistance,
	}
end

local function destroyItemOverlay(inst)
	local entry = itemTracked[inst]
	if not entry then return end
	if entry.box then entry.box:Destroy() end
	if entry.tag then entry.tag:Destroy() end
	itemTracked[inst] = nil
end

local function scanForItems(refPos)
	if not CONFIG.ItemESP.Enabled then return end

	local found = {}  -- set of instances we found this scan

	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and d.Parent then
			if matchesShoppingList(d.Name) then
				found[d] = true
				createItemOverlay(d)
			end
		end
	end

	-- remove stale
	for inst in pairs(itemTracked) do
		if not found[inst] or not inst.Parent then
			destroyItemOverlay(inst)
		end
	end

	-- rebuild the detected list (sorted by distance)
	local newDetected = {}
	for inst in pairs(itemTracked) do
		if inst.Parent then
			local pos = getItemPosition(inst)
			local dist = pos and refPos and (pos - refPos).Magnitude or 9999
			table.insert(newDetected, {
				name = inst.Name,
				instance = inst,
				dist = dist,
			})
		end
	end

	table.sort(newDetected, function(a, b) return a.dist < b.dist end)
	detectedItems = newDetected

	-- validate selectedItem still exists
	if selectedItem and not itemTracked[selectedItem] then
		selectedItem = nil
	end

	-- auto-select first if nothing selected
	if not selectedItem and #detectedItems > 0 then
		selectedItem = detectedItems[1].instance
	end

	-- update dropdown text
	if selectedItem then
		for _, item in ipairs(detectedItems) do
			if item.instance == selectedItem then
				dropBtn.Text = string.format("  %s  [%dm]", item.name, math.floor(item.dist + 0.5))
				break
			end
		end
	else
		dropBtn.Text = "  No items found..."
	end

	-- if popup is open, refresh it
	if popupOpen then
		refreshPopup()
	end
end

-- ══════════════════════════════════════════════════════════════════
--  ENTITY ESP — registry, overlays, reconcile
-- ══════════════════════════════════════════════════════════════════

local targetFolders = {}
local tracked = {}
local DEFAULT_FOLDER_OPTS = { RequireHumanoid = true }

local Overlay

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function updateHud()
	if not CONFIG.StatusHud.Enabled then
		hudFrame.Visible = false
		return
	end

	hudFrame.Visible = true
	hudBody.Text = table.concat({
		string.format("GUI     : %s  (%s)", Overlay and Overlay.GuiVisible and "ON" or "OFF", tostring(CONFIG.GuiToggleKey):gsub("Enum%.KeyCode%.", "")),
		string.format("Overlay : %s", Overlay and Overlay.Enabled and "ON" or "OFF"),
		string.format("Folders : %d", countKeys(targetFolders)),
		string.format("Tracked : %d", countKeys(tracked)),
		string.format("Items   : %d", #detectedItems),
		string.format("Angel   : %s", CONFIG.AngelAlert.Enabled and "ON" or "OFF"),
	}, "\n")
end

local function registerFolder(folder, opts)
	targetFolders[folder] = opts or true
end

local function unregisterFolder(folder)
	targetFolders[folder] = nil
end

local function resolveFolderOptions(opts)
	if type(opts) ~= "table" then
		return DEFAULT_FOLDER_OPTS
	end
	return opts
end

local function isTopLevelModelWithinFolder(model, folder)
	local parent = model.Parent
	while parent and parent ~= folder do
		if parent:IsA("Model") then
			return false
		end
		parent = parent.Parent
	end
	return parent ~= nil
end

local function collectFolderModels(folder, requireHumanoid)
	local results = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Model") and isTopLevelModelWithinFolder(d, folder) then
			if not requireHumanoid or d:FindFirstChildOfClass("Humanoid") then
				table.insert(results, d)
			end
		end
	end
	return results
end

local function createOverlay(model, meta)
	local o = resolveFolderOptions(meta.opts)

	local box = makeBox(o.BoxColor)
	box.Parent = overlayLayer

	local tag = makeTag(o)
	tag.Text = model.Name
	tag.Parent = overlayLayer

	tracked[model] = {
		box = box,
		stroke = box:FindFirstChild("Stroke"),
		tag = tag,
		lastDist = nil,
		lastName = nil,
		lastShowDistance = nil,
		lastTagFormat = nil,
		maxDistance = o.MaxDistance,
		minSize = (o.MinBoxSize and o.MinBoxSize > 0) and o.MinBoxSize or nil,
		baseColor = o.BoxColor or CONFIG.BoxColor,
		stateColors = o.StateColors,
		stateAttribute = o.StateAttribute or "State",
		lastStateColor = nil,
		folder = meta.folder,
		folderName = meta.folder and meta.folder.Name or nil,
		isAngel = meta.folder and meta.folder.Name == CONFIG.AngelAlert.Folder or false,
	}
end

local function destroyOverlay(model)
	local entry = tracked[model]
	if not entry then
		return
	end
	if entry.box then
		entry.box:Destroy()
	end
	if entry.tag then
		entry.tag:Destroy()
	end
	tracked[model] = nil
end

local function hideEntry(entry)
	if entry.box then
		entry.box.Visible = false
	end
	if entry.tag then
		entry.tag.Visible = false
	end
end

-- ── Angel alert UI ───────────────────────────────────────────────

local alertArrow = Instance.new("TextLabel")
alertArrow.Name = "AngelArrow"
alertArrow.AnchorPoint = Vector2.new(0.5, 0.5)
alertArrow.Size = UDim2.fromOffset(64, 64)
alertArrow.BackgroundTransparency = 1
alertArrow.BorderSizePixel = 0
alertArrow.Font = Enum.Font.GothamBold
alertArrow.Text = "▲"
alertArrow.TextColor3 = CONFIG.AngelAlert.Color
alertArrow.TextSize = 44
alertArrow.TextStrokeColor3 = Color3.new(0, 0, 0)
alertArrow.TextStrokeTransparency = 0.4
alertArrow.Rotation = 0
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
alertBanner.BorderSizePixel = 0
alertBanner.Font = Enum.Font.GothamBold
alertBanner.Text = ""
alertBanner.TextColor3 = CONFIG.AngelAlert.Color
alertBanner.TextSize = 20
alertBanner.TextStrokeTransparency = 0.6
alertBanner.Visible = false
alertBanner.ZIndex = 6
alertBanner.Parent = alertLayer

do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = alertBanner

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
	corner.Parent = alertBanner
end

local alert = { target = nil, aim = nil, dist = nil }
local ANGEL_LOOK_BIND = "EntityBoxAngelLookAt"

local function clearAlert()
	alert.target, alert.aim, alert.dist = nil, nil, nil
	alertArrow.Visible = false
	alertBanner.Visible = false
end

local function hideAllVisuals()
	for _, entry in pairs(tracked) do
		hideEntry(entry)
	end
	for _, entry in pairs(itemTracked) do
		hideEntry(entry)
	end
	clearAlert()
end

-- ── Reconcile ────────────────────────────────────────────────────

local function reconcile()
	local desired = {}
	local changed = false

	for folder, opts in pairs(targetFolders) do
		if folder.Parent then
			local requireHumanoid = resolveFolderOptions(opts).RequireHumanoid ~= false
			for _, model in ipairs(collectFolderModels(folder, requireHumanoid)) do
				desired[model] = {
					opts = opts,
					folder = folder,
				}
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

	if changed then
		updateHud()
	end
end

-- ── Folder discovery ─────────────────────────────────────────────

local function noteFolder(d)
	if not d:IsA("Folder") then
		return
	end
	local opts = CONFIG.FolderNames[d.Name]
	if opts then
		registerFolder(d, opts)
		updateHud()
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do
	noteFolder(d)
end

-- ══════════════════════════════════════════════════════════════════
--  PROJECTION (3D → 2D)
-- ══════════════════════════════════════════════════════════════════

local CORNERS = {}
for xi = -1, 1, 2 do
	for yi = -1, 1, 2 do
		for zi = -1, 1, 2 do
			table.insert(CORNERS, Vector3.new(xi, yi, zi))
		end
	end
end

local function projectModel(camera, model, viewport, minSize)
	local ok, cf, size = pcall(function()
		local c, s = model:GetBoundingBox()
		return c, s
	end)
	if not ok or not cf then
		return nil
	end

	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local any = false

	for _, sign in ipairs(CORNERS) do
		local world = (cf * CFrame.new(sign.X * hx, sign.Y * hy, sign.Z * hz)).Position
		local sp = camera:WorldToViewportPoint(world)
		if sp.Z > 0 then
			any = true
			if sp.X < minX then minX = sp.X end
			if sp.X > maxX then maxX = sp.X end
			if sp.Y < minY then minY = sp.Y end
			if sp.Y > maxY then maxY = sp.Y end
		end
	end

	if not any then
		return nil
	end

	minX = math.clamp(minX, 0, viewport.X)
	maxX = math.clamp(maxX, 0, viewport.X)
	minY = math.clamp(minY, 0, viewport.Y)
	maxY = math.clamp(maxY, 0, viewport.Y)

	local w, h = maxX - minX, maxY - minY

	if minSize then
		if w <= 0 and h <= 0 then
			return nil
		end
		if w < minSize then
			local cx = (minX + maxX) * 0.5
			minX = math.clamp(cx - minSize * 0.5, 0, viewport.X)
			maxX = math.clamp(cx + minSize * 0.5, 0, viewport.X)
		end
		if h < minSize then
			local cy = (minY + maxY) * 0.5
			minY = math.clamp(cy - minSize * 0.5, 0, viewport.Y)
			maxY = math.clamp(cy + minSize * 0.5, 0, viewport.Y)
		end
		w, h = maxX - minX, maxY - minY
		if w <= 0 or h <= 0 then
			return nil
		end
	elseif w < 1 or h < 1 then
		return nil
	end

	return minX, minY, maxX, maxY
end

-- project a single BasePart (simpler than model)
local function projectPart(camera, part, viewport, minSize)
	local cf = part.CFrame
	local size = part.Size
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local any = false

	for _, sign in ipairs(CORNERS) do
		local world = (cf * CFrame.new(sign.X * hx, sign.Y * hy, sign.Z * hz)).Position
		local sp = camera:WorldToViewportPoint(world)
		if sp.Z > 0 then
			any = true
			if sp.X < minX then minX = sp.X end
			if sp.X > maxX then maxX = sp.X end
			if sp.Y < minY then minY = sp.Y end
			if sp.Y > maxY then maxY = sp.Y end
		end
	end

	if not any then return nil end

	minX = math.clamp(minX, 0, viewport.X)
	maxX = math.clamp(maxX, 0, viewport.X)
	minY = math.clamp(minY, 0, viewport.Y)
	maxY = math.clamp(maxY, 0, viewport.Y)

	local w, h = maxX - minX, maxY - minY

	if minSize then
		if w <= 0 and h <= 0 then return nil end
		if w < minSize then
			local cx = (minX + maxX) * 0.5
			minX = math.clamp(cx - minSize * 0.5, 0, viewport.X)
			maxX = math.clamp(cx + minSize * 0.5, 0, viewport.X)
		end
		if h < minSize then
			local cy = (minY + maxY) * 0.5
			minY = math.clamp(cy - minSize * 0.5, 0, viewport.Y)
			maxY = math.clamp(cy + minSize * 0.5, 0, viewport.Y)
		end
		w, h = maxX - minX, maxY - minY
		if w <= 0 or h <= 0 then return nil end
	elseif w < 1 or h < 1 then
		return nil
	end

	return minX, minY, maxX, maxY
end

-- ══════════════════════════════════════════════════════════════════
--  ANGEL ALERT
-- ══════════════════════════════════════════════════════════════════

local function aimPosition(model)
	local root = model:FindFirstChild("Root") or model.PrimaryPart
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local ok, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	return ok and pivot or nil
end

local function findNearestAngel(refPos, radius)
	local best, bestPos, bestDist, count = nil, nil, nil, 0
	for model, entry in pairs(tracked) do
		if entry.isAngel and model.Parent then
			local ok, pivot = pcall(function()
				return model:GetPivot().Position
			end)
			if ok then
				local d = (pivot - refPos).Magnitude
				if d <= radius then
					count += 1
					if not bestDist or d < bestDist then
						best, bestPos, bestDist = model, pivot, d
					end
				end
			end
		end
	end
	return best, bestPos, bestDist, count
end

local function updateAngelAlert(camera, viewport, refPos)
	local cfg = CONFIG.AngelAlert
	if not cfg.Enabled then
		clearAlert()
		return
	end

	local model, pivot, dist, count = findNearestAngel(refPos, cfg.Radius)
	if not model then
		clearAlert()
		return
	end

	local aim = aimPosition(model) or pivot
	alert.target, alert.aim, alert.dist = model, aim, dist

	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)

	if cfg.ShowBanner then
		local text = string.format("%s  %dm", cfg.Text, math.floor(dist + 0.5))
		if count > 1 then
			text = string.format("%s x%d  %dm", cfg.Text, count, math.floor(dist + 0.5))
		end
		alertBanner.Text = text
		alertBanner.TextColor3 = cfg.Color
		alertBanner.TextTransparency = 0.1 + 0.35 * pulse
		alertBanner.Visible = true
	else
		alertBanner.Visible = false
	end

	if not cfg.ShowOffscreenArrow then
		alertArrow.Visible = false
		return
	end

	local vp = camera:WorldToViewportPoint(aim)
	local margin = cfg.EdgeMargin
	local onScreen = vp.Z > 0
		and vp.X >= margin and vp.X <= viewport.X - margin
		and vp.Y >= margin and vp.Y <= viewport.Y - margin

	if onScreen then
		alertArrow.Visible = false
		return
	end

	local rel = camera.CFrame:PointToObjectSpace(aim)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 1e-3 then
		dir = Vector2.new(0, -1)
	end
	dir = dir.Unit

	local center = Vector2.new(viewport.X, viewport.Y) * 0.5
	local half = Vector2.new(viewport.X * 0.5 - margin, viewport.Y * 0.5 - margin)
	local scale = math.min(
		half.X / math.max(math.abs(dir.X), 1e-4),
		half.Y / math.max(math.abs(dir.Y), 1e-4)
	)
	local pos = center + dir * scale

	alertArrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	alertArrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
	alertArrow.TextColor3 = cfg.Color
	alertArrow.TextTransparency = 0.05 + 0.35 * pulse
	alertArrow.TextStrokeTransparency = 0.4 + 0.3 * pulse
	alertArrow.Visible = true
end

local function formatTagText(name, dist)
	if not CONFIG.ShowDistance then
		return name
	end
	local ok, text = pcall(string.format, CONFIG.TagFormat, name, dist)
	if ok then
		return text
	end
	return string.format("%s [%dm]", name, dist)
end

-- ══════════════════════════════════════════════════════════════════
--  OVERLAY OBJECT
-- ══════════════════════════════════════════════════════════════════

Overlay = {
	Enabled = true,
	GuiVisible = true,
	Config = CONFIG,
	_connections = {},
}

function Overlay:SetEnabled(enabled)
	self.Enabled = enabled and true or false
	if not self.Enabled then
		hideAllVisuals()
	end
	updateHud()
end

function Overlay:ToggleEnabled()
	self:SetEnabled(not self.Enabled)
end

function Overlay:SetGuiVisible(visible)
	self.GuiVisible = visible and true or false
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

function Overlay:Rescan()
	reconcile()
end

function Overlay:RemoveFog(on)
	fogToggle.setState(on)
end

function Overlay:RemoveDarkness(on)
	darknessToggle.setState(on)
end

function Overlay:Destroy()
	for _, conn in ipairs(self._connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._connections = {}

	for model in pairs(tracked) do
		destroyOverlay(model)
	end
	for inst in pairs(itemTracked) do
		destroyItemOverlay(inst)
	end

	table.clear(targetFolders)
	table.clear(tracked)
	table.clear(itemTracked)

	pcall(function()
		RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND)
	end)

	clearAlert()

	-- restore environment
	restoreFog()
	restoreDarkness()

	if screenGui then
		screenGui:Destroy()
	end

	if _G.AislesOfTheLocust == self then
		_G.AislesOfTheLocust = nil
	end
end

-- ══════════════════════════════════════════════════════════════════
--  CONNECTIONS
-- ══════════════════════════════════════════════════════════════════

local descendantAddedConn = Workspace.DescendantAdded:Connect(noteFolder)
local descendantRemovingConn = Workspace.DescendantRemoving:Connect(function(d)
	if targetFolders[d] then
		unregisterFolder(d)
		reconcile()
		updateHud()
	end
end)

table.insert(Overlay._connections, descendantAddedConn)
table.insert(Overlay._connections, descendantRemovingConn)

-- Insert key to toggle the whole GUI
table.insert(Overlay._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.GuiToggleKey then
		Overlay:ToggleGui()
	end
end))

-- ══════════════════════════════════════════════════════════════════
--  RENDER LOOP
-- ══════════════════════════════════════════════════════════════════

local lastScan = 0
local lastItemScan = 0
local visualsHidden = false

local renderConn = RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now - lastScan >= CONFIG.RescanInterval then
		lastScan = now
		reconcile()
	end

	if not Overlay.Enabled then
		if not visualsHidden then
			hideAllVisuals()
			visualsHidden = true
		end
		return
	end

	if not Overlay.GuiVisible then
		if not visualsHidden then
			hideAllVisuals()
			visualsHidden = true
		end
		return
	end

	visualsHidden = false

	local camera = Workspace.CurrentCamera
	if not camera then
		hideAllVisuals()
		return
	end

	local viewport = camera.ViewportSize
	local camPos = camera.CFrame.Position

	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = root and root.Position or camPos

	-- ── Item scan (slower interval) ──────────────────────────────
	if now - lastItemScan >= CONFIG.ItemESP.ScanInterval then
		lastItemScan = now
		scanForItems(refPos)
		updateHud()
	end

	-- ── Entity ESP ───────────────────────────────────────────────
	for model, entry in pairs(tracked) do
		local box, tag = entry.box, entry.tag
		local hide = false
		local rect

		if entry.stateColors and entry.stroke then
			local state = model:GetAttribute(entry.stateAttribute)
			local color = (state and entry.stateColors[state]) or entry.baseColor
			if entry.lastStateColor ~= color then
				entry.lastStateColor = color
				entry.stroke.Color = color
			end
		end

		local ok, pivot = pcall(function()
			return model:GetPivot().Position
		end)

		if not ok then
			hide = true
		else
			local dist = (pivot - refPos).Magnitude
			local shown = math.floor(dist + 0.5)
			local name = model.Name
			local maxDistance = entry.maxDistance
			if maxDistance == nil then
				maxDistance = CONFIG.MaxDistance
			end

			if maxDistance > 0 and dist > maxDistance then
				hide = true
			end

			if not hide then
				if entry.lastName ~= name
					or entry.lastDist ~= shown
					or entry.lastShowDistance ~= CONFIG.ShowDistance
					or entry.lastTagFormat ~= CONFIG.TagFormat then
					entry.lastName = name
					entry.lastDist = shown
					entry.lastShowDistance = CONFIG.ShowDistance
					entry.lastTagFormat = CONFIG.TagFormat
					tag.Text = formatTagText(name, shown)
				end
			end
		end

		if not hide then
			rect = { projectModel(camera, model, viewport, entry.minSize) }
			if rect[1] == nil then
				hide = true
			end
		end

		if hide then
			hideEntry(entry)
		else
			local minX, minY, maxX, maxY = rect[1], rect[2], rect[3], rect[4]
			local w, h = maxX - minX, maxY - minY

			box.Position = UDim2.fromOffset(minX, minY)
			box.Size = UDim2.fromOffset(w, h)
			box.Visible = true

			tag.Position = UDim2.fromOffset(minX + w * 0.5, minY - CONFIG.TagOffset)
			tag.Visible = true
		end
	end

	-- ── Item ESP (shopping list overlays) ────────────────────────
	for inst, entry in pairs(itemTracked) do
		local box, tag = entry.box, entry.tag
		local hide = false
		local rect

		if not inst.Parent then
			hide = true
		else
			local pos = getItemPosition(inst)
			if not pos then
				hide = true
			else
				local dist = (pos - refPos).Magnitude
				local shown = math.floor(dist + 0.5)
				local maxDist = entry.maxDistance or 0
				if maxDist > 0 and dist > maxDist then
					hide = true
				end
				if not hide then
					tag.Text = string.format("🛒 %s [%dm]", inst.Name, shown)
				end
			end
		end

		if not hide then
			if inst:IsA("Model") then
				rect = { projectModel(camera, inst, viewport, entry.minSize) }
			else
				rect = { projectPart(camera, inst, viewport, entry.minSize) }
			end
			if rect[1] == nil then
				hide = true
			end
		end

		if hide then
			hideEntry(entry)
		else
			local minX, minY, maxX, maxY = rect[1], rect[2], rect[3], rect[4]
			local w, h = maxX - minX, maxY - minY

			box.Position = UDim2.fromOffset(minX, minY)
			box.Size = UDim2.fromOffset(w, h)
			box.Visible = true

			tag.Position = UDim2.fromOffset(minX + w * 0.5, minY - CONFIG.TagOffset)
			tag.Visible = true
		end
	end

	updateAngelAlert(camera, viewport, refPos)
end)

table.insert(Overlay._connections, renderConn)

-- ── Camera lock ──────────────────────────────────────────────────

pcall(function()
	RunService:UnbindFromRenderStep(ANGEL_LOOK_BIND)
end)
RunService:BindToRenderStep(ANGEL_LOOK_BIND, Enum.RenderPriority.Camera.Value + 1, function()
	local cfg = CONFIG.AngelAlert
	if not Overlay.Enabled or not Overlay.GuiVisible or not cfg.Enabled or not cfg.LockCamera then
		return
	end

	local target, aim = alert.target, alert.aim
	if not target or not aim or not target.Parent then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = camera.CFrame.Position
	if (aim - origin).Magnitude < 0.05 then
		return
	end

	camera.CFrame = CFrame.lookAt(origin, aim)
end)

-- ══════════════════════════════════════════════════════════════════
--  STARTUP
-- ══════════════════════════════════════════════════════════════════

_G.AislesOfTheLocust = Overlay

updateHud()
reconcile()

-- initial item scan
do
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = root and root.Position or (Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position or Vector3.zero)
	scanForItems(refPos)
end

print("[AislesOfTheLocust] refined active — watching folders: " .. table.concat((function()
	local names = {}
	for name in pairs(CONFIG.FolderNames) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end)(), ", "))
print("[AislesOfTheLocust] shopping list: " .. table.concat(CONFIG.ShoppingList, ", "))
print("[AislesOfTheLocust] press Insert to show/hide the GUI")
