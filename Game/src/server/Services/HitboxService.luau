--!strict
-- HitboxService: spatial queries per move + 1 s position history for lag-compensated reach checks.
-- Status: Milestone 1 start. Only the melee box in front of the attacker. Position history
-- (lag compensation) comes with the M1 combo.

local HitboxService = {}

-- Extra reach so a hit that looked fine on a laggy screen still lands.
local LAG_MARGIN = 1.5
local BOX_HEIGHT = 7

-- Every living humanoid whose body touches a box in front of rootPart, facing along aim.
-- Never returns the attacker's own humanoid. Returns at most maxTargets.
function HitboxService.InFront(attacker: Model, rootPart: BasePart, aim: Vector3, range: number, width: number, maxTargets: number): { Humanoid }
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 0.01 then
		flat = rootPart.CFrame.LookVector
	end
	flat = flat.Unit

	local length = range + LAG_MARGIN
	local center = rootPart.Position + flat * (length / 2)
	local boxCFrame = CFrame.lookAt(center, center + flat)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }

	local found: { Humanoid } = {}
	local seen: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(width, BOX_HEIGHT, length), params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and not seen[humanoid] and humanoid.Health > 0 then
			seen[humanoid] = true
			table.insert(found, humanoid)
			if #found >= maxTargets then
				break
			end
		end
	end
	return found
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function HitboxService.Init() end

-- Called once after every Init(). Connect events, start loops.
function HitboxService.Start() end

return HitboxService
