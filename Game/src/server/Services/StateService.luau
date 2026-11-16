--!strict
-- StateService: one combat state per fighter (players + training dummies), with timers.
-- Vault: 12 Combat System → Fighter states.
--
-- Rules:
--  * Timers are timestamps (state.until = now + seconds), never wait(). A new hit overwrites them.
--  * One Heartbeat loop expires timers, regenerates guard and tracks control time for everyone.
--  * The state is mirrored to the character as the attribute "CombatState" so clients and UI can read it.
--  * Every attack/cast gets an action id. Being stunned, ragdolled, guard broken, dying or respawning
--    cancels it, so a scheduled hit from an interrupted swing never lands (IsActionCurrent).
--
-- Damage invulnerability (i-frames, spawn shield) and stun immunity are separate things:
--   HasIFrames      → the hit does nothing at all
--   IsStunImmune    → the hit deals damage but can't stun / ragdoll

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))

export type State =
	"Idle"
	| "Attacking"
	| "Casting"
	| "Dashing"
	| "Blocking"
	| "Stunned"
	| "Airborne"
	| "Ragdolled"
	| "GuardBroken"
	| "EndLag"

export type Action = "M1" | "Block" | "Dash" | "Ability"

-- What each state allows. Every input is checked here first (plus the timers in Can()).
local ALLOWS: { [State]: { M1: boolean, Block: boolean, Dash: boolean, Ability: boolean } } = {
	Idle = { M1 = true, Block = true, Dash = true, Ability = true },
	-- Next hit of the string. Dash cancels the swing's startup; abilities only after the hit frame.
	Attacking = { M1 = true, Block = false, Dash = true, Ability = true },
	-- Using an ability: committed until its recovery ends.
	Casting = { M1 = false, Block = false, Dash = false, Ability = false },
	-- Front dash → side dash cancel, dash → M1 / ability follow-ups.
	Dashing = { M1 = true, Block = false, Dash = true, Ability = true },
	EndLag = { M1 = false, Block = true, Dash = true, Ability = true }, -- combo extension window
	Blocking = { M1 = false, Block = true, Dash = false, Ability = false },
	Stunned = { M1 = false, Block = false, Dash = false, Ability = false },
	Airborne = { M1 = true, Block = false, Dash = false, Ability = true }, -- AirUsable abilities only (AbilityService)
	Ragdolled = { M1 = false, Block = false, Dash = false, Ability = false }, -- ragdoll cancel has its own remote
	GuardBroken = { M1 = false, Block = false, Dash = false, Ability = false },
}

-- States where someone else is in control of you (counted for the anti-infinite control cap).
local CONTROLLED: { [string]: boolean } = { Stunned = true, Ragdolled = true, GuardBroken = true }
-- No jumping in these (PDF: stunned players can't jump; blocking can't jump).
local NO_JUMP: { [string]: boolean } = { Stunned = true, Ragdolled = true, GuardBroken = true, Blocking = true }

type ActionInfo = { id: number, kind: string, startupEnd: number }

export type Fighter = {
	model: Model,
	humanoid: Humanoid,
	player: Player?,
	state: State,
	stateEnd: number, -- 0 = no timer
	stunImmuneUntil: number,
	iFramesUntil: number,
	spawnShieldUntil: number,
	m1LockedUntil: number, -- finisher end lag survives dashing / abilities
	action: ActionInfo?,
	-- Anti-infinite: when the current stretch of being controlled started (0 = free).
	controlStart: number,
	freeSince: number,
	controlCapped: boolean,
	-- Block / guard meter.
	guard: number,
	lastBlockedAt: number,
	blockStartedAt: number,
	blockDisabledUntil: number,
	-- Ragdoll.
	ragdollStartedAt: number,
	ragdollCancellable: boolean,
	-- Combo this fighter is RECEIVING. usedAbilities[attackerKey .. abilityId] = cast id.
	combo: { hits: number, lastHitAt: number, usedAbilities: { [string]: number } },
	defaultJumpPower: number,
	defaultJumpHeight: number,
	label: BillboardGui?,
	connections: { RBXScriptConnection },
}

type StateListener = (model: Model, old: State, new: State) -> ()

local StateService = {}

local fighters: { [Model]: Fighter } = {}
local listeners: { StateListener } = {}
local removedListeners: { (model: Model) -> () } = {}
local addedListeners: { (model: Model) -> () } = {}
local nextActionId = 0

-- Ragdoll cancel cooldown per player, so dying / respawning doesn't reset it.
local ragdollCancelReadyAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end
StateService.Now = now

local function applyMovement(f: Fighter)
	local speed = Combat.NormalWalkSpeed
	if f.state == "Stunned" then
		speed = Combat.M1.StunnedWalkSpeed
	elseif f.state == "Blocking" then
		speed = Combat.Block.WalkSpeed
	elseif f.state == "Ragdolled" or f.state == "GuardBroken" then
		speed = 0
	end
	f.humanoid.WalkSpeed = speed
	local noJump = NO_JUMP[f.state] == true
	f.humanoid.JumpPower = if noJump then 0 else f.defaultJumpPower
	f.humanoid.JumpHeight = if noJump then 0 else f.defaultJumpHeight
end

local function updateLabel(f: Fighter)
	local label = f.label
	if label then
		local text = label:FindFirstChild("Text") :: TextLabel?
		if text then
			local extra = if f.controlCapped then " (cap)" else ""
			text.Text = `{f.state}{extra}`
		end
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
	gui.Size = UDim2.fromOffset(140, 24)
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

-- ===== States =====

-- Set a state. seconds = nil means "until something else changes it".
function StateService.Set(model: Model, state: State, seconds: number?)
	local f = fighters[model]
	if not f then
		return
	end
	local old = f.state
	local t = now()
	f.state = state
	f.stateEnd = if seconds then t + seconds else 0

	if CONTROLLED[state] then
		-- Being controlled interrupts whatever you were doing (scheduled hits are cancelled).
		f.action = nil
		if f.controlStart == 0 then
			f.controlStart = t
		end
		f.freeSince = 0
	end
	if state ~= "Blocking" then
		f.blockStartedAt = 0
	end
	if old == "Ragdolled" and state ~= "Ragdolled" then
		f.ragdollCancellable = false
		model:SetAttribute("RagdollCancellable", false)
		if not CONTROLLED[state] then
			-- Standing up from a ragdoll: short stun immunity (not damage invulnerability).
			f.stunImmuneUntil = math.max(f.stunImmuneUntil, t + Combat.StunImmunityAfterRagdoll)
		end
	end

	model:SetAttribute("CombatState", state)
	applyMovement(f)
	updateLabel(f)
	if old ~= state then
		for _, listener in listeners do
			task.spawn(listener, model, old, state)
		end
	end
end

-- Called with (model, oldState, newState) on every state change (RagdollService listens).
function StateService.OnStateChanged(listener: StateListener)
	table.insert(listeners, listener)
end

-- Called when a new fighter is registered (character spawned, dummy added).
-- Also called right away for every fighter that already exists.
function StateService.OnAdded(listener: (model: Model) -> ())
	table.insert(addedListeners, listener)
	for model in fighters do
		task.spawn(listener, model)
	end
end

-- Called when a fighter stops existing (died, removed, respawned).
function StateService.OnRemoved(listener: (model: Model) -> ())
	table.insert(removedListeners, listener)
end

function StateService.Get(model: Model): Fighter?
	return fighters[model]
end

function StateService.GetState(model: Model): State?
	local f = fighters[model]
	return f and f.state
end

function StateService.IsControlled(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and CONTROLLED[f.state] == true
end

function StateService.Can(model: Model, action: Action): boolean
	local f = fighters[model]
	if not f or f.humanoid.Health <= 0 then
		return false
	end
	if not ALLOWS[f.state][action] then
		return false
	end
	local t = now()
	if action == "M1" then
		return t >= f.m1LockedUntil
	elseif action == "Block" then
		return t >= f.blockDisabledUntil
	elseif action == "Ability" then
		-- Not during an attack's startup: the swing must resolve before an ability starts on top of it.
		local a = f.action
		return not (a and f.state == "Attacking" and t < a.startupEnd)
	end
	return true
end

-- ===== Actions (attack ids) =====

-- Start an attack / cast. Returns its id. Any older action of this fighter is replaced (cancelled).
function StateService.BeginAction(model: Model, kind: string, startup: number): number
	nextActionId += 1
	local f = fighters[model]
	if f then
		f.action = { id = nextActionId, kind = kind, startupEnd = now() + startup }
		f.spawnShieldUntil = 0 -- attacking ends spawn protection
	end
	return nextActionId
end

-- Is this action still the fighter's current, uninterrupted one (and the fighter alive)?
function StateService.IsActionCurrent(model: Model, id: number): boolean
	local f = fighters[model]
	return f ~= nil and f.action ~= nil and (f.action :: ActionInfo).id == id and f.humanoid.Health > 0
end

function StateService.CurrentAction(model: Model): (string?, number?)
	local f = fighters[model]
	local a = f and f.action
	if not a then
		return nil, nil
	end
	return a.kind, a.id
end

-- Is the current action still before its hit frame?
function StateService.InStartup(model: Model): boolean
	local f = fighters[model]
	local a = f and f.action
	return a ~= nil and now() < a.startupEnd
end

function StateService.CancelAction(model: Model)
	local f = fighters[model]
	if f then
		f.action = nil
	end
end

-- Finisher end lag: no M1 until then, whatever state the fighter goes through meanwhile.
function StateService.LockM1(model: Model, seconds: number)
	local f = fighters[model]
	if f then
		f.m1LockedUntil = math.max(f.m1LockedUntil, now() + seconds)
	end
end

function StateService.M1LockedFor(model: Model): number
	local f = fighters[model]
	return if f then math.max(0, f.m1LockedUntil - now()) else 0
end

-- ===== Immunity =====

function StateService.IsStunImmune(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and now() < f.stunImmuneUntil
end

function StateService.GiveStunImmunity(model: Model, seconds: number)
	local f = fighters[model]
	if f then
		f.stunImmuneUntil = math.max(f.stunImmuneUntil, now() + seconds)
	end
end

-- Damage invulnerability: dash / ragdoll-cancel i-frames and spawn protection.
function StateService.HasIFrames(model: Model): boolean
	local f = fighters[model]
	if not f then
		return false
	end
	local t = now()
	return t < f.iFramesUntil or t < f.spawnShieldUntil
end

function StateService.GiveIFrames(model: Model, seconds: number)
	local f = fighters[model]
	if f and seconds > 0 then
		f.iFramesUntil = math.max(f.iFramesUntil, now() + seconds)
	end
end

-- True once this fighter has been controlled for longer than MaxControlSeconds without a break.
-- Hits then deal damage but can't stun or ragdoll (CombatService).
function StateService.IsControlCapped(model: Model): boolean
	local f = fighters[model]
	if not f or f.controlStart == 0 then
		return false
	end
	return now() - f.controlStart >= Combat.ComboExtension.MaxControlSeconds
end

-- How much longer this fighter may still be controlled before the cap.
function StateService.ControlLeft(model: Model): number
	local f = fighters[model]
	if not f or f.controlStart == 0 then
		return Combat.ComboExtension.MaxControlSeconds
	end
	return math.max(0, Combat.ComboExtension.MaxControlSeconds - (now() - f.controlStart))
end

-- ===== Combo tracking (on the target) =====

local function comboExpired(f: Fighter, t: number): boolean
	return t - f.combo.lastHitAt > Combat.ComboExtension.ComboDropSeconds
end

-- Count a hit in the combo on this target. Returns the damage multiplier for this hit (scaling).
function StateService.RegisterComboHit(model: Model): number
	local f = fighters[model]
	if not f then
		return 1
	end
	local t = now()
	local cfg = Combat.ComboExtension
	if comboExpired(f, t) then
		f.combo.hits = 0
		table.clear(f.combo.usedAbilities)
	end
	f.combo.hits += 1
	f.combo.lastHitAt = t
	model:SetAttribute("ComboHits", f.combo.hits) -- dummies' combo counter / debugging
	local over = f.combo.hits - cfg.ScalingStartsAfterHit
	if over <= 0 then
		return 1
	end
	return math.max(cfg.ScalingMin, 1 - over * cfg.ScalingPerHit)
end

function StateService.ComboHits(model: Model): number
	local f = fighters[model]
	if not f or comboExpired(f, now()) then
		return 0
	end
	return f.combo.hits
end

-- Once per combo: may this cast of this ability hit this target? `key` = attacker key .. abilityId.
-- Every hit of the cast that was first used in this combo is fine (multi-hit abilities);
-- a NEW cast of the same ability in the same combo is not.
function StateService.AbilityAllowedInCombo(model: Model, key: string, castId: number?): boolean
	local f = fighters[model]
	if not f or not Combat.ComboExtension.OncePerCombo then
		return true
	end
	if comboExpired(f, now()) then
		return true
	end
	local used = f.combo.usedAbilities[key]
	return used == nil or (castId ~= nil and used == castId)
end

function StateService.MarkAbilityUsed(model: Model, key: string, castId: number)
	local f = fighters[model]
	if f and f.combo.usedAbilities[key] == nil then
		f.combo.usedAbilities[key] = castId
	end
end

-- ===== Block / guard =====

function StateService.SetGuard(model: Model, guard: number)
	local f = fighters[model]
	if f then
		f.guard = math.clamp(guard, 0, Combat.Block.GuardPoints)
		model:SetAttribute("Guard", f.guard)
	end
end

-- ===== Ragdoll cancel bookkeeping =====

function StateService.MarkRagdoll(model: Model, cancellable: boolean)
	local f = fighters[model]
	if f then
		f.ragdollStartedAt = now()
		f.ragdollCancellable = cancellable
		model:SetAttribute("RagdollCancellable", cancellable)
	end
end

function StateService.RagdollCancelReadyAt(player: Player): number
	return ragdollCancelReadyAt[player] or 0
end

function StateService.SetRagdollCancelReadyAt(player: Player, t: number)
	ragdollCancelReadyAt[player] = t
	local character = player.Character
	if character then
		character:SetAttribute("RagdollCancelReadyAt", t)
	end
end

-- ===== Registering fighters =====

-- Fighters (players + dummies) don't collide with each other, like most battlegrounds games:
-- otherwise bodies bump and push the attacker away mid-combo. They still collide with the map.
-- Hits use hitboxes, not touching. (It also stops a ragdoll's own limbs from fighting each other.)
local FIGHTER_GROUP = "Fighters"

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = FIGHTER_GROUP
	end
end

local function unregister(model: Model)
	local f = fighters[model]
	if not f then
		return
	end
	fighters[model] = nil
	f.action = nil
	for _, c in f.connections do
		c:Disconnect()
	end
	for _, listener in removedListeners do
		task.spawn(listener, model)
	end
end

local function register(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or fighters[model] then
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	local t = now()
	local f: Fighter = {
		model = model,
		humanoid = humanoid,
		player = player,
		state = "Idle",
		stateEnd = 0,
		stunImmuneUntil = 0,
		iFramesUntil = 0,
		spawnShieldUntil = if player then t + Combat.Respawn.ShieldSeconds else 0,
		m1LockedUntil = 0,
		action = nil,
		controlStart = 0,
		freeSince = t,
		controlCapped = false,
		guard = Combat.Block.GuardPoints,
		lastBlockedAt = 0,
		blockStartedAt = 0,
		blockDisabledUntil = 0,
		ragdollStartedAt = 0,
		ragdollCancellable = false,
		combo = { hits = 0, lastHitAt = 0, usedAbilities = {} },
		defaultJumpPower = humanoid.JumpPower,
		defaultJumpHeight = humanoid.JumpHeight,
		label = makeLabel(model),
		connections = {},
	}
	fighters[model] = f
	model:SetAttribute("CombatState", "Idle")
	model:SetAttribute("Guard", f.guard)
	model:SetAttribute("RagdollCancellable", false)
	if player then
		model:SetAttribute("RagdollCancelReadyAt", ragdollCancelReadyAt[player] or 0)
		model:SetAttribute("SpawnShieldUntil", f.spawnShieldUntil)
	end
	CollectionService:AddTag(model, "Fighter") -- clients find fighters by this tag (hit reactions)
	for _, listener in addedListeners do
		task.spawn(listener, model)
	end
	for _, part in model:GetDescendants() do
		setGroup(part)
	end
	table.insert(f.connections, model.DescendantAdded:Connect(setGroup)) -- accessories, tools, late parts
	table.insert(
		f.connections,
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				unregister(model)
			end
		end)
	)
	table.insert(
		f.connections,
		humanoid.Died:Connect(function()
			unregister(model)
		end)
	)
end

local function onTimerEnd(f: Fighter)
	if f.state == "Blocking" then
		return -- blocking has no timer; kept for safety
	end
	StateService.Set(f.model, "Idle")
end

local function step(dt: number)
	local t = now()
	local cfg = Combat.ComboExtension
	local block = Combat.Block
	for _, f in fighters do
		if f.stateEnd > 0 and t >= f.stateEnd then
			onTimerEnd(f)
		end

		-- Anti-infinite control clock.
		if CONTROLLED[f.state] then
			if not f.controlCapped and f.controlStart > 0 and t - f.controlStart >= cfg.MaxControlSeconds then
				f.controlCapped = true
				updateLabel(f)
			end
		else
			if f.freeSince == 0 then
				f.freeSince = t
				if f.controlCapped then
					-- Hit the cap: a guaranteed window to act once control ends.
					f.stunImmuneUntil = math.max(f.stunImmuneUntil, t + cfg.ControlBreakImmunity)
				end
			end
			if f.controlStart > 0 and t - f.freeSince >= cfg.ControlResetSeconds then
				f.controlStart = 0
				if f.controlCapped then
					f.controlCapped = false
					updateLabel(f)
				end
			end
		end

		-- Guard regeneration: RegenPerSecond while not blocking, starting RegenDelay after the last blocked hit.
		if f.guard < block.GuardPoints and f.state ~= "Blocking" and t - f.lastBlockedAt >= block.RegenDelay then
			local before = math.floor(f.guard)
			f.guard = math.min(block.GuardPoints, f.guard + block.RegenPerSecond * dt)
			if math.floor(f.guard) ~= before or f.guard >= block.GuardPoints then
				f.model:SetAttribute("Guard", math.floor(f.guard))
			end
		end
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
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		ragdollCancelReadyAt[player] = nil
		local character = player.Character
		if character then
			unregister(character)
		end
	end)

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

	RunService.Heartbeat:Connect(step)
end

return StateService
