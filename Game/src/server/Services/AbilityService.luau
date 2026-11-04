--!strict
-- AbilityService: storage, equip slots and using abilities (vault: 03 Systems → Abilities & Equip).
-- Status: storage + equip (EquipAbility / UnequipAbility) and UseAbility for melee and
-- projectile abilities. AoE / Movement / Defense use come with those abilities. Delete/Lock come
-- with the full Inventory screen.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Economy = require(Config:WaitForChild("Economy"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HitboxService = require(script.Parent.HitboxService)
local CombatService = require(script.Parent.CombatService)

type AbilityDef = Types.AbilityDef

-- Studio only: every player starts with these in storage, so abilities can be tested
-- without spinning for them. Never runs in the live game.
local STUDIO_STARTER_ABILITIES = { "EmberFist", "PebbleToss" }

-- Small allowance so a press sent the moment the cooldown ends isn't rejected because of ping.
local LATENCY_ALLOWANCE = 0.2
-- Melee abilities hit at most this many targets.
local MELEE_MAX_TARGETS = 4
-- Where a thrown projectile leaves the hand, from the HumanoidRootPart: right, up, forward (studs).
-- Measured on the Pebble Toss release frame. The server can't use the hand itself: it doesn't
-- run the thrower's animation, so their hand is in its rest pose here.
local THROW_OFFSET = Vector3.new(0.86, 0.47, 3.04)

local AbilityService = {}

local defsById: { [string]: AbilityDef } = {}
for _, def in Abilities do
	defsById[def.Id] = def
end

-- [player][abilityId] = server clock when it can be used again
local readyAt: { [Player]: { [string]: number } } = {}
local abilityUsed: RemoteEvent
local abilityHit: RemoteEvent

local function storageCount(data: DataService.PlayerData): number
	local count = 0
	for _ in data.Inventory do
		count += 1
	end
	return count
end

local function isEquipped(data: DataService.PlayerData, uniqueId: string): boolean
	for _, equipped in data.Equipped do
		if equipped == uniqueId then
			return true
		end
	end
	return false
end

-- How many equip slots the player can use (vault plans 2, +1 at 100 KOs / with the
-- +1 Equip Slot pass; for now FreeSlots opens all of them). Never more than MaxSlots.
function AbilityService.SlotCount(player: Player): number
	local data = DataService.Get(player)
	local count = Economy.FreeSlots
	if data and (data.KOs >= Economy.ThirdSlotKOs or MonetizationService.HasPass(player, "ExtraSlot")) then
		count += 1
	end
	return math.min(count, Economy.MaxSlots)
end

function AbilityService.IsStorageFull(player: Player): boolean
	local data = DataService.Get(player)
	return data == nil or storageCount(data) >= data.MaxStorage
end

-- Put an ability in storage. If storage is full, replaceUniqueId must name an owned,
-- unlocked, unequipped ability to throw away. Returns the new uniqueId, or nil + reason.
function AbilityService.AddToStorage(player: Player, abilityId: string, replaceUniqueId: string?): (string?, string?)
	local data = DataService.Get(player)
	if not data then
		return nil, "NotLoaded"
	end

	if storageCount(data) >= data.MaxStorage then
		if not replaceUniqueId then
			return nil, "StorageFull"
		end
		if not data.Inventory[replaceUniqueId] then
			return nil, "NotOwned"
		end
		if data.Locked[replaceUniqueId] then
			return nil, "Locked"
		end
		if isEquipped(data, replaceUniqueId) then
			return nil, "Equipped"
		end
		data.Inventory[replaceUniqueId] = nil
	end

	local uniqueId = HttpService:GenerateGUID(false)
	data.Inventory[uniqueId] = { AbilityId = abilityId, Level = 1 }
	DataService.Changed(player, { "Inventory" })
	return uniqueId, nil
end

-- Put an owned ability in a slot. If it's already in another slot, it moves.
function AbilityService.Equip(player: Player, uniqueId: string, slot: number): (boolean, string?)
	local data = DataService.Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if not data.Inventory[uniqueId] then
		return false, "NotOwned"
	end
	if slot % 1 ~= 0 or slot < 1 or slot > AbilityService.SlotCount(player) then
		return false, "BadSlot"
	end
	for i, equipped in data.Equipped do
		if equipped == uniqueId then
			data.Equipped[i] = false
		end
	end
	data.Equipped[slot] = uniqueId
	DataService.Changed(player, { "Equipped" })
	return true, nil
end

function AbilityService.Unequip(player: Player, slot: number): (boolean, string?)
	local data = DataService.Get(player)
	if not data then
		return false, "NotLoaded"
	end
	if slot % 1 ~= 0 or slot < 1 or slot > Economy.MaxSlots then
		return false, "BadSlot"
	end
	data.Equipped[slot] = false
	DataService.Changed(player, { "Equipped" })
	return true, nil
end

-- ===== Using abilities =====

local function useMelee(player: Player, character: Model, root: BasePart, def: AbilityDef, aim: Vector3)
	-- The hit lands when the animation's punch does, not when the key was pressed.
	task.wait(def.WindupSeconds or 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not root.Parent then
		return
	end

	local power = Rarities.Defs[def.Rarity].Power
	local damage = def.Damage * power
	local targets = HitboxService.InFront(character, root, aim, def.Range, def.HitboxWidth or 5, MELEE_MAX_TARGETS)
	for _, target in targets do
		local targetRoot = target.Parent and target.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
		local knockback = Vector3.zero
		if targetRoot and def.Knockback then
			local away = targetRoot.Position - root.Position
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(aim.X, 0, aim.Z).Unit
			knockback = away * def.Knockback + Vector3.new(0, def.Knockback * 0.4, 0)
		end
		CombatService.DealDamage(player, target, damage, knockback, def.Id)
	end
end

-- Flies a projectile in a straight line, sweeping a sphere along it every frame. The first
-- character or wall it touches is the hit: damage (characters only), then every client plays
-- the impact (AbilityHit). Nothing is sent if it flies its full range without touching anything.
local function useProjectile(player: Player, character: Model, root: BasePart, def: AbilityDef, aim: Vector3)
	task.wait(def.WindupSeconds or 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not root.Parent then
		return
	end

	local flat = Vector3.new(aim.X, 0, aim.Z).Unit
	local right = flat:Cross(Vector3.yAxis)
	local chest = root.Position + Vector3.new(0, THROW_OFFSET.Y, 0)
	local hand = chest + right * THROW_OFFSET.X + flat * THROW_OFFSET.Z
	local speed = def.ProjectileSpeed or 80
	local radius = def.ProjectileRadius or 0.5

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	-- First sweep: from the chest to the hand, so a target standing right in front still gets hit.
	local position = chest
	local travelled = -(hand - chest).Magnitude
	local step = hand - chest
	while true do
		local result = workspace:Spherecast(position, radius, step, params)
		if result then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			local target = model and model:FindFirstChildOfClass("Humanoid")
			if target and target.Health > 0 then
				local power = Rarities.Defs[def.Rarity].Power
				local knockback = flat * (def.Knockback or 0) + Vector3.new(0, (def.Knockback or 0) * 0.4, 0)
				CombatService.DealDamage(player, target, def.Damage * power, knockback, def.Id)
			end
			abilityHit:FireAllClients(character, def.Id, result.Position, result.Normal)
			return
		end
		position += step
		travelled += step.Magnitude
		if travelled >= def.Range then
			return
		end
		local dt = RunService.Heartbeat:Wait()
		step = flat * math.min(speed * dt, def.Range - travelled)
	end
end

local function onUseAbility(player: Player, slot: number, aim: Vector3)
	local data = DataService.Get(player)
	if not data or slot > AbilityService.SlotCount(player) then
		return
	end
	local uniqueId = data.Equipped[slot]
	if not uniqueId then
		return
	end
	local owned = data.Inventory[uniqueId]
	local def = owned and defsById[owned.AbilityId]
	if not def then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	-- Cooldown on the server clock.
	local now = os.clock()
	local perPlayer = readyAt[player]
	if not perPlayer then
		perPlayer = {}
		readyAt[player] = perPlayer
	end
	if now < (perPlayer[def.Id] or 0) - LATENCY_ALLOWANCE then
		return
	end
	perPlayer[def.Id] = now + def.Cooldown

	-- Everyone else plays the animation + VFX (the attacker already did, instantly).
	for _, other in Players:GetPlayers() do
		if other ~= player then
			abilityUsed:FireClient(other, character, def.Id, aim)
		end
	end

	if def.Type == "Melee" then
		useMelee(player, character, root, def, aim)
	elseif def.Type == "Projectile" then
		useProjectile(player, character, root, def, aim)
	end
end

local function isUnitVector(x: unknown): boolean
	if typeof(x) ~= "Vector3" then
		return false
	end
	local v = x :: Vector3
	return RemoteGuard.IsFiniteNumber(v.X)
		and RemoteGuard.IsFiniteNumber(v.Y)
		and RemoteGuard.IsFiniteNumber(v.Z)
		and math.abs(v.Magnitude - 1) < 0.05
end

local function giveStudioStarters(player: Player)
	-- PlayerAdded handlers run in no fixed order, so wait for DataService to load the player.
	while not DataService.Get(player) and player.Parent do
		task.wait()
	end
	local data = DataService.Get(player)
	for slot, abilityId in STUDIO_STARTER_ABILITIES do
		local uniqueId = AbilityService.AddToStorage(player, abilityId, nil)
		-- Also put it on the hotbar (slot 1, 2, ...) if that slot is free and it isn't there already.
		local alreadyEquipped = false
		if data then
			for _, equipped in data.Equipped do
				local owned = equipped and data.Inventory[equipped]
				if owned and owned.AbilityId == abilityId then
					alreadyEquipped = true
				end
			end
		end
		if uniqueId and data and not alreadyEquipped and not data.Equipped[slot] then
			AbilityService.Equip(player, uniqueId, slot)
		end
	end
end

function AbilityService.Init()
	abilityUsed = Remotes.Event("AbilityUsed")
	abilityHit = Remotes.Event("AbilityHit")
end

function AbilityService.Start()
	RemoteGuard.Event("EquipAbility", { PerSecond = 4, Burst = 8 }, function(uniqueId, slot)
		return RemoteGuard.IsString(uniqueId, 64) and RemoteGuard.IsInteger(slot, 1, Economy.MaxSlots)
	end, function(player, uniqueId, slot)
		AbilityService.Equip(player, uniqueId, slot)
	end)

	RemoteGuard.Event("UnequipAbility", { PerSecond = 4, Burst = 8 }, function(slot)
		return RemoteGuard.IsInteger(slot, 1, Economy.MaxSlots)
	end, function(player, slot)
		AbilityService.Unequip(player, slot)
	end)

	RemoteGuard.Event("UseAbility", { PerSecond = 5, Burst = 5 }, function(slot, aim)
		return RemoteGuard.IsInteger(slot, 1, Economy.MaxSlots) and isUnitVector(aim)
	end, onUseAbility)

	if RunService:IsStudio() then
		Players.PlayerAdded:Connect(giveStudioStarters)
		for _, player in Players:GetPlayers() do
			task.spawn(giveStudioStarters, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
	end)
end

return AbilityService
