--!strict
-- CombatController: M1 / block / dash input (100–200 ms input buffer), instant local animation + VFX, mobile combat buttons, soft targeting.
-- Status: Milestone 1 start. Only the server → client side so far: being knocked back, and a
-- short flash on whoever gets hit. M1, block and dash input come next (vault: 07 Tech Plan, 08 Roadmap).

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

-- M1 input. The server decides everything; this just sends the click.
-- Space held → Uppercut finisher, S held → Ground Smash, otherwise Knockback (only matters on hit 4).
local LOCAL_M1_INTERVAL = 0.3 -- matches Combat.M1.MinInterval so we don't spam the remote
local lastM1 = 0

-- Which hit of the string we're on, predicted with the server's rules (CombatService.onM1) so the
-- swing animates instantly instead of waiting a round trip.
local chainIndex = 0
local playingM1: AnimationTrack? = nil

local function playM1Animation(character: Model, index: number)
	local name = `M1_{index}`
	local move = CombatKeyframes[name]
	if not move then
		return
	end
	local track = Pose.Track(character, name, move.Keyframes, Combat.M1.AnimationIds[index])
	if not track then
		return
	end
	if playingM1 and playingM1 ~= track then
		playingM1:Stop(0.05)
	end
	playingM1 = track
	track:Play(0.05)
end

local function onM1()
	local now = os.clock()
	if now - lastM1 < LOCAL_M1_INTERVAL then
		return
	end
	local character = Players.LocalPlayer.Character
	local state = character and character:GetAttribute("CombatState")
	if state ~= nil and state ~= "Idle" and state ~= "Attacking" and state ~= "Airborne" then
		return
	end
	if now - lastM1 > Combat.M1.ChainResetSeconds or chainIndex >= Combat.M1.ChainLength then
		chainIndex = 0
	end
	chainIndex += 1
	lastM1 = now
	if character then
		playM1Animation(character, chainIndex)
	end
	local finisher = "None"
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		finisher = "Space"
	elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
		finisher = "S"
	end
	local camera = workspace.CurrentCamera
	m1Remote:FireServer(camera.CFrame.LookVector, finisher)
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

	-- Our client owns our character's physics, so the server asks us to apply knockback.
	Remotes.Event("Knockback").OnClientEvent:Connect(function(velocity: Vector3)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Knockback.Apply(root, velocity)
		end
	end)

	Remotes.Event("HitEffect").OnClientEvent:Connect(function(model: Model, _abilityId: string, _position: Vector3)
		if model and model.Parent then
			flash(model)
		end
	end)
end

return CombatController
