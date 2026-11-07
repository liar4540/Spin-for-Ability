--!strict
-- AbilityService: storage, equip slots and using abilities (vault: 03 Systems → Abilities & Equip).
-- Status: storage + equip (EquipAbility / UnequipAbility) and UseAbility for melee and
-- projectile abilities, and dashes (Movement: moved by the client, distance-checked here).
-- AoE / Defense use come with those abilities. Delete/Lock come
-- with the full Inventory screen.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Projectile = require(Shared:WaitForChild("Projectile"))
local Types = require(Shared:WaitForChild("Types"))
local Economy = require(Config:WaitForChild("Economy"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HitboxService = require(script.Parent.HitboxService)
local CombatService = require(script.Parent.CombatService)
local StateService = require(script.Parent.StateService)

type AbilityDef = Types.AbilityDef

-- Studio only: every player starts with these in storage, so abilities can be tested
-- without spinning for them. Never runs in the live game.
local STUDIO_STARTER_ABILITIES = { "EmberFist", "PebbleToss", "GaleStep", "FrostJab", "ThunderLance" }

-- Small allowance so a press sent the moment the cooldown ends isn't rejected because of ping.
local LATENCY_ALLOWANCE = 0.2
-- Melee abilities hit at most this many targets.
local MELEE_MAX_TARGETS = 4
-- Where a thrown projectile leaves the hand, from the HumanoidRootPart: right, up, forward (studs).
-- Measured on the Pebble Toss release frame. The server can't use the hand itself: it doesn't
-- run the thrower's animation, so their hand is in its rest pose here.
local THROW_OFFSET = Vector3.new(0.86, 0.47, 3.04)
-- Server-clock projectiles (Thunder Lance) are announced to players this close to where they leave
-- the hand (Vault: Replicating VFX - 250 studs, just beyond the 220-stud client cull).
local LAUNCH_RADIUS = 250
-- Sky strike (Thunder Lance stage 7B): it lands this long after the hit (game seconds; the clients play
-- the same timeline from the server time), on the ground found straight below the target within this.
local STRIKE_DELAY = 0.15
local STRIKE_GROUND_DROP = 20
local seeds = Random.new()

local AbilityService = {}

local defsById: { [string]: AbilityDef } = {}
for _, def in Abilities do
	defsById[def.Id] = def
end

-- [player][abilityId] = server clock when it can be used again
local readyAt: { [Player]: { [string]: number } } = {}
-- [player][abilityId] = server clock of the last request (MinRequestSeconds), accepted or not
local lastRequest: { [Player]: { [string]: number } } = {}
-- [player] = the dash being watched (a newer dash replaces it)
local dashWatches: { [Player]: RBXScriptConnection } = {}
local abilityUsed: RemoteEvent
local abilityHit: RemoteEvent
local abilityImpact: RemoteEvent
local abilityLaunch: RemoteEvent
local abilityStrike: RemoteEvent

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
	-- An exact box when the ability sets a height (Frost Jab), else the older taller box.
	-- Each target is in the list once, so it's hit at most once per cast.
	local targets = if def.HitboxHeight
		then HitboxService.InBox(character, root, aim, def.HitboxWidth or 5, def.HitboxHeight, def.Range, MELEE_MAX_TARGETS)
		else HitboxService.InFront(character, root, aim, def.Range, def.HitboxWidth or 5, MELEE_MAX_TARGETS)
	local impacts: { { Target: Model, Position: Vector3 } } = {}
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
		local model = target.Parent
		if model and model:IsA("Model") then
			if def.SlowMultiplier and def.SlowSeconds then
				StateService.ApplySlow(model, def.SlowMultiplier, def.SlowSeconds)
			end
			if targetRoot then
				table.insert(impacts, { Target = model, Position = targetRoot.Position })
			end
		end
	end
	-- Every client plays the on-hit VFX (the attacker played the startup VFX on its own already).
	-- Only server-owned characters and positions are sent, plus the server time of the hit, so a
	-- client that gets this late skips effects that have already finished.
	if #impacts > 0 then
		abilityImpact:FireAllClients(character, def.Id, impacts, workspace:GetServerTimeNow())
	end
end

-- Flies a projectile in a straight line, one Projectile.Step every frame (a big hitbox sphere for
-- characters, a small one the size of the projectile for walls and the ground). The first thing it
-- touches is the hit: damage (characters only). Every client then plays the impact (AbilityHit),
-- also when it flies its full range without touching anything (it shatters in the air there).
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
	local hitboxRadius = def.HitboxRadius or 0.5
	local bodyRadius = def.ProjectileRadius or 0.5
	local filters = Projectile.Filters(character)

	-- First sweep: from the chest to the hand, so a target standing right in front still gets hit.
	local position = chest
	local travelled = -(hand - chest).Magnitude
	local step = hand - chest
	local hit: Projectile.Hit? = nil
	while true do
		hit = Projectile.Step(position, step, hitboxRadius, bodyRadius, filters)
		if hit then
			break
		end
		position += step
		travelled += step.Magnitude
		if travelled >= def.Range then
			break
		end
		local dt = RunService.Heartbeat:Wait()
		step = flat * math.min(speed * dt, def.Range - travelled)
	end

	if hit then
		local target = hit.Humanoid
		if target and target.Health > 0 then
			local power = Rarities.Defs[def.Rarity].Power
			local knockback = flat * (def.Knockback or 0) + Vector3.new(0, (def.Knockback or 0) * 0.4, 0)
			CombatService.DealDamage(player, target, def.Damage * power, knockback, def.Id)
		end
		abilityHit:FireAllClients(character, def.Id, hit.Position, hit.Normal)
	else
		abilityHit:FireAllClients(character, def.Id, position, -flat) -- end of its range
	end
end

export type ClockShot = {
	Hit: boolean, -- it touched something (a character or the world) before its full range
	Position: Vector3, -- where it stopped
	Target: Model?, -- the character hit, if any
	Travelled: number, -- studs from the origin
}

-- A projectile flown on the SERVER CLOCK (Thunder Lance). Its front is at
--     origin + direction * speed * (now - start)        (closed form: no drift, any frame rate)
-- and every Heartbeat sweeps from where it was to there with Projectile.Step (the big HitboxRadius
-- sphere finds characters, the small ProjectileRadius one walls and the ground; the thrower and their
-- accessories are never hit). Before that, one sweep from the thrower's eyes to the spear's tip, so a
-- target or a wall between them is hit first (no throwing through a wall you're hugging).
-- There is no server-side part. The other clients get AbilityLaunch (origin, direction, start, seed)
-- and draw their own spear from it; the thrower's client drew its own on the Release marker.
-- The first thing it touches is the hit: damage once (characters only), then AbilityHit to everyone
-- with the exact point, the target, the server time and the seed (so every client draws the same
-- impact bolts). At full range it just fades out: no AbilityHit. A character hit by a SkyStrike
-- ability also gets AbilityStrike right after (skyStrike).
-- A character hit by a SkyStrike projectile: a lightning strike comes down on it from the sky. The
-- server only decides where (the ground straight below the target's root, or the target itself if
-- there's no ground within STRIKE_GROUND_DROP) and tells everyone at once, so a target that dies,
-- resets or leaves before the strike lands still gets it at that spot. Damage (StrikeDamage, final,
-- no rarity Power) lands STRIKE_DELAY later, only if set above 0 and the target is still alive.
local function skyStrike(player: Player, character: Model, def: AbilityDef, target: Humanoid, filters: Projectile.Filters)
	local model = target.Parent :: Model
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if root then root.Position else model:GetPivot().Position
	local ground = workspace:Raycast(from, Vector3.new(0, -STRIKE_GROUND_DROP, 0), filters.World)
	local groundPos = if ground then ground.Position else from
	abilityStrike:FireAllClients(character, def.Id, model, groundPos, workspace:GetServerTimeNow(), seeds:NextInteger(1, 2147483646))
	local damage = def.StrikeDamage or 0
	if damage > 0 then
		task.delay(STRIKE_DELAY, function()
			if target.Parent and target.Health > 0 then
				CombatService.DealDamage(player, target, damage, Vector3.zero, def.Id)
			end
		end)
	end
end

-- override (Studio QA hook only): fly from a given origin / direction, without the wind-up.
local function useClockProjectile(player: Player, character: Model, root: BasePart, def: AbilityDef, aim: Vector3,
	override: { Origin: Vector3, Direction: Vector3 }?): ClockShot?
	if not override then
		task.wait(def.WindupSeconds or 0)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not root.Parent then
		return nil
	end

	local flat = if override then override.Direction.Unit else Vector3.new(aim.X, 0, aim.Z).Unit
	local right = flat:Cross(Vector3.yAxis)
	local offset = def.ThrowOffset or THROW_OFFSET
	local hand = root.Position + right * offset.X + Vector3.yAxis * offset.Y + flat * offset.Z
	local origin = if override then override.Origin else hand + flat * (def.ProjectileLead or 0)
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local speed = def.ProjectileSpeed or 80
	local hitboxRadius = def.HitboxRadius or 0.5
	local bodyRadius = def.ProjectileRadius or 0.5
	local filters = Projectile.Filters(character)
	local seed = seeds:NextInteger(1, 2147483646)
	local start = workspace:GetServerTimeNow()

	for _, other in Players:GetPlayers() do
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if other ~= player and otherRoot and (otherRoot.Position - origin).Magnitude <= LAUNCH_RADIUS + def.Range then
			abilityLaunch:FireClient(other, character, def.Id, origin, flat, start, seed)
		end
	end

	local hit = if override then nil else Projectile.Step(eye, origin - eye, hitboxRadius, bodyRadius, filters)
	local last = origin
	local travelled = 0
	while not hit do
		travelled = math.min(speed * (workspace:GetServerTimeNow() - start), def.Range)
		local now = origin + flat * travelled
		hit = Projectile.Step(last, now - last, hitboxRadius, bodyRadius, filters)
		last = now
		if hit or travelled >= def.Range then
			break
		end
		RunService.Heartbeat:Wait()
	end

	if not hit then
		return { Hit = false, Position = last, Target = nil, Travelled = travelled }
	end
	local target = hit.Humanoid
	local model = target and target.Parent :: Model?
	if target and target.Health > 0 then
		local power = Rarities.Defs[def.Rarity].Power
		local knockback = flat * (def.Knockback or 0) + Vector3.new(0, (def.Knockback or 0) * 0.4, 0)
		CombatService.DealDamage(player, target, def.Damage * power, knockback, def.Id)
	end
	abilityHit:FireAllClients(character, def.Id, hit.Position, hit.Normal, model, workspace:GetServerTimeNow(), seed)
	if def.SkyStrike and target then
		skyStrike(player, character, def, target, filters) -- characters only: never a wall, the floor or full range
	end
	return { Hit = true, Position = hit.Position, Target = model, Travelled = (hit.Position - origin).Magnitude }
end

-- Dashes are moved by the dashing player's own client (smooth on their screen). The server only
-- watches: for `seconds` after the press, the character may move at most maxStuds sideways from
-- where it was. Further than that, it's pulled back onto that circle and stopped there.
local function watchDash(player: Player, root: BasePart, maxStuds: number, seconds: number)
	local previous = dashWatches[player]
	if previous then
		previous:Disconnect()
	end
	local start = root.Position
	local endsAt = os.clock() + seconds
	local watch: RBXScriptConnection
	watch = RunService.Heartbeat:Connect(function()
		if os.clock() > endsAt or not root.Parent then
			watch:Disconnect()
			if dashWatches[player] == watch then
				dashWatches[player] = nil
			end
			return
		end
		local moved = root.Position - start
		local flat = Vector3.new(moved.X, 0, moved.Z)
		if flat.Magnitude > maxStuds then
			local allowed = start + flat.Unit * maxStuds
			local rotation = root.CFrame - root.Position
			root.CFrame = rotation + Vector3.new(allowed.X, root.Position.Y, allowed.Z)
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end
	end)
	dashWatches[player] = watch
end

-- The dash itself already happened on the player's client; check it stays within MaxDashStuds.
local function useDash(player: Player, root: BasePart, def: AbilityDef)
	watchDash(player, root, def.MaxDashStuds or def.Range + 2, def.DashWindowSeconds or 1)
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

	-- Per-ability request limit (on top of RemoteGuard's shared one): every request counts, even rejected ones.
	local now = os.clock()
	if def.MinRequestSeconds then
		local requests = lastRequest[player]
		if not requests then
			requests = {}
			lastRequest[player] = requests
		end
		local last = requests[def.Id]
		requests[def.Id] = now
		if last and now - last < def.MinRequestSeconds then
			return
		end
	end

	-- Cooldown on the server clock.
	local perPlayer = readyAt[player]
	if not perPlayer then
		perPlayer = {}
		readyAt[player] = perPlayer
	end
	if now < (perPlayer[def.Id] or 0) - LATENCY_ALLOWANCE then
		if def.Type == "Movement" then
			-- Still on cooldown: no dash allowed. Its client may have dashed anyway (a cheat, or a
			-- clock that drifted); only normal walking is let through.
			watchDash(player, root, humanoid.WalkSpeed * (def.DashWindowSeconds or 1) + 2, def.DashWindowSeconds or 1)
		end
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
	elseif def.Type == "Projectile" and def.ServerClock then
		useClockProjectile(player, character, root, def, aim)
	elseif def.Type == "Projectile" then
		useProjectile(player, character, root, def, aim)
	elseif def.Type == "Movement" then
		useDash(player, root, def)
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
	abilityImpact = Remotes.Event("AbilityImpact")
	abilityLaunch = Remotes.Event("AbilityLaunch")
	abilityStrike = Remotes.Event("AbilityStrike")
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

		-- Studio-only QA hook (Frost Jab stage 7: a second hit inside the slow, which the 3 s cooldown
		-- never allows from one player). A server-side BindableFunction, never a remote, never in the
		-- live game: Invoke("Melee", player, abilityId) runs the real melee path (hitbox, damage,
		-- slow, AbilityImpact) once, skipping only the cooldown and request checks.
		-- Thunder Lance stage 7: Invoke("Projectile", player, abilityId, origin, direction) flies the real
		-- server-clock projectile (sweeps, damage, AbilityLaunch / AbilityHit) from an exact origin and
		-- direction, and returns where it stopped and what it hit (a 2-stud pass vs a 3-stud miss, walls).
		local hook = Instance.new("BindableFunction")
		hook.Name = "AbilityTestHook"
		hook.OnInvoke = function(action: string, player: Player, abilityId: string, origin: Vector3?, direction: Vector3?): any
			local def = defsById[abilityId]
			local character = player and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not def or not character or not root then
				return false
			end
			if action == "Projectile" and def.ServerClock and origin and direction then
				return useClockProjectile(player, character, root, def, direction, { Origin = origin, Direction = direction })
			end
			if action ~= "Melee" or def.Type ~= "Melee" then
				return false
			end
			local look = root.CFrame.LookVector
			task.spawn(useMelee, player, character, root, def, Vector3.new(look.X, 0, look.Z).Unit)
			return true
		end
		hook.Parent = game:GetService("ServerStorage"):FindFirstChild("Dev") or game:GetService("ServerStorage")
	end

	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		lastRequest[player] = nil
		local watch = dashWatches[player]
		if watch then
			watch:Disconnect()
			dashWatches[player] = nil
		end
	end)
end

return AbilityService
