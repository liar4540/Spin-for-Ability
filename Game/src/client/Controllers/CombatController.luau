--!strict
-- CombatController: M1 / block / dash input (100–200 ms input buffer), instant local animation + VFX, mobile combat buttons, soft targeting.
-- Status: M1 string with finishers (Knockback, Ground Smash, Downslam in the air), knockback, and a
-- short flash on whoever gets hit. Block and dash input come next (vault: 12 Combat System).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))
local Combat = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))

local Client = script.Parent.Parent
local Pose = require(Client:WaitForChild("Abilities"):WaitForChild("Pose"))
local CombatKeyframes = require(Client:WaitForChild("Animations"):WaitForChild("CombatKeyframes"))

local HIT_FLASH_SECONDS = 0.15
local HIT_FLASH_COLOR = Color3.fromRGB(255, 170, 60)

local UserInputService = game:GetService("UserInputService")

local CombatController = {}

local m1Remote: RemoteEvent

-- One Highlight per hit model, reused for every hit.
local flashes: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any

local function flash(model: Model)
	local highlight = flashes[model]
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.FillColor = HIT_FLASH_COLOR
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		flashes[model] = highlight
	end
	local h = highlight :: Highlight
	h.FillTransparency = 0.35
	h.OutlineTransparency = 0
	h.Enabled = true
	task.delay(HIT_FLASH_SECONDS, function()
		h.Enabled = false
	end)
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function CombatController.Init() end

-- M1 input. The server decides everything; this sends the click and plays the swing right away.
-- Hits 1–3, then hit 4 = finisher: in the air (jump first) → Downslam, S held → Ground Smash,
-- otherwise Knockback. So the Downslam is M1 ×3, jump, M1.
local LOCAL_M1_INTERVAL = 0.3 -- matches Combat.M1.MinInterval so we don't spam the remote
local lastM1 = 0

-- Predicted with the server's rules (CombatService.onM1) so the swing animates instantly instead of
-- waiting a round trip.
local chainIndex = 0

local playing: AnimationTrack? = nil
local playToken = 0
local ANIMATION_IDS = Combat.Animation.Ids :: { [string]: string }

-- Plays one combat move with a short crossfade from whatever was playing, and blends its last
-- moments back into idle so the pose never snaps.
local function playMove(character: Model, name: string)
	local move = CombatKeyframes[name]
	if not move then
		return
	end
	local cfg = Combat.Animation
	local track = Pose.Track(character, name, move.Keyframes, ANIMATION_IDS[name])
	if not track then
		return
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
end

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

local buffered = false

local function onM1()
	local now = os.clock()
	local wait = LOCAL_M1_INTERVAL - (now - lastM1)
	if wait > 0 then
		-- Clicked a little early: throw it the moment it's allowed instead of ignoring it.
		if wait <= Combat.M1.InputBuffer and not buffered then
			buffered = true
			task.delay(wait, function()
				buffered = false
				onM1()
			end)
		end
		return
	end
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local state = character:GetAttribute("CombatState")
	if state ~= nil and state ~= "Idle" and state ~= "Attacking" then
		return
	end

	local cfg = Combat.M1
	-- Hit 4 gets a longer window (time to jump for the Downslam).
	local window = if chainIndex == cfg.ChainLength - 1 then cfg.FinisherWindow else cfg.ChainResetSeconds
	local dropped = now - lastM1 > window
	if dropped and chainIndex > 0 and chainIndex < cfg.ChainLength and now - lastM1 < cfg.RestartDelay then
		return -- same rule as the server: a dropped string can't restart right away
	end
	if dropped or chainIndex >= cfg.ChainLength then
		chainIndex = 0
	end
	chainIndex += 1
	lastM1 = now

	local finisher = "None"
	if chainIndex < cfg.ChainLength then
		playMove(character, `M1_{chainIndex}`)
		if root then
			Knockback.Step(root, root.CFrame.LookVector, cfg.ForwardStep, cfg.ForwardStepSeconds)
		end
	elseif inAir(character) and root and (heightAboveStanding(character, root) >= Combat.Downslam.MinHeight
		or root.AssemblyLinearVelocity.Y > 0) then
		-- High enough, or still rising from the jump (it will be by the hit). Landing and too low
		-- → normal Knockback, the same thing the server will decide.
		finisher = "Air"
		playMove(character, "Downslam")
		local d = Combat.Downslam
		-- Hang through the wind-up once high enough; right after take-off let the jump keep rising.
		if root and heightAboveStanding(character, root) >= d.MinHeight then
			Knockback.Apply(root, Vector3.zero, 0, { Seconds = d.HangSeconds, FallSpeed = d.HangFallSpeed })
		end
	else
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			finisher = "S"
		end
		playMove(character, "M1_4")
	end

	local camera = workspace.CurrentCamera
	m1Remote:FireServer(camera.CFrame.LookVector, finisher)
end

local function onCharacter(_character: Model)
	chainIndex = 0
end

-- Called once after every Init(). Connect events, start loops.
function CombatController.Start()
	m1Remote = Remotes.Event("M1Attack")
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onM1()
		end
	end)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	-- Our client owns our character's physics, so the server asks us to apply knockback,
	-- launches and air-combo hang time.
	Remotes.Event("Knockback").OnClientEvent:Connect(function(velocity: Vector3, seconds: number?, hangSeconds: number?)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or typeof(velocity) ~= "Vector3" then
			return
		end
		local hover = if type(hangSeconds) == "number" then { Seconds = hangSeconds, FallSpeed = Combat.HangFallSpeed } else nil
		Knockback.Apply(root, velocity, if type(seconds) == "number" then seconds else nil, hover)
	end)

	Remotes.Event("HitEffect").OnClientEvent:Connect(function(model: Model, _abilityId: string, _position: Vector3)
		if model and model.Parent then
			flash(model)
		end
	end)
end

return CombatController
