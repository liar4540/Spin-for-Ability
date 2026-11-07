--!strict
-- Knockback: moves a character for a moment. Setting AssemblyLinearVelocity once isn't enough,
-- because the Humanoid's ground control cancels it in a frame or two.
-- Call it where the character's physics is owned: the server for NPCs/dummies, the player's
-- own client for player characters.
--
--   Apply(root, velocity, seconds, hover):
--     * velocity ≠ 0: a push (knockback, launch, slam, the flight next to an air-combo target).
--       Replaces whatever was running. Optionally followed by a hover.
--     * velocity = 0 with a hover: "stay up". Never cancels a push that is still running (the
--       hover is queued after it), and only ever extends a running hover, never shortens it.
--     A hover = air-combo hang time: falls slowly at FallSpeed instead of dropping, can drift sideways.
--   Step: the attacker's small forward step on an M1. Eases out and leaves gravity alone.
-- One LinearVelocity per character for pushes/hovers and one for steps, reused for every hit.

local RunService = game:GetService("RunService")

local PUSH_SECONDS = 0.18

export type Hover = { Seconds: number, FallSpeed: number }

type Motion = {
	phase: "push" | "hover",
	hoverUntil: number, -- os.clock() time, hover phase only
	pendingHover: number?, -- seconds of hover to start when the push ends
	fallSpeed: number,
}

local Knockback = {}

local motions: { [BasePart]: Motion } = setmetatable({}, { __mode = "k" }) :: any
local stepTokens: { [BasePart]: {} } = setmetatable({}, { __mode = "k" }) :: any

local function attachmentOf(root: BasePart): Attachment
	local existing = root:FindFirstChild("KnockbackAttachment")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = root
	return attachment
end

local function mover(root: BasePart, name: string): LinearVelocity
	local existing = root:FindFirstChild(name)
	if existing and existing:IsA("LinearVelocity") then
		return existing
	end
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = name
	velocity.Attachment0 = attachmentOf(root)
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 1e6
	velocity.Enabled = false
	velocity.Parent = root
	return velocity
end

local function stopStep(root: BasePart)
	stepTokens[root] = nil
	local step = root:FindFirstChild("StepVelocity")
	if step and step:IsA("LinearVelocity") then
		step.Enabled = false
	end
end

local function finish(root: BasePart, push: LinearVelocity, m: Motion)
	if motions[root] == m then
		push.Enabled = false
		motions[root] = nil
	end
end

local function startHover(root: BasePart, push: LinearVelocity, m: Motion, seconds: number)
	m.phase = "hover"
	m.pendingHover = nil
	m.hoverUntil = os.clock() + seconds
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	push.LineDirection = Vector3.yAxis
	push.LineVelocity = -m.fallSpeed
	push.Enabled = true
	-- Kill leftover upward speed so the hang starts right where the push ended.
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, -m.fallSpeed, v.Z)

	local function check()
		if motions[root] ~= m then
			return
		end
		local left = m.hoverUntil - os.clock()
		if left > 0.01 then
			task.delay(left, check) -- extended meanwhile
		else
			finish(root, push, m)
		end
	end
	task.delay(seconds, check)
end

-- velocity: world space, studs/second. seconds: how long the push lasts (default 0.18).
function Knockback.Apply(root: BasePart, velocity: Vector3, seconds: number?, hover: Hover?)
	stopStep(root)
	local push = mover(root, "KnockbackVelocity")
	local current = motions[root]

	if velocity.Magnitude == 0 then
		if not hover then
			return
		end
		if current and current.phase == "push" then
			current.pendingHover = math.max(current.pendingHover or 0, hover.Seconds)
			current.fallSpeed = hover.FallSpeed
		elseif current then
			current.hoverUntil = math.max(current.hoverUntil, os.clock() + hover.Seconds)
		else
			local m: Motion = { phase = "hover", hoverUntil = 0, fallSpeed = hover.FallSpeed }
			motions[root] = m
			startHover(root, push, m, hover.Seconds)
		end
		return
	end

	local m: Motion = {
		phase = "push",
		hoverUntil = 0,
		pendingHover = if hover then hover.Seconds else nil,
		fallSpeed = if hover then hover.FallSpeed else 0,
	}
	motions[root] = m
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	push.VectorVelocity = velocity
	push.Enabled = true
	task.delay(seconds or PUSH_SECONDS, function()
		if motions[root] ~= m then
			return
		end
		local pending = m.pendingHover
		if pending then
			startHover(root, push, m, pending)
		else
			finish(root, push, m)
		end
	end)
end

-- Ends any push or hover right away (the character falls normally).
function Knockback.Release(root: BasePart)
	motions[root] = nil
	local push = root:FindFirstChild("KnockbackVelocity")
	if push and push:IsA("LinearVelocity") then
		push.Enabled = false
	end
end

-- Smooth forward step: starts at full speed and eases to zero over `seconds`, so the total distance
-- is `distance`. Only moves along the ground plane; gravity and jumping are untouched.
-- Skipped while a push/hover is running (getting hit wins over stepping).
function Knockback.Step(root: BasePart, direction: Vector3, distance: number, seconds: number)
	if motions[root] then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 or seconds <= 0 then
		return
	end
	flat = flat.Unit
	local step = mover(root, "StepVelocity")
	step.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	step.PrimaryTangentAxis = Vector3.xAxis
	step.SecondaryTangentAxis = Vector3.zAxis
	step.MaxForce = 2e4 -- soft, so walls still stop it

	local token = {}
	stepTokens[root] = token
	-- Linear ease-out: v(t) = v0 * (1 - t/T) covers v0 * T / 2, so v0 = 2 * distance / T.
	local v0 = 2 * distance / seconds
	local started = os.clock()
	step.PlaneVelocity = Vector2.new(flat.X, flat.Z) * v0
	step.Enabled = true

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if stepTokens[root] ~= token or not root.Parent then
			connection:Disconnect()
			return
		end
		local alpha = (os.clock() - started) / seconds
		if alpha >= 1 then
			step.Enabled = false
			stepTokens[root] = nil
			connection:Disconnect()
			return
		end
		step.PlaneVelocity = Vector2.new(flat.X, flat.Z) * (v0 * (1 - alpha))
	end)
end

return Knockback
