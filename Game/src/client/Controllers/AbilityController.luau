--!strict
-- AbilityController: the ability hotbar (4 slots, keys 1-4 + tap), local cooldowns, and
-- playing every player's ability animation + VFX (vault: 06 UI-UX → HUD → Ability slots).
--
-- The client plays its own move instantly and asks the server (UseAbility); the server checks
-- the cooldown, finds targets and deals damage, then tells everyone else (AbilityUsed).
-- Projectiles: the server flies them and tells every client where they hit (AbilityHit).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
local AbilityEffects = Client:WaitForChild("Abilities")

type AbilityDef = Types.AbilityDef
type Effect = {
	Play: (character: Model, aim: Vector3, isLocal: boolean) -> (),
	-- Projectiles: the server says where the attacker's projectile hit (AbilityHit).
	Hit: ((character: Model, position: Vector3, normal: Vector3) -> ())?,
}

local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local GaleStepVFX = require(AbilityEffects:WaitForChild("GaleStepVFX"))

-- Abilities whose animation + VFX are built. The rest still work on the server, with no visuals yet.
local EFFECTS: { [string]: Effect } = {
	EmberFist = require(AbilityEffects:WaitForChild("EmberFist")) :: any,
	PebbleToss = require(AbilityEffects:WaitForChild("PebbleTossVFX")) :: any,
	GaleStep = GaleStepVFX :: any,
}

-- After using any ability, others can't start until this ends (so animations don't overlap).
local BUSY_SECONDS = 0.5
local SLOT_SIZE = 68
local SLOT_GAP = 10

type SlotView = {
	Button: TextButton,
	Outline: UIStroke,
	Icon: ImageLabel,
	Name: TextLabel,
	Cooldown: Frame,
	Seconds: TextLabel,
	Scale: UIScale,
}

local AbilityController = {}

local defsById: { [string]: AbilityDef } = {}
for _, def in Abilities do
	defsById[def.Id] = def
end

local useAbility: RemoteEvent
local slots: { SlotView } = {}
local readyAt: { [string]: number } = {} -- [abilityId] = os.clock() when usable again
local busyUntil = 0

local function abilityInSlot(slot: number): AbilityDef?
	local uniqueId = PlayerState.Equipped()[slot]
	if not uniqueId then
		return nil
	end
	local owned = PlayerState.Inventory()[uniqueId]
	return owned and defsById[owned.AbilityId]
end

local function buildSlot(parent: Instance, slot: number): SlotView
	local button = Instance.new("TextButton")
	button.Name = `Slot{slot}`
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = slot
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = Theme.Colors.Card
	button.BackgroundTransparency = Theme.PanelTransparency
	Theme.Round(button, UDim.new(0.2, 0))
	local outline = Theme.Outline(button)
	button.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.86, 0.86)
	icon.Image = ""
	icon.Parent = button

	-- Name along the bottom (whole slot when there's no icon).
	local name = Theme.Label(button, "", Theme.Fonts.Body, 11)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -2)
	name.Size = UDim2.new(1, -4, 0, 14)
	name.TextWrapped = true

	-- Dark sweep: covers the slot and shrinks downward as the cooldown runs out.
	local cooldown = Instance.new("Frame")
	cooldown.Name = "Cooldown"
	cooldown.AnchorPoint = Vector2.new(0, 1)
	cooldown.Position = UDim2.fromScale(0, 1)
	cooldown.Size = UDim2.fromScale(1, 0)
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = 0.35
	cooldown.BorderSizePixel = 0
	cooldown.ZIndex = 2
	Theme.Round(cooldown, UDim.new(0.2, 0))
	cooldown.Parent = button

	local seconds = Theme.Label(button, "", Theme.Fonts.Title, 26)
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.ZIndex = 3

	local key = Theme.Label(button, tostring(slot), Theme.Fonts.Title, 18)
	key.AnchorPoint = Vector2.new(0, 0)
	key.Position = UDim2.fromOffset(5, 1)
	key.Size = UDim2.fromOffset(16, 20)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.ZIndex = 4

	local scale = Instance.new("UIScale")
	scale.Parent = button

	button.Activated:Connect(function()
		AbilityController.Use(slot)
	end)

	return {
		Button = button,
		Outline = outline,
		Icon = icon,
		Name = name,
		Cooldown = cooldown,
		Seconds = seconds,
		Scale = scale,
	}
end

local function buildHotbar()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hotbar"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local row = Instance.new("Frame")
	row.Name = "Slots"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(Economy.MaxSlots * SLOT_SIZE + (Economy.MaxSlots - 1) * SLOT_GAP, SLOT_SIZE)
	if touchOnly then
		-- Mobile: bottom-right, above and left of the jump button.
		row.AnchorPoint = Vector2.new(1, 1)
		row.Position = UDim2.new(1, -24, 1, -150)
	else
		-- PC: bottom-center row.
		row.AnchorPoint = Vector2.new(0.5, 1)
		row.Position = UDim2.new(0.5, 0, 1, -16)
	end
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	for slot = 1, Economy.MaxSlots do
		slots[slot] = buildSlot(row, slot)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function redraw()
	for slot, view in slots do
		local def = abilityInSlot(slot)
		if def then
			view.Name.Text = def.Name
			view.Icon.Image = def.Icon or ""
			view.Outline.Color = Rarities.Defs[def.Rarity].Color
			view.Button.BackgroundTransparency = Theme.PanelTransparency
		else
			view.Name.Text = ""
			view.Icon.Image = ""
			view.Outline.Color = Theme.Colors.Outline
			view.Button.BackgroundTransparency = 0.5
		end
	end
end

local function updateCooldowns()
	local now = os.clock()
	for slot, view in slots do
		local def = abilityInSlot(slot)
		local left = if def then (readyAt[def.Id] or 0) - now else 0
		if def and left > 0 then
			view.Cooldown.Size = UDim2.fromScale(1, left / def.Cooldown)
			view.Seconds.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
		else
			view.Cooldown.Size = UDim2.fromScale(1, 0)
			view.Seconds.Text = ""
		end
	end
end

-- Shake the slot a little when it can't be used (on cooldown / dead / busy).
local function nope(slot: number)
	local view = slots[slot]
	if not view then
		return
	end
	view.Scale.Scale = 0.9
	task.delay(0.08, function()
		view.Scale.Scale = 1
	end)
end

function AbilityController.Use(slot: number)
	local def = abilityInSlot(slot)
	if not def then
		return
	end
	local now = os.clock()
	if now < (readyAt[def.Id] or 0) or now < busyUntil then
		nope(slot)
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		nope(slot)
		return
	end

	readyAt[def.Id] = now + def.Cooldown
	busyUntil = now + BUSY_SECONDS

	-- Aim where the character faces (soft-aim at the nearest enemy comes with mobile combat).
	-- Dashes go where the camera faces instead.
	local aim = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	if def.Type == "Movement" then
		aim = GaleStepVFX.Aim() or aim
	end
	useAbility:FireServer(slot, aim)

	local effect = EFFECTS[def.Id]
	if effect then
		effect.Play(character, aim, true)
	end

	local view = slots[slot]
	view.Scale.Scale = 0.92
	task.delay(0.1, function()
		view.Scale.Scale = 1
	end)
end

function AbilityController.Init()
	useAbility = Remotes.Event("UseAbility")
end

function AbilityController.Start()
	buildHotbar()
	redraw()
	PlayerState.Changed:Connect(redraw)
	RunService.RenderStepped:Connect(updateCooldowns)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local slot = KEYS[input.KeyCode]
		if slot then
			AbilityController.Use(slot)
		end
	end)

	-- Other players' moves: same animation + VFX, no camera shake.
	Remotes.Event("AbilityUsed").OnClientEvent:Connect(function(character: Model, abilityId: string, aim: Vector3)
		local effect = EFFECTS[abilityId]
		if effect and character and character.Parent then
			effect.Play(character, aim, false)
		end
	end)

	-- Projectile hits (everyone, the attacker too): the server decided it, every client shows it.
	Remotes.Event("AbilityHit").OnClientEvent:Connect(function(character: Model, abilityId: string, position: Vector3, normal: Vector3)
		local effect = EFFECTS[abilityId]
		if effect and effect.Hit and character then
			effect.Hit(character, position, normal)
		end
	end)
end

return AbilityController
