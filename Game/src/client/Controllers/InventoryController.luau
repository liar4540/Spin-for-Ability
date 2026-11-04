--!strict
-- InventoryController: storage / equip UI (vault: 06 UI-UX → Inventory / Equip).
-- Status: simple first version. Equip slots on top, storage cards below.
-- Tap a card, then tap a slot to equip it. Tap a filled slot with no card picked to unequip.
-- Sort/filter, the info panel, Upgrade, Delete and Lock come with the full Inventory screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Economy = require(Config:WaitForChild("Economy"))

local Client = script.Parent.Parent
local PlayerState = require(Client:WaitForChild("PlayerState"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

type AbilityDef = Types.AbilityDef

local WINDOW_SIZE = Vector2.new(600, 420)
local SLOT_SIZE = 96
local CARD_SIZE = Vector2.new(176, 84)
local PAD = 16

local HINT_PICK = "Tap an ability, then tap a slot. Tap a filled slot to unequip."
local HINT_SLOT = "Now tap a slot for %s."

local InventoryController = {}

local defsById: { [string]: AbilityDef } = {}
for _, def in Abilities do
	defsById[def.Id] = def
end

local equipAbility: RemoteEvent
local unequipAbility: RemoteEvent

local gui: ScreenGui
local window: Frame
local windowScale: UIScale
local fitScale = 1 -- shrinks the window on small screens
local counter: TextLabel
local hint: TextLabel
local grid: ScrollingFrame
local slotButtons: { { Button: TextButton, Outline: UIStroke, Name: TextLabel, Icon: ImageLabel } } = {}
local selected: string? = nil -- uniqueId of the picked card

local function slotOf(uniqueId: string): number?
	for slot, equipped in PlayerState.Equipped() do
		if equipped == uniqueId then
			return slot
		end
	end
	return nil
end

local function redraw()
	if not gui then
		return
	end
	local inventory = PlayerState.Inventory()
	if selected and not inventory[selected] then
		selected = nil
	end

	-- Equip slots
	local equipped = PlayerState.Equipped()
	for slot, view in slotButtons do
		local uniqueId = equipped[slot]
		local owned = uniqueId and inventory[uniqueId]
		local def = owned and defsById[owned.AbilityId]
		view.Name.Text = if def then def.Name else "Empty"
		view.Icon.Image = if def then def.Icon or "" else ""
		view.Name.TextColor3 = if def then Theme.Colors.Text else Theme.Colors.TextDim
		view.Outline.Color = if selected then Theme.Colors.Accent elseif def then Rarities.Defs[def.Rarity].Color else Theme.Colors.Outline
	end

	-- Storage cards (sorted rarest first, then by name)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local ids = {}
	for uniqueId, owned in inventory do
		if defsById[owned.AbilityId] then
			table.insert(ids, uniqueId)
		end
	end
	table.sort(ids, function(a, b)
		local da, db = defsById[inventory[a].AbilityId], defsById[inventory[b].AbilityId]
		local ra, rb = Rarities.Defs[da.Rarity].Rank, Rarities.Defs[db.Rarity].Rank
		if ra ~= rb then
			return ra > rb
		end
		return da.Name < db.Name
	end)

	for order, uniqueId in ids do
		local def = defsById[inventory[uniqueId].AbilityId]
		local rarityColor = Rarities.Defs[def.Rarity].Color
		local card = Instance.new("TextButton")
		card.Name = uniqueId
		card.Text = ""
		card.AutoButtonColor = false
		card.LayoutOrder = order
		card.BackgroundColor3 = Theme.Colors.Card
		Theme.Round(card, UDim.new(0, 12))
		local isSelected = selected == uniqueId
		Theme.Outline(card, if isSelected then Theme.Colors.Accent else rarityColor, if isSelected then 5 else Theme.OutlineStroke)
		card.Parent = grid

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = def.Icon or ""
		icon.Position = UDim2.fromOffset(6, 10)
		icon.Size = UDim2.fromOffset(CARD_SIZE.Y - 20, CARD_SIZE.Y - 20)
		icon.Parent = card
		local textLeft = if def.Icon then CARD_SIZE.Y - 10 else 6

		local name = Theme.Label(card, def.Name, Theme.Fonts.Title, 17)
		name.Size = UDim2.new(1, -textLeft - 6, 0, 40)
		name.Position = UDim2.fromOffset(textLeft, 8)
		name.TextWrapped = true

		local rarity = Theme.Label(card, def.Rarity, Theme.Fonts.Body, 14)
		rarity.Size = UDim2.new(1, -textLeft - 6, 0, 18)
		rarity.Position = UDim2.new(0, textLeft, 1, -24)
		rarity.TextColor3 = rarityColor

		local slot = slotOf(uniqueId)
		if slot then
			local tag = Theme.Label(card, `[{slot}]`, Theme.Fonts.Title, 14)
			tag.TextXAlignment = Enum.TextXAlignment.Right
			tag.Size = UDim2.fromOffset(30, 18)
			tag.Position = UDim2.new(1, -36, 1, -24)
			tag.TextColor3 = Theme.Colors.Accent
		end

		Theme.PressFeel(card)
		card.Activated:Connect(function()
			selected = if selected == uniqueId then nil else uniqueId
			redraw()
		end)
	end

	local count = #ids
	counter.Text = `{count} / {PlayerState.Get("MaxStorage") or Economy.MaxStorage}`
	local pickedOwned = selected and inventory[selected]
	local pickedDef = pickedOwned and defsById[pickedOwned.AbilityId]
	hint.Text = if pickedDef then string.format(HINT_SLOT, pickedDef.Name) else HINT_PICK
end

local function onSlot(slot: number)
	if selected then
		equipAbility:FireServer(selected, slot)
		selected = nil
		redraw()
	elseif PlayerState.Equipped()[slot] then
		unequipAbility:FireServer(slot)
	end
end

function InventoryController.Open()
	selected = nil
	redraw()
	gui.Enabled = true
	windowScale.Scale = fitScale * 0.6
	TweenService:Create(windowScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fitScale }):Play()
end

function InventoryController.Close()
	gui.Enabled = false -- never make the player wait for a close animation
end

local function buildOpenButton(playerGui: Instance)
	local hud = Instance.new("ScreenGui")
	hud.Name = "MenuButtons"
	hud.ResetOnSpawn = false
	hud.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local button = Instance.new("TextButton")
	button.Name = "Inventory"
	button.Text = "🎒"
	button.TextSize = 34
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, PAD, 0.5, 0)
	button.Size = UDim2.fromOffset(64, 64)
	button.BackgroundColor3 = Theme.Colors.Card
	button.AutoButtonColor = false
	Theme.Round(button)
	Theme.Outline(button)
	button.Parent = hud

	local label = Theme.Label(button, "Inventory", Theme.Fonts.Body, 13)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 2)
	label.Size = UDim2.fromOffset(80, 16)

	Theme.PressFeel(button)
	button.Activated:Connect(function()
		if gui.Enabled then
			InventoryController.Close()
		else
			InventoryController.Open()
		end
	end)
	hud.Parent = playerGui
end

local function buildWindow(playerGui: Instance)
	gui = Instance.new("ScreenGui")
	gui.Name = "Inventory"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.IgnoreGuiInset = true

	-- Dark background: tapping it closes the menu.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Parent = gui
	backdrop.Activated:Connect(InventoryController.Close)

	window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y)
	window.BackgroundColor3 = Theme.Colors.Panel
	window.BackgroundTransparency = Theme.PanelTransparency
	window.Active = true -- taps on the window don't fall through to the backdrop
	Theme.Round(window, Theme.PanelCorner)
	Theme.Outline(window)
	window.Parent = gui

	windowScale = Instance.new("UIScale")
	windowScale.Parent = window
	-- Small screens: shrink the whole window to fit.
	local camera = workspace.CurrentCamera
	local function fitToScreen()
		local view = camera.ViewportSize
		fitScale = math.min(1, (view.X - 32) / WINDOW_SIZE.X, (view.Y - 32) / WINDOW_SIZE.Y)
		windowScale.Scale = fitScale
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)
	fitToScreen()

	local title = Theme.Label(window, "INVENTORY", Theme.Fonts.Title, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 10)
	title.Size = UDim2.fromOffset(220, 40)

	counter = Theme.Label(window, "", Theme.Fonts.Title, 22)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.Position = UDim2.fromOffset(PAD + 210, 16)
	counter.Size = UDim2.fromOffset(100, 32)
	counter.TextColor3 = Theme.Colors.Accent

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "✖"
	close.Font = Theme.Fonts.Title
	close.TextSize = 24
	close.TextColor3 = Theme.Colors.Text
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = Theme.Colors.Bad
	close.AutoButtonColor = false
	Theme.Round(close)
	Theme.Outline(close)
	Theme.PressFeel(close)
	close.Activated:Connect(InventoryController.Close)
	close.Parent = window

	-- Equip slots: the player's "build".
	local slotRow = Instance.new("Frame")
	slotRow.Name = "Slots"
	slotRow.BackgroundTransparency = 1
	slotRow.Position = UDim2.fromOffset(PAD, 62)
	slotRow.Size = UDim2.new(1, -PAD * 2, 0, SLOT_SIZE)
	slotRow.Parent = window
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotLayout.Padding = UDim.new(0, 14)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = slotRow

	for slot = 1, Economy.MaxSlots do
		local button = Instance.new("TextButton")
		button.Name = `Slot{slot}`
		button.Text = ""
		button.AutoButtonColor = false
		button.LayoutOrder = slot
		button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		button.BackgroundColor3 = Theme.Colors.Card
		Theme.Round(button, UDim.new(0.2, 0))
		local outline = Theme.Outline(button)
		button.Parent = slotRow

		local key = Theme.Label(button, tostring(slot), Theme.Fonts.Title, 20)
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Position = UDim2.fromOffset(8, 4)
		key.Size = UDim2.fromOffset(20, 22)

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		icon.Size = UDim2.fromOffset(SLOT_SIZE - 34, SLOT_SIZE - 34)
		icon.Image = ""
		icon.Parent = button

		local name = Theme.Label(button, "", Theme.Fonts.Title, 14)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -4)
		name.Size = UDim2.new(1, -8, 0, 18)
		name.TextWrapped = true

		Theme.PressFeel(button)
		button.Activated:Connect(function()
			onSlot(slot)
		end)
		slotButtons[slot] = { Button = button, Outline = outline, Name = name, Icon = icon }
	end

	hint = Theme.Label(window, HINT_PICK, Theme.Fonts.Body, 15)
	hint.Position = UDim2.fromOffset(PAD, 62 + SLOT_SIZE + 8)
	hint.Size = UDim2.new(1, -PAD * 2, 0, 20)
	hint.TextColor3 = Theme.Colors.TextDim

	local storageTop = 62 + SLOT_SIZE + 36
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Storage"
	grid.Position = UDim2.fromOffset(PAD, storageTop)
	grid.Size = UDim2.new(1, -PAD * 2, 1, -storageTop - PAD)
	grid.BackgroundColor3 = Theme.Colors.Card
	grid.BackgroundTransparency = 0.4
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	Theme.Round(grid, UDim.new(0, 12))
	grid.Parent = window

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 10)
	gridPad.PaddingLeft = UDim.new(0, 10)
	gridPad.PaddingRight = UDim.new(0, 10)
	gridPad.PaddingBottom = UDim.new(0, 10)
	gridPad.Parent = grid

	gui.Parent = playerGui
end

function InventoryController.Init()
	equipAbility = Remotes.Event("EquipAbility")
	unequipAbility = Remotes.Event("UnequipAbility")
end

function InventoryController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	buildWindow(playerGui)
	buildOpenButton(playerGui)
	PlayerState.Changed:Connect(redraw)
	redraw()
end

return InventoryController
