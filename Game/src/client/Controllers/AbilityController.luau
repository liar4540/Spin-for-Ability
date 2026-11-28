--!strict
-- AbilityController: the ability hotbar (4 slots, keys 1-4 + tap), local cooldowns, and
-- playing every player's ability animation + VFX (vault: 06 UI-UX → HUD → Ability slots).
--
-- The client plays its own move instantly and asks the server (UseAbility); the server checks
-- the cooldown, finds targets and deals damage, then tells everyone else (AbilityUsed).
-- Projectiles: the server flies them and tells every client where they hit (AbilityHit). Server-clock
-- ones (Thunder Lance) are also announced to the other clients when they leave the hand (AbilityLaunch).
-- Melee with on-hit VFX (Frost Jab): the server tells every client who was hit (AbilityImpact).

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
	-- Projectiles: the server says where the attacker's projectile hit (AbilityHit); server-clock ones
	-- (Thunder Lance) also get the target, the server time of the hit and the seed.
	Hit: ((character: Model, position: Vector3, normal: Vector3, target: Model?, serverTime: number?, seed: number?) -> ())?,
	-- Server-clock projectiles: another player's left their hand (AbilityLaunch).
	Launch: ((character: Model, origin: Vector3, direction: Vector3, serverTime: number, seed: number) -> ())?,
	-- Melee: the server says who the attacker's hit landed on, and when (AbilityImpact).
	Impact: ((character: Model, hits: { { Target: Model, Position: Vector3 } }, serverTime: number) -> ())?,
	-- Sky strike after a projectile's character hit (AbilityStrike): where it lands, when, the seed.
	Strike: ((character: Model, target: Model?, groundPos: Vector3, serverTime: number, seed: number) -> ())?,
	-- Lock-on teleports: false = can't be used right now (no enemy in range), so nothing plays and no cooldown starts.
	CanUse: ((character: Model) -> boolean)?,
	-- Lock-on teleports: the target this client picked, sent with UseAbility so the server lands us there too.
	Pick: ((character: Model) -> Model?)?,
	-- Channelled beam (AbilityBeam): "Fire" with origin / direction / length, or "Stop" (interrupted).
	Beam: ((character: Model, phase: string, origin: Vector3?, direction: Vector3?, length: number?, serverTime: number?) -> ())?,
	-- Lock-on teleport landed (AbilityTeleport): from, to, the target, the server time.
	Teleport: ((character: Model, from: Vector3, to: Vector3, target: Model?, serverTime: number) -> ())?,
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
	FrostJab = require(AbilityEffects:WaitForChild("FrostJabVFX")) :: any,
	ThunderLance = require(AbilityEffects:WaitForChild("ThunderLanceVFX")) :: any,
	ShadowSwap = require(AbilityEffects:WaitForChild("ShadowSwapVFX")) :: any,
	BloodMoonSlash = require(AbilityEffects:WaitForChild("BloodMoonSlashVFX")) :: any,
	StarCannon = require(AbilityEffects:WaitForChild("StarCannonVFX")) :: any,
	FrostBloom = require(AbilityEffects:WaitForChild("FrostBloomVFX")) :: any,
	Sever = require(AbilityEffects:WaitForChild("SeverVFX")) :: any,
	AltarOfRuin = require(AbilityEffects:WaitForChild("AltarOfRuinVFX")) :: any,
}

-- After using any ability, others can't start until this ends (so animations don't overlap).
local BUSY_SECONDS = 0.5
-- Combat states that can't use abilities (mirrors the server's StateService rules).
local BLOCKED_STATES: { [string]: boolean } =
	{ Stunned = true, Ragdolled = true, GuardBroken = true, Blocking = true, Casting = true }
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
	-- Same state rules as the server (StateService), so a stunned / ragdolled / blocking player
	-- doesn't play an ability the server will refuse. The server still decides.
	local state = character:GetAttribute("CombatState")
	if type(state) == "string" and BLOCKED_STATES[state] then
		nope(slot)
		return
	end

	local effect = EFFECTS[def.Id]
	if effect and effect.CanUse and not effect.CanUse(character) then
		nope(slot) -- e.g. Shadow Swap with no enemy in range: not cast, no cooldown
		return
	end

	local devNoCooldown = RunService:IsStudio() and Players.LocalPlayer:GetAttribute("DevNoCooldown") == true
	readyAt[def.Id] = now + (if devNoCooldown then 0 else def.Cooldown)
	busyUntil = now + BUSY_SECONDS

	-- Aim where the character faces (soft-aim at the nearest enemy comes with mobile combat).
	-- Dashes go where the camera faces instead.
	local aim = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	if def.Type == "Movement" then
		aim = GaleStepVFX.Aim() or aim
	end
	useAbility:FireServer(slot, aim, if effect and effect.Pick then effect.Pick(character) else nil)

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

-- Studio-only test button: toggles no cooldowns for this player (the server checks IsStudio too).
-- Not part of the game: it is never built outside Studio.
local function buildDevButton()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevNoCooldown", 10) :: RemoteEvent?
	if not remote then
		return
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTools"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	local button = Instance.new("TextButton")
	button.Name = "NoCooldown"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, 60)
	button.Size = UDim2.fromOffset(150, 34)
	button.BackgroundColor3 = Theme.Colors.Panel
	button.BackgroundTransparency = Theme.PanelTransparency
	button.TextColor3 = Theme.Colors.Text
	button.Font = Theme.Fonts.Body
	button.TextSize = 16
	button.AutoButtonColor = true
	Theme.Round(button)
	local stroke = Theme.Outline(button)
	button.Parent = gui
	local function refresh()
		local on = player:GetAttribute("DevNoCooldown") == true
		button.Text = if on then "No cooldown: ON" else "No cooldown: OFF"
		stroke.Color = if on then Theme.Colors.Good else Theme.Colors.Outline
		if on then
			table.clear(readyAt)
		end
	end
	refresh()
	player:GetAttributeChangedSignal("DevNoCooldown"):Connect(refresh)
	button.Activated:Connect(function()
		remote:FireServer()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function AbilityController.Start()
	if RunService:IsStudio() then
		task.spawn(buildDevButton)
	end
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

	-- The server refused a cast (state or cooldown): put the local cooldown back to the server's.
	Remotes.Event("CombatResult").OnClientEvent:Connect(function(kind: string, slot: any, accepted: any, readyIn: any)
		if kind ~= "Ability" or accepted ~= false or type(slot) ~= "number" then
			return
		end
		local def = abilityInSlot(slot)
		if def then
			readyAt[def.Id] = os.clock() + (if type(readyIn) == "number" then readyIn else 0)
			busyUntil = 0
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
	Remotes.Event("AbilityHit").OnClientEvent:Connect(function(character: Model, abilityId: string, position: Vector3, normal: Vector3,
		target: Model?, serverTime: number?, seed: number?)
		local effect = EFFECTS[abilityId]
		if effect and effect.Hit and character then
			effect.Hit(character, position, normal, target, serverTime, seed)
		end
	end)

	-- Server-clock projectiles (everyone but the thrower, who launched its own on the Release marker).
	Remotes.Event("AbilityLaunch").OnClientEvent:Connect(function(character: Model, abilityId: string, origin: Vector3,
		direction: Vector3, serverTime: number, seed: number)
		local effect = EFFECTS[abilityId]
		if effect and effect.Launch and character and character.Parent then
			effect.Launch(character, origin, direction, serverTime, seed)
		end
	end)

	-- Sky strikes (everyone, the attacker too): the server picked the spot right after the hit; the
	-- target may already be gone (dead, reset, left), so it plays at the ground position it sent.
	Remotes.Event("AbilityStrike").OnClientEvent:Connect(function(character: Model, abilityId: string, target: Model?,
		groundPos: Vector3, serverTime: number, seed: number)
		local effect = EFFECTS[abilityId]
		if effect and effect.Strike and character then
			effect.Strike(character, target, groundPos, serverTime, seed)
		end
	end)

	-- Channelled beams (everyone): where the beam fires, or that it was stopped.
	Remotes.Event("AbilityBeam").OnClientEvent:Connect(function(character: Model, abilityId: string, phase: string,
		origin: Vector3?, direction: Vector3?, length: number?, serverTime: number?)
		local effect = EFFECTS[abilityId]
		if effect and effect.Beam and character then
			effect.Beam(character, phase, origin, direction, length, serverTime)
		end
	end)

	-- Lasting zones (everyone, the caster too): where it stands, how big, when it starts and ends.
	Remotes.Event("AbilityZone").OnClientEvent:Connect(function(character: Model, abilityId: string, phase: string,
		center: CFrame?, radius: number?, activeAt: number?, endsAt: number?)
		local effect = EFFECTS[abilityId] :: any
		if effect and effect.Zone and character then
			effect.Zone(character, phase, center, radius, activeAt, endsAt)
		end
	end)

	-- Lock-on teleports (everyone; the caster already played its own and ignores this unless it was off).
	Remotes.Event("AbilityTeleport").OnClientEvent:Connect(function(character: Model, abilityId: string, from: Vector3, to: Vector3,
		target: Model?, serverTime: number)
		local effect = EFFECTS[abilityId]
		if effect and effect.Teleport and character then
			effect.Teleport(character, from, to, target, serverTime)
		end
	end)

	-- Melee hits (everyone, the attacker too): the server decided who was hit, every client shows it.
	Remotes.Event("AbilityImpact").OnClientEvent:Connect(function(character: Model, abilityId: string, hits: { any }, serverTime: number)
		local effect = EFFECTS[abilityId]
		if effect and effect.Impact and character and typeof(hits) == "table" then
			effect.Impact(character, hits, serverTime)
		end
	end)
end

return AbilityController
