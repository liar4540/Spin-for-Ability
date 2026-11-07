--!strict
-- ReactionController: hit-reaction animations on every fighter (players and training dummies).
-- The server sets two attributes on whoever gets hit (CombatService.ApplyHit):
--   Reaction    = "Stun" | "Air" | "Down"
--   ReactionHit = counter, +1 per hit (so a repeat hit with the same reaction still fires)
-- and the fighter's CombatState (Stunned / Ragdolled). Every client plays the reaction locally:
--   Stun → "Stunned" dazed loop + a "Flinch" jolt on each hit
--   Air  → "Launched" loop (face to the sky, limbs dangling) while hanging after an Uppercut
--   Down → "KnockedDown" loop (flat on the back) after a Downslam / ragdoll
-- When CombatState leaves Stunned/Ragdolled the loop fades out, which reads as getting up.
-- Keyframes: client/Animations/CombatKeyframes (made in Blender, assets/animations/_src).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))

local Client = script.Parent.Parent
local Pose = require(Client:WaitForChild("Abilities"):WaitForChild("Pose"))
local CombatKeyframes = require(Client:WaitForChild("Animations"):WaitForChild("CombatKeyframes"))

local LOOP_FOR: { [string]: string } = { Stun = "Stunned", Air = "Launched", Down = "KnockedDown" }
local REACTING_STATES: { [string]: boolean } = { Stunned = true, Ragdolled = true }
local ANIMATION_IDS = Combat.Animation.Ids :: { [string]: string }

type Active = { name: string, track: AnimationTrack }

local ReactionController = {}

local active: { [Model]: Active } = setmetatable({}, { __mode = "k" }) :: any
local flinchTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function track(model: Model, name: string): AnimationTrack?
	local move = CombatKeyframes[name]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not move or not humanoid then
		return nil
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		-- Some Studio-made dummies have no Animator. A local one is enough to play on this client.
		Instance.new("Animator").Parent = humanoid
	end
	return Pose.Track(model, name, move.Keyframes, ANIMATION_IDS[name])
end

local function stop(model: Model)
	local current = active[model]
	if current then
		current.track:Stop(Combat.Animation.ReactionFadeOut)
		active[model] = nil
	end
end

local function flinch(model: Model)
	local move = CombatKeyframes.Flinch
	local t = track(model, "Flinch")
	if not move or not t then
		return
	end
	t.Priority = Enum.AnimationPriority.Action3 -- on top of the dazed loop
	t.Looped = false
	t:Play(0.03)
	local token = (flinchTokens[model] or 0) + 1
	flinchTokens[model] = token
	local blendOut = Combat.Animation.BlendOut
	task.delay(math.max(0, move.Length - blendOut), function()
		if flinchTokens[model] == token and t.IsPlaying then
			t:Stop(blendOut)
		end
	end)
end

local function onHit(model: Model)
	local state = model:GetAttribute("CombatState")
	local reaction = model:GetAttribute("Reaction")
	local loopName = if type(reaction) == "string" then LOOP_FOR[reaction] else nil
	if not loopName or type(state) ~= "string" or not REACTING_STATES[state] then
		return
	end

	local current = active[model]
	if not current or current.name ~= loopName then
		if current then
			current.track:Stop(Combat.Animation.ReactionFadeIn)
		end
		local t = track(model, loopName)
		if not t then
			return
		end
		-- Above Action, so getting hit cuts off the fighter's own punch pose.
		t.Priority = Enum.AnimationPriority.Action2
		t.Looped = true
		t:Play(Combat.Animation.ReactionFadeIn)
		active[model] = { name = loopName, track = t }
	end
	if reaction == "Stun" then
		flinch(model)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance
	model:GetAttributeChangedSignal("ReactionHit"):Connect(function()
		onHit(model)
	end)
	model:GetAttributeChangedSignal("CombatState"):Connect(function()
		local state = model:GetAttribute("CombatState")
		if type(state) ~= "string" or not REACTING_STATES[state] then
			stop(model)
		end
	end)
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function ReactionController.Init() end

-- Called once after every Init(). Connect events, start loops.
function ReactionController.Start()
	for _, model in CollectionService:GetTagged("Fighter") do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal("Fighter"):Connect(watch)
end

return ReactionController
