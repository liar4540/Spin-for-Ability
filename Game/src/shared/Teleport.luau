--!strict
-- Teleport: who a lock-on teleport (Shadow Swap) picks and where it lands. The server uses it for the
-- real move and the caster's client to predict it the same frame, so both agree on the target.
--   Nearest   the closest living fighter (players + training dummies, CollectionService tag "Fighter")
--             within `range` studs of the caster's root, never the caster
--   Behind    a spot `studs` behind the target (opposite its facing), pulled in if a wall is in the way,
--             at the target's height, facing the target

local CollectionService = game:GetService("CollectionService")

local FIGHTER_TAG = "Fighter"
local WALL_GAP = 1.5 -- studs kept from a wall that is closer than `studs` behind the target
local MIN_BEHIND = 1 -- never closer to the target than this

local Teleport = {}

local function rootOf(model: Instance): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Teleport.Nearest(caster: Model, range: number): Model?
	local root = rootOf(caster)
	if not root then
		return nil
	end
	local best: Model? = nil
	local bestDistance = range
	for _, model in CollectionService:GetTagged(FIGHTER_TAG) do
		if model == caster or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local targetRoot = rootOf(model)
		if not humanoid or humanoid.Health <= 0 or not targetRoot then
			continue
		end
		local distance = (targetRoot.Position - root.Position).Magnitude
		if distance <= bestDistance then
			best = model
			bestDistance = distance
		end
	end
	return best
end

-- Where to land behind `target` (a CFrame for the caster's HumanoidRootPart), or nil if it has no root.
function Teleport.Behind(caster: Model, target: Model, studs: number): CFrame?
	local targetRoot = rootOf(target)
	if not targetRoot then
		return nil
	end
	local look = targetRoot.CFrame.LookVector
	local back = -Vector3.new(look.X, 0, look.Z)
	back = if back.Magnitude > 0.01 then back.Unit else Vector3.new(0, 0, 1)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { caster }
	for _, model in CollectionService:GetTagged(FIGHTER_TAG) do
		table.insert(ignore, model)
	end
	local clientVfx = workspace:FindFirstChild("ClientVFX")
	if clientVfx then
		table.insert(ignore, clientVfx)
	end
	params.FilterDescendantsInstances = ignore

	local distance = studs
	local wall = workspace:Raycast(targetRoot.Position, back * (studs + WALL_GAP), params)
	if wall then
		distance = math.max(MIN_BEHIND, wall.Distance - WALL_GAP)
	end
	local spot = targetRoot.Position + back * distance
	local face = Vector3.new(targetRoot.Position.X, spot.Y, targetRoot.Position.Z)
	return CFrame.lookAt(spot, face)
end

return Teleport
