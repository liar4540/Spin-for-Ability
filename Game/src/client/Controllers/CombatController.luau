--!strict
-- CombatController: M1 / block / dash / ragdoll-cancel input, instant local animation, prediction +
-- reconciliation with the server, hit feedback, mobile combat buttons.
-- Vault: 12 Combat System. The server decides every hit; this only predicts so it feels instant.
--
-- M1 prediction: the swing animates the moment you click, using the same chain rules as the server
-- (CombatService.onM1). Every swing has a sequence number; the server answers each one
-- (CombatResult "M1"). If it was rejected, the animation is cut and the chain goes back to the
-- server's hit, so the client never stays on the wrong hit of the string.
-- Controls: M1 = click / tap button · F (hold) = block · Q = dash (direction from movement) ·
-- Q while ragdolled = ragdoll cancel · S + M1 on hit 4 = Ground Smash · jump + M1 on hit 4 = Downslam.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))
local Combat = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local Client = script.Parent.Parent
local Pose = require(Client:WaitForChild("Abilities"):WaitForChild("Pose"))
local CombatKeyframes = require(Client:WaitForChild("Animations"):WaitForChild("CombatKeyframes"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local HIT_FLASH_SECONDS = 0.15
-- Abilities whose own on-hit VFX already marks the target (and whose palette has no orange).
local OWN_HIT_FLASH: { [string]: boolean } = {
	FrostJab = true, -- frost coat (FrostJabVFX)
	ThunderLance = true, -- electric arcs on the target (ThunderLanceVFX)
}
local FLASH_COLORS: { [string]: Color3 } = {
	Hit = Color3.fromRGB(255, 170, 60),
	Blocked = Color3.fromRGB(90, 170, 255),
	GuardBreak = Color3.fromRGB(220, 240, 255),
	Escape = Color3.fromRGB(200, 230, 255),
}
local HEAVY_HITS: { [string]: boolean } = { M1_4 = true, M1_Downslam = true, M1_GroundSmash = true }
local LAG_MARGIN = 1.5 -- same as HitboxService, for the local hit prediction
local PREDICTED_FLASH_SECONDS = 0.5 -- the server's echo of a hit we already flashed is skipped

local CombatController = {}

local player = Players.LocalPlayer
local m1Remote: RemoteEvent
local blockRemote: RemoteEvent
local dashRemote: RemoteEvent
local ragdollCancelRemote: RemoteEvent

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	return if model then model:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.zero
end

local function myState(): string?
	local character = player.Character
	local state = character and character:GetAttribute("CombatState")
	return if type(state) == "string" then state else nil
end

-- ===== Hit flash + camera shake =====

-- One Highlight per hit model, reused for every hit.
local flashes: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any
local flashTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local predictedAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function flash(model: Model, kind: string)
	local highlight = flashes[model]
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		flashes[model] = highlight
	end
	local h = highlight :: Highlight
	h.FillColor = FLASH_COLORS[kind] or FLASH_COLORS.Hit
	h.FillTransparency = 0.35
	h.OutlineTransparency = 0
	h.Enabled = true
	local token = (flashTokens[model] or 0) + 1
	flashTokens[model] = token
	task.delay(HIT_FLASH_SECONDS, function()
		if flashTokens[model] == token then
			h.Enabled = false
		end
	end)
end

local shakeUntil = 0
local shakeStrength = 0
local function shake(strength: number, seconds: number)
	shakeStrength = math.max(if os.clock() < shakeUntil then shakeStrength else 0, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

-- ===== Animation =====

local playing: AnimationTrack? = nil
local playToken = 0
local ANIMATION_IDS = Combat.Animation.Ids :: { [string]: string }

-- Plays one combat move with a short crossfade from whatever was playing, and blends its last
-- moments back into idle so the pose never snaps.
local function playMove(character: Model, name: string): AnimationTrack?
	local move = CombatKeyframes[name]
	if not move then
		return nil
	end
	local cfg = Combat.Animation
	local track = Pose.Track(character, name, move.Keyframes, ANIMATION_IDS[name])
	if not track then
		return nil
	end
	local previous = playing
	if previous and previous ~= track and previous.IsPlaying then
		previous:Stop(cfg.FadeIn)
	end
	playing = track
	playToken += 1
	local token = playToken
	track:Play(cfg.FadeIn)
	task.delay(math.max(0, move.Length - cfg.BlendOut), function()
		if playToken == token and track.IsPlaying then
			track:Stop(cfg.BlendOut)
		end
	end)
	return track
end

-- Cut the current swing (rejected by the server, interrupted, dash-cancelled).
local function cancelSwingAnimation(track: AnimationTrack?)
	local current = playing
	if current and (track == nil or current == track) and current.IsPlaying then
		current:Stop(Combat.Animation.CancelFade)
		playToken += 1
		playing = nil
	end
end

-- ===== Local hit prediction =====

-- How far the root is above its normal standing height (fighters ignored, same rule as the server).
local function heightAboveStanding(character: Model, root: BasePart): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.CollisionGroup = "Fighters"
	local result = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), params)
	local height = if result then root.Position.Y - result.Position.Y else math.huge
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return height - ((if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2)
end

local function inAir(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
end

type Box = { Size: Vector3, Offset: number, Down: number? }

-- Same box as the server's (HitboxService.InFront + CombatService.closestTarget), on what this
-- client sees. Only used for feedback timing (whiff recovery, an instant flash), never for damage.
local function predictTarget(character: Model, root: BasePart, aim: Vector3, box: Box): Model?
	local dir = flat(aim)
	if dir == Vector3.zero then
		dir = flat(root.CFrame.LookVector)
	end
	local length = box.Offset + box.Size.Z / 2 + LAG_MARGIN
	local center = root.Position + dir * (length / 2) - Vector3.new(0, box.Down or 0, 0)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local best: Model? = nil
	local bestDistance = math.huge
	for _, part in workspace:GetPartBoundsInBox(CFrame.lookAt(center, center + dir), Vector3.new(box.Size.X, box.Size.Y, length), params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local r = rootOf(model)
		if
			model
			and humanoid
			and r
			and humanoid.Health > 0
			and CollectionService:HasTag(model, "Fighter")
			and model:GetAttribute("CombatState") ~= "Ragdolled"
		then
			local d = (r.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	return best
end

-- ===== M1 =====

type Swing = {
	seq: number,
	index: number,
	at: number, -- server time of the click
	track: AnimationTrack?,
	-- Chain before this swing, to roll back to if the server rejects it.
	prevIndex: number,
	prevLastM1: number,
	prevNextAllowed: number,
	prevLock: number,
}

local seq = 0
local swings: { [number]: Swing } = {}
local chainIndex = 0
local lastM1 = -math.huge -- server time of the last swing
local nextAllowed = 0 -- server time the next swing may start
local m1LockedUntil = 0 -- finisher end lag (server time)
local buffered = false

local function resetChain()
	chainIndex = 0
	lastM1 = -math.huge
	nextAllowed = 0
	buffered = false
	table.clear(swings)
end

local M1_STATES: { [string]: boolean } = { Idle = true, Attacking = true, Dashing = true }

local function onM1()
	local now = serverNow()
	local cfg = Combat.M1
	local allowedAt = math.max(nextAllowed, m1LockedUntil)
	local wait = allowedAt - now
	if wait > 0 then
		-- Clicked a little early: throw it the moment it's allowed. Only one click is ever kept.
		if wait <= cfg.InputBuffer and not buffered then
			buffered = true
			task.delay(wait, function()
				if buffered then
					buffered = false
					onM1()
				end
			end)
		end
		return
	end
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local state = myState()
	if state ~= nil and not M1_STATES[state] then
		return
	end

	-- Same chain rules as the server.
	local window = if chainIndex == cfg.ChainLength - 1 then cfg.FinisherWindow else cfg.ChainResetSeconds
	local dropped = now - lastM1 > window
	if dropped and chainIndex > 0 and chainIndex < cfg.ChainLength and now - lastM1 < cfg.RestartDelay then
		return -- a dropped string can't restart right away (no swing animation either)
	end
	local swing: Swing = {
		seq = 0,
		index = 0,
		at = now,
		track = nil,
		prevIndex = chainIndex,
		prevLastM1 = lastM1,
		prevNextAllowed = nextAllowed,
		prevLock = m1LockedUntil,
	}
	if dropped or chainIndex >= cfg.ChainLength then
		chainIndex = 0
	end
	chainIndex += 1
	lastM1 = now
	nextAllowed = now + cfg.MinInterval

	-- Punch where the camera looks: turn the body to it (our client owns our physics).
	local camera = workspace.CurrentCamera
	local aim = flat(camera.CFrame.LookVector)
	if aim == Vector3.zero then
		aim = flat(root.CFrame.LookVector)
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)

	local finisher = "None"
	local moveName = `M1_{chainIndex}`
	local box: Box = cfg.Hitbox
	if chainIndex < cfg.ChainLength then
		swing.track = playMove(character, moveName)
		Knockback.Step(root, aim, cfg.ForwardStep, cfg.ForwardStepSeconds)
	elseif inAir(character) and (heightAboveStanding(character, root) >= Combat.Downslam.MinHeight or root.AssemblyLinearVelocity.Y > 0) then
		-- High enough, or still rising from the jump (it will be by the hit). Landing and too low
		-- → normal Knockback, the same thing the server will decide.
		finisher = "Air"
		moveName = "Downslam"
		box = Combat.Downslam.Hitbox
		swing.track = playMove(character, "Downslam")
		local d = Combat.Downslam
		-- Hang through the wind-up once high enough; right after take-off let the jump keep rising.
		if heightAboveStanding(character, root) >= d.MinHeight then
			Knockback.Apply(root, Vector3.zero, 0, { Seconds = d.HangSeconds, FallSpeed = d.HangFallSpeed })
		end
	else
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			finisher = "S"
		end
		moveName = "M1_4"
		swing.track = playMove(character, "M1_4")
	end
	if chainIndex == cfg.ChainLength then
		m1LockedUntil = now + cfg.EndLagSeconds
	end

	seq += 1
	swing.seq = seq
	swing.index = chainIndex
	swings[seq] = swing
	swings[seq - 8] = nil -- keep only recent swings
	m1Remote:FireServer(aim, finisher, seq)

	-- At the hit frame: predict a whiff (so the next click waits like the server will) or a hit
	-- (instant flash; the server's own flash for it is skipped).
	local move = cfg.Moves[moveName]
	local thisSeq = seq
	local isFinisher = chainIndex == cfg.ChainLength
	task.delay(move.Startup, function()
		if not swings[thisSeq] or not character.Parent then
			return
		end
		local r = rootOf(character)
		if not r then
			return
		end
		local target = predictTarget(character, r, aim, box)
		if target then
			predictedAt[target] = os.clock()
			flash(target, "Hit")
			shake(if isFinisher then 0.6 else 0.15, if isFinisher then 0.25 else 0.08)
		elseif not isFinisher then
			nextAllowed = math.max(nextAllowed, swing.at + cfg.MinInterval + cfg.WhiffRecovery)
		end
	end)
end

local function onM1Result(seqIn: number, accepted: boolean, index: number, a: any, b: any)
	local swing = swings[seqIn]
	if accepted then
		-- a = finisher name ("" if none), b = m1LockedUntil
		if swing and swing.index ~= index and seqIn == seq then
			chainIndex = index -- the server counted differently (lag): follow it from now on
		end
		if type(b) == "number" then
			m1LockedUntil = math.max(m1LockedUntil, b)
		end
		return
	end
	-- Rejected: a = retryAt, b = m1LockedUntil. Cut the swing and go back to the server's chain.
	if swing then
		cancelSwingAnimation(swing.track)
		local root = rootOf(player.Character)
		if root then
			Knockback.StopStep(root)
		end
		swings[seqIn] = nil
		if seqIn == seq then
			lastM1 = swing.prevLastM1
			m1LockedUntil = swing.prevLock
		end
	end
	if seqIn == seq then
		chainIndex = index
		nextAllowed = math.max(nextAllowed, if type(a) == "number" then a else 0)
		if type(b) == "number" then
			m1LockedUntil = math.max(m1LockedUntil, b)
		end
	end
end

-- ===== Block =====

local blockHeld = false

local function setBlock(down: boolean)
	if blockHeld == down then
		return
	end
	blockHeld = down
	blockRemote:FireServer(down)
end

-- ===== Dash + ragdoll cancel =====

local dashReadyAt: { [string]: number } = {} -- [group] = server time
local dashKind: string? = nil
local dashEndsAt = 0

local function dashConfig(kind: string)
	return if kind == "Front" then Combat.Dash.Front elseif kind == "Back" then Combat.Dash.Back else Combat.Dash.Side
end

-- Direction from movement input relative to the camera (works for keyboard, thumbstick and touch).
local function dashInput(character: Model): (string, Vector3)
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local move = if humanoid then humanoid.MoveDirection else Vector3.zero
	if move.Magnitude < 0.1 then
		return "Front", look
	end
	local forward = move:Dot(look)
	local side = move:Dot(right)
	if math.abs(side) > math.abs(forward) then
		return if side > 0 then "Right" else "Left", if side > 0 then right else -right
	end
	return if forward < 0 then "Back" else "Front", if forward < 0 then -look else look
end

local function tryRagdollCancel(character: Model)
	if character:GetAttribute("RagdollCancellable") ~= true then
		return
	end
	local readyAt = character:GetAttribute("RagdollCancelReadyAt")
	if type(readyAt) == "number" and serverNow() < readyAt then
		return
	end
	ragdollCancelRemote:FireServer()
end

local DASH_STATES: { [string]: boolean } = { Idle = true, Attacking = true, EndLag = true, Dashing = true }

local function onDash()
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local state = myState()
	if state == "Ragdolled" then
		tryRagdollCancel(character)
		return
	end
	if state ~= nil and not DASH_STATES[state] then
		return
	end
	local kind, dir = dashInput(character)
	local cfg = dashConfig(kind)
	local now = serverNow()
	if os.clock() < dashEndsAt then
		-- Mid-dash: only a front → side cancel.
		if not (Combat.Dash.FrontToSideCancel and dashKind == "Front" and (kind == "Left" or kind == "Right")) then
			return
		end
	end
	if now < (dashReadyAt[cfg.Group] or 0) then
		return
	end
	dashReadyAt[cfg.Group] = now + cfg.Cooldown
	dashKind = kind
	dashEndsAt = os.clock() + cfg.Duration

	-- A dash in an M1's startup cancels it (the server does the same).
	local newest = swings[seq]
	local newestMove = newest and Combat.M1.Moves[`M1_{newest.index}`]
	if newest and newestMove and now - newest.at < newestMove.Startup + newestMove.Active then
		cancelSwingAnimation(newest.track)
	end

	-- Stop short of walls.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.CollisionGroup = "Fighters"
	local hit = workspace:Raycast(root.Position, dir * (cfg.Distance + Combat.Dash.WallStop), params)
	local distance = if hit then math.max(0, hit.Distance - Combat.Dash.WallStop) else cfg.Distance
	if distance > 0.5 then
		Knockback.Step(root, dir, distance, cfg.Duration)
	end
	dashRemote:FireServer(kind, dir)
end

local function onDashResult(accepted: boolean, kind: string, readyAt: number)
	local cfg = dashConfig(kind)
	if type(readyAt) == "number" then
		dashReadyAt[cfg.Group] = readyAt
	end
	if not accepted then
		dashEndsAt = 0
		local root = rootOf(player.Character)
		if root then
			Knockback.StopStep(root)
		end
	end
end

-- ===== Own state changes =====

local CONTROLLED: { [string]: boolean } = { Stunned = true, Ragdolled = true, GuardBroken = true }

local function watchOwnCharacter(character: Model)
	resetChain()
	m1LockedUntil = 0
	dashEndsAt = 0
	blockHeld = false
	local previous = character:GetAttribute("CombatState")
	character:GetAttributeChangedSignal("CombatState"):Connect(function()
		local state = character:GetAttribute("CombatState")
		local root = rootOf(character)
		if type(state) == "string" and CONTROLLED[state] then
			-- Interrupted: cut the swing, forget the buffered click, stop any step.
			cancelSwingAnimation(nil)
			buffered = false
			dashEndsAt = 0
			if root then
				Knockback.StopStep(root)
				if state == "Ragdolled" then
					Knockback.Release(root) -- the server owns the body now; drop our own movers
				end
			end
		end
		if previous == "Ragdolled" and state ~= "Ragdolled" then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
		-- Still holding block when free again → block again (it needs its startup again).
		if blockHeld and (state == "Idle" or state == "EndLag") then
			blockRemote:FireServer(true)
		end
		previous = state
	end)
end

-- ===== Mobile buttons =====

local BUTTON_SIZE = 64
local BUTTON_GAP = 10

local function makeButton(parent: Instance, name: string, text: string, order: number, size: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = Theme.Colors.Card
	button.BackgroundTransparency = Theme.PanelTransparency
	Theme.Round(button, UDim.new(0.5, 0))
	Theme.Outline(button)
	local label = Theme.Label(button, text, Theme.Fonts.Title, if size > BUTTON_SIZE then 24 else 18)
	label.Size = UDim2.fromScale(1, 1)
	button.Parent = parent
	return button
end

-- Touch-only devices: M1 / Block / Dash buttons above the ability hotbar (bottom-right).
local function buildMobileButtons()
	if not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatButtons"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(1, -24, 1, -150 - 68 - 16) -- above the hotbar (AbilityController)
	row.Size = UDim2.fromOffset(3 * BUTTON_SIZE + 16 + 2 * BUTTON_GAP, BUTTON_SIZE + 16)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, BUTTON_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local dash = makeButton(row, "Dash", "DASH", 1, BUTTON_SIZE)
	local block = makeButton(row, "Block", "BLOCK", 2, BUTTON_SIZE)
	local m1 = makeButton(row, "M1", "HIT", 3, BUTTON_SIZE + 16)
	m1.Activated:Connect(onM1)
	dash.Activated:Connect(onDash)
	-- Block is held: down on press, up on release.
	block.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setBlock(true)
		end
	end)
	block.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setBlock(false)
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- ===== Setup =====

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function CombatController.Init() end

-- Called once after every Init(). Connect events, start loops.
function CombatController.Start()
	m1Remote = Remotes.Event("M1Attack")
	blockRemote = Remotes.Event("SetBlock")
	dashRemote = Remotes.Event("Dash")
	ragdollCancelRemote = Remotes.Event("RagdollCancel")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onM1()
		elseif input.KeyCode == Enum.KeyCode.F then
			setBlock(true)
		elseif input.KeyCode == Enum.KeyCode.Q then
			onDash()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F then
			setBlock(false)
		end
	end)
	buildMobileButtons()

	player.CharacterAdded:Connect(watchOwnCharacter)
	if player.Character then
		watchOwnCharacter(player.Character)
	end

	Remotes.Event("CombatResult").OnClientEvent:Connect(function(kind: string, ...: any)
		if kind == "M1" then
			local s, accepted, index, a, b = ...
			if type(s) == "number" and type(accepted) == "boolean" and type(index) == "number" then
				onM1Result(s, accepted, index, a, b)
			end
		elseif kind == "M1Whiff" then
			local s, extra = ...
			local swing = swings[s]
			if swing and type(extra) == "number" then
				nextAllowed = math.max(nextAllowed, swing.at + Combat.M1.MinInterval + extra)
			end
		elseif kind == "M1Cancelled" then
			local s = ...
			local swing = swings[s]
			if swing then
				cancelSwingAnimation(swing.track)
			end
		elseif kind == "Dash" then
			local accepted, dashKindIn, readyAt = ...
			if type(accepted) == "boolean" and type(dashKindIn) == "string" then
				onDashResult(accepted, dashKindIn, readyAt)
			end
		end
	end)

	-- Our client owns our character's physics, so the server asks us to apply knockback,
	-- launches, hang time and the ragdoll-cancel back dash.
	Remotes.Event("Knockback").OnClientEvent:Connect(function(velocity: Vector3, seconds: number?, hangSeconds: number?)
		local character = player.Character
		local root = rootOf(character)
		if not root or typeof(velocity) ~= "Vector3" then
			return
		end
		local hover = if type(hangSeconds) == "number" then { Seconds = hangSeconds, FallSpeed = Combat.HangFallSpeed } else nil
		Knockback.Apply(root, velocity, if type(seconds) == "number" then seconds else nil, hover)
	end)

	Remotes.Event("HitEffect").OnClientEvent:Connect(
		function(model: Model, abilityId: string, _position: Vector3, kind: string?, attacker: Model?)
			if not model or not model.Parent then
				return
			end
			local hitKind = if type(kind) == "string" then kind else "Hit"
			local mine = player.Character
			local predicted = predictedAt[model]
			local skip = hitKind == "Hit" and attacker == mine and predicted ~= nil and os.clock() - predicted < PREDICTED_FLASH_SECONDS
			if not skip and not OWN_HIT_FLASH[abilityId] then
				flash(model, hitKind)
			end
			-- Camera shake only when we're involved.
			if mine and (model == mine or attacker == mine) and not skip then
				local heavy = HEAVY_HITS[abilityId] or hitKind == "GuardBreak"
				shake(if heavy then 0.6 else 0.15, if heavy then 0.25 else 0.08)
			end
		end
	)

	RunService:BindToRenderStep("CombatShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		if left <= 0 then
			return
		end
		local camera = workspace.CurrentCamera
		local s = shakeStrength * math.min(1, left / 0.1)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * s), math.rad((math.random() - 0.5) * s), 0)
	end)
end

return CombatController
