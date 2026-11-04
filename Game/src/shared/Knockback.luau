--!strict
-- Knockback: pushes a character for a moment. Setting AssemblyLinearVelocity once isn't enough,
-- because the Humanoid's ground control cancels it in a frame or two.
-- Call it where the character's physics is owned: the server for NPCs/dummies, the player's
-- own client for player characters. One LinearVelocity per character, reused for every hit.

local PUSH_SECONDS = 0.18

local Knockback = {}

local pushUntil: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

local function mover(root: BasePart): LinearVelocity
	local existing = root:FindFirstChild("KnockbackVelocity")
	if existing and existing:IsA("LinearVelocity") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "KnockbackVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 1e6
	velocity.Enabled = false
	velocity.Parent = root
	return velocity
end

function Knockback.Apply(root: BasePart, velocity: Vector3)
	local push = mover(root)
	push.VectorVelocity = velocity
	push.Enabled = true
	local untilTime = os.clock() + PUSH_SECONDS
	pushUntil[root] = untilTime
	task.delay(PUSH_SECONDS, function()
		if pushUntil[root] == untilTime then
			push.Enabled = false
		end
	end)
end

return Knockback
