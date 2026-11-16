--!strict
-- RagdollService: real R15 physics ragdoll (vault: 12 Combat System → Finishers; PDF → Ragdoll).
--
-- * Built once per character (BallSocketConstraint per Motor6D, with limits), only switched on/off.
-- * Driven by StateService: entering "Ragdolled" switches it on, leaving it switches it off. Nothing
--   else calls Enable/Disable, so the ragdoll and the combat state can't disagree.
-- * Network ownership: while ragdolled the SERVER owns every body part (the victim's client can't
--   move itself out, and the server applies the knockback). On stand-up ownership goes back to the
--   player, only if the character is alive and the player is still here.
-- * The Root joint (HumanoidRootPart ↔ LowerTorso) stays a Motor6D, so the root follows the body and
--   the camera follows the fall. The root doesn't collide while ragdolled; the limbs do.
-- * Stand-up puts the body upright on the ground under it; if that spot is inside a wall it walks
--   back towards where the ragdoll started. Every part's velocity is zeroed (no fling).
-- * Rigs without Motor6Ds (e.g. future joint types) fall back to the KnockedDown animation
--   (attribute PhysicsRagdoll stays false and ReactionController plays the loop instead).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Knockback = require(Shared:WaitForChild("Knockback"))

local StateService = require(script.Parent:WaitForChild("StateService"))

type Rig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	motors: { Motor6D },
	sockets: { BallSocketConstraint },
	collide: { [BasePart]: boolean }, -- CanCollide before the ragdoll
	active: boolean,
	startPosition: Vector3,
}

local RagdollService = {}

local rigs: { [Model]: Rig } = {}
local ROTATE_X_TO_Y = CFrame.fromAxisAngle(Vector3.zAxis, math.rad(90)) -- twist axis along the limb

local function build(model: Model): Rig?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local motors: { Motor6D } = {}
	local sockets: { BallSocketConstraint } = {}
	local limits = Combat.Ragdoll.Limits :: { [string]: { number } }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "Root" and d.Part0 and d.Part1 then
			local motor = d :: Motor6D
			local part0 = motor.Part0 :: BasePart
			local part1 = motor.Part1 :: BasePart
			local a0 = Instance.new("Attachment")
			a0.Name = `RagdollA0_{motor.Name}`
			a0.CFrame = motor.C0 * ROTATE_X_TO_Y
			a0.Parent = part0
			local a1 = Instance.new("Attachment")
			a1.Name = `RagdollA1_{motor.Name}`
			a1.CFrame = motor.C1 * ROTATE_X_TO_Y
			a1.Parent = part1
			local limit = limits[motor.Name] or Combat.Ragdoll.DefaultLimit
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = `RagdollSocket_{motor.Name}`
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = limit[1]
			socket.TwistLowerAngle = limit[2]
			socket.TwistUpperAngle = limit[3]
			socket.Enabled = false
			socket.Parent = part1
			table.insert(motors, motor)
			table.insert(sockets, socket)
		end
	end
	if #motors == 0 then
		return nil
	end
	-- Switching the Neck motor off would otherwise kill the character.
	humanoid.RequiresNeck = false
	local rig: Rig = {
		model = model,
		humanoid = humanoid,
		root = root,
		motors = motors,
		sockets = sockets,
		collide = {},
		active = false,
		startPosition = root.Position,
	}
	return rig
end

local function rigFor(model: Model): Rig?
	if not Combat.Ragdoll.UsePhysics then
		return nil
	end
	local rig = rigs[model]
	if rig and rig.root.Parent then
		return rig
	end
	local built = build(model)
	if built then
		rigs[model] = built
	end
	return built
end

-- Every body part that can take ownership (each limb is its own assembly while ragdolled).
local function setOwner(model: Model, owner: Player?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			local ok = part:CanSetNetworkOwnership()
			if ok then
				pcall(part.SetNetworkOwner, part, owner)
			end
		end
	end
end

local function zeroVelocity(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function standParams(model: Model): (RaycastParams, OverlapParams)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { model }
	ray.CollisionGroup = "Fighters" -- ignores every fighter, hits the map
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { model }
	overlap.CollisionGroup = "Fighters"
	overlap.RespectCanCollide = true
	return ray, overlap
end

-- Upright CFrame for the root at (or near) where the body lies.
local function standUpCFrame(rig: Rig): CFrame
	local root = rig.root
	local ray, overlap = standParams(rig.model)
	local standOffset = rig.humanoid.HipHeight + root.Size.Y / 2

	-- Face where the body's front points along the ground (lying on the back, that's the head side).
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.2 then
		local up = root.CFrame.UpVector
		flat = Vector3.new(up.X, 0, up.Z)
	end
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)

	local lying = root.Position
	local tries = math.max(1, Combat.Ragdoll.StandUpTries)
	for i = 0, tries do
		local guess = lying:Lerp(rig.startPosition, i / tries)
		local hit = workspace:Raycast(guess + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), ray)
		local position = if hit then hit.Position + Vector3.new(0, standOffset, 0) else guess
		local blocked = workspace:GetPartBoundsInBox(
			CFrame.new(position + Vector3.new(0, 0.5, 0)),
			Vector3.new(1.6, standOffset * 2 - 0.4, 0.8),
			overlap
		)
		if #blocked == 0 then
			return CFrame.lookAt(position, position + flat)
		end
	end
	return CFrame.lookAt(rig.startPosition, rig.startPosition + flat)
end

-- Switch the ragdoll on. Returns false if this rig can't physics-ragdoll (animation fallback).
local function enable(model: Model): boolean
	local rig = rigFor(model)
	if not rig then
		model:SetAttribute("PhysicsRagdoll", false)
		return false
	end
	if rig.active then
		return true
	end
	rig.active = true
	rig.startPosition = rig.root.Position
	Knockback.Release(rig.root) -- stop any server-side push (dummies)

	local humanoid = rig.humanoid
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	table.clear(rig.collide)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			rig.collide[part] = part.CanCollide
			part.CanCollide = part ~= rig.root
		end
	end
	for _, socket in rig.sockets do
		socket.Enabled = true
	end
	for _, motor in rig.motors do
		motor.Enabled = false
	end
	setOwner(model, nil)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	model:SetAttribute("PhysicsRagdoll", true)
	return true
end

local function disable(model: Model)
	local rig = rigs[model]
	if not rig or not rig.active then
		return
	end
	rig.active = false
	model:SetAttribute("PhysicsRagdoll", false)
	if not rig.root.Parent then
		return -- character already gone
	end

	for _, motor in rig.motors do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	for _, socket in rig.sockets do
		socket.Enabled = false
	end
	for part, collide in rig.collide do
		if part.Parent then
			part.CanCollide = collide
		end
	end
	table.clear(rig.collide)

	local humanoid = rig.humanoid
	rig.root.CFrame = standUpCFrame(rig)
	zeroVelocity(model)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)

	local player = Players:GetPlayerFromCharacter(model)
	if player and player.Parent and humanoid.Health > 0 and model:IsDescendantOf(workspace) then
		-- Give the player their character back (they own its physics again).
		if rig.root:CanSetNetworkOwnership() then
			pcall(rig.root.SetNetworkOwner, rig.root, player)
		end
	end
end

-- Give a ragdolled body a one-shot velocity (world space). Capped so nothing gets flung.
function RagdollService.Impulse(model: Model, velocity: Vector3)
	local rig = rigs[model]
	if not rig or not rig.active then
		return
	end
	local cap = Combat.Ragdoll.MaxImpulse
	if velocity.Magnitude > cap then
		velocity = velocity.Unit * cap
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = velocity
		end
	end
end

-- True while this model is in a physics ragdoll (false for the animation fallback).
function RagdollService.IsPhysical(model: Model): boolean
	local rig = rigs[model]
	return rig ~= nil and rig.active
end

function RagdollService.Init() end

function RagdollService.Start()
	StateService.OnStateChanged(function(model, old, new)
		if new == "Ragdolled" then
			enable(model)
		elseif old == "Ragdolled" then
			disable(model)
		end
	end)
	-- Died / removed / respawned: forget the rig. A dead body keeps whatever joints it has.
	StateService.OnRemoved(function(model)
		local rig = rigs[model]
		if rig and rig.active and rig.root.Parent and rig.humanoid.Health > 0 then
			disable(model) -- removed while alive (e.g. taken out of Workspace): put it back together
		end
		rigs[model] = nil
	end)
	-- Build the constraints once, when the fighter appears (not on the first hit).
	StateService.OnAdded(function(model)
		rigFor(model)
	end)
end

return RagdollService
