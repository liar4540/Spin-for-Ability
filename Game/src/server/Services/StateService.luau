--!strict
-- StateService: one combat state per fighter (players + training dummies), with timers.
-- Build-order step 1 (vault: 12 Combat System).
--
-- Rules:
--  * Timers are timestamps (state.until = now + seconds), never wait(). A new hit overwrites them.
--  * One Heartbeat loop expires timers for everyone, instead of one thread per hit.
--  * The state is mirrored to the character as the attribute "CombatState" so clients and UI can read it.
--  * Slows (ApplySlow) are a status next to the state: WalkSpeed is worked out in ONE place
--    (applyWalkSpeed) from the state and the slow, mirrored as SlowMultiplier / SlowEndsAt.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))

export type State = "Idle" | "Attacking" | "Blocking" | "Stunned" | "Airborne" | "Ragdolled" | "GuardBroken" | "EndLag"

-- What each state allows. Every input is checked here first.
local ALLOWS: { [State]: { M1: boolean, Block: boolean, Dash: boolean, Ability: boolean } } = {
	Idle = { M1 = true, Block = true, Dash = true, Ability = true },
	Attacking = { M1 = true, Block = false, Dash = true, Ability = true },
	EndLag = { M1 = false, Block = true, Dash = true, Ability = true }, -- combo extension window
	Blocking = { M1 = false, Block = true, Dash = false, Ability = false },
	Stunned = { M1 = false, Block = false, Dash = false, Ability = false },
	Airborne = { M1 = true, Block = false, Dash = false, Ability = true }, -- AirUsable abilities only (checked by AbilityService)
	Ragdolled = { M1 = false, Block = false, Dash = false, Ability = false },
	GuardBroken = { M1 = false, Block = false, Dash = false, Ability = false },
}

export type Fighter = {
	model: Model,
	humanoid: Humanoid,
	state: State,
	stateEnd: number, -- 0 = no timer
	stunImmuneUntil: number,
	iFramesUntil: number,
	slowMultiplier: number, -- WalkSpeed multiplier while slowed (1 = not slowed)
	slowEndsAt: number, -- 0 = not slowed
	combo: { hits: number, lastHitAt: number, usedAbilities: { [string]: boolean } }, -- combo this fighter is RECEIVING
	label: BillboardGui?,
}

local StateService = {}

local fighters: { [Model]: Fighter } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function applyWalkSpeed(f: Fighter)
	local speed = Combat.NormalWalkSpeed
	if f.state == "Stunned" then
		speed = Combat.M1.StunnedWalkSpeed
	elseif f.state == "Blocking" then
		speed = Combat.Block.WalkSpeed
	elseif f.state == "Ragdolled" or f.state == "GuardBroken" then
		speed = 0
	end
	if f.slowEndsAt > 0 then
		speed *= f.slowMultiplier
	end
	f.humanoid.WalkSpeed = speed
end

-- Slow status, mirrored to the model as attributes SlowMultiplier / SlowEndsAt (server time) so
-- clients and UI can read it. Cleared here only: when it runs out, the fighter dies, or is removed.
local function setSlow(f: Fighter, multiplier: number, endsAt: number)
	f.slowMultiplier = multiplier
	f.slowEndsAt = endsAt
	f.model:SetAttribute("SlowMultiplier", if endsAt > 0 then multiplier else nil)
	f.model:SetAttribute("SlowEndsAt", if endsAt > 0 then endsAt else nil)
	applyWalkSpeed(f)
end

local function updateLabel(f: Fighter)
	local label = f.label
	if label then
		(label:FindFirstChild("Text") :: TextLabel).Text = f.state
	end
end

local function makeLabel(model: Model): BillboardGui?
	if not (Combat.DebugStateLabels and RunService:IsStudio()) then
		return nil
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CombatStateDebug"
	gui.Size = UDim2.fromOffset(120, 24)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 0)
	text.TextStrokeTransparency = 0
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = "Idle"
	text.Parent = gui
	gui.Parent = head
	return gui
end

-- Set a state. seconds = nil means "until something else changes it".
function StateService.Set(model: Model, state: State, seconds: number?)
	local f = fighters[model]
	if not f then
		return
	end
	f.state = state
	f.stateEnd = if seconds then now() + seconds else 0
	model:SetAttribute("CombatState", state)
	applyWalkSpeed(f)
	updateLabel(f)
end

function StateService.Get(model: Model): Fighter?
	return fighters[model]
end

function StateService.GetState(model: Model): State?
	local f = fighters[model]
	return f and f.state
end

-- action: "M1" | "Block" | "Dash" | "Ability"
function StateService.Can(model: Model, action: "M1" | "Block" | "Dash" | "Ability"): boolean
	local f = fighters[model]
	if not f or f.humanoid.Health <= 0 then
		return false
	end
	return ALLOWS[f.state][action]
end

function StateService.IsStunImmune(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and now() < f.stunImmuneUntil
end

function StateService.HasIFrames(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and now() < f.iFramesUntil
end

function StateService.GiveIFrames(model: Model, seconds: number)
	local f = fighters[model]
	if f then
		f.iFramesUntil = math.max(f.iFramesUntil, now() + seconds)
	end
end

-- Combo tracking on the target. Returns the damage multiplier for this hit (scaling).
function StateService.RegisterComboHit(model: Model): number
	local f = fighters[model]
	if not f then
		return 1
	end
	local t = now()
	local cfg = Combat.ComboExtension
	if t - f.combo.lastHitAt > cfg.ComboDropSeconds then
		f.combo.hits = 0
		table.clear(f.combo.usedAbilities)
	end
	f.combo.hits += 1
	f.combo.lastHitAt = t
	local over = f.combo.hits - cfg.ScalingStartsAfterHit
	if over <= 0 then
		return 1
	end
	return math.max(cfg.ScalingMin, 1 - over * cfg.ScalingPerHit)
end

-- True if this ability was already used in the combo on this target (abilities are once per combo).
function StateService.AbilityUsedInCombo(model: Model, abilityId: string): boolean
	local f = fighters[model]
	if not f or not Combat.ComboExtension.OncePerCombo then
		return false
	end
	if now() - f.combo.lastHitAt > Combat.ComboExtension.ComboDropSeconds then
		return false
	end
	return f.combo.usedAbilities[abilityId] == true
end

function StateService.MarkAbilityUsed(model: Model, abilityId: string)
	local f = fighters[model]
	if f then
		f.combo.usedAbilities[abilityId] = true
	end
end

-- Fighters (players + dummies) don't collide with each other, like most battlegrounds games:
-- otherwise bodies bump and push the attacker away mid-combo (worst in the air after an Uppercut).
-- They still collide with the map. Hits use hitboxes, not touching.
local FIGHTER_GROUP = "Fighters"

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = FIGHTER_GROUP
	end
end

-- Slow a fighter: WalkSpeed x multiplier for `seconds`. Never stacks: a new slow refreshes the timer
-- (and keeps the stronger multiplier if one is already running). Returns false if model isn't a fighter.
function StateService.ApplySlow(model: Model, multiplier: number, seconds: number): boolean
	local f = fighters[model]
	if not f or f.humanoid.Health <= 0 then
		return false
	end
	local t = now()
	local active = f.slowEndsAt > t
	setSlow(f, if active then math.min(f.slowMultiplier, multiplier) else multiplier, math.max(if active then f.slowEndsAt else 0, t + seconds))
	return true
end

local function register(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or fighters[model] then
		return
	end
	local f: Fighter = {
		model = model,
		humanoid = humanoid,
		state = "Idle",
		stateEnd = 0,
		stunImmuneUntil = 0,
		iFramesUntil = 0,
		slowMultiplier = 1,
		slowEndsAt = 0,
		combo = { hits = 0, lastHitAt = 0, usedAbilities = {} },
		label = makeLabel(model),
	}
	fighters[model] = f
	model:SetAttribute("CombatState", "Idle")
	CollectionService:AddTag(model, "Fighter") -- clients find fighters by this tag (hit reactions)
	for _, part in model:GetDescendants() do
		setGroup(part)
	end
	model.DescendantAdded:Connect(setGroup) -- accessories, tools, late-loading parts
	-- A slow never outlives its fighter: dying or being removed (reset, leaving) clears it.
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if f.slowEndsAt > 0 then
				setSlow(f, 1, 0)
			end
			fighters[model] = nil
		end
	end)
	humanoid.Died:Connect(function()
		if f.slowEndsAt > 0 then
			setSlow(f, 1, 0)
		end
		fighters[model] = nil
	end)
end

local function onTimerEnd(f: Fighter)
	local was = f.state
	StateService.Set(f.model, "Idle")
	if was == "Ragdolled" then
		f.stunImmuneUntil = now() + Combat.StunImmunityAfterRagdoll
	end
end

function StateService.Init()
	PhysicsService:RegisterCollisionGroup(FIGHTER_GROUP)
	PhysicsService:CollisionGroupSetCollidable(FIGHTER_GROUP, FIGHTER_GROUP, false)
end

function StateService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			register(character)
		end)
		if player.Character then
			register(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end

	for _, model in CollectionService:GetTagged("TrainingDummy") do
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			register(model)
		end
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(function(model)
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			register(model)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local t = now()
		for _, f in fighters do
			if f.stateEnd > 0 and t >= f.stateEnd then
				onTimerEnd(f)
			end
			if f.slowEndsAt > 0 and t >= f.slowEndsAt then
				setSlow(f, 1, 0)
			end
		end
	end)
end

return StateService
