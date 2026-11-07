--!strict
-- HitboxService: spatial queries per move + 1 s position history for lag-compensated reach checks.
-- Status: Milestone 1 start. Only the melee box in front of the attacker. Position history
-- (lag compensation) comes with the M1 combo.

local HitboxService = {}

-- Extra reach so a hit that looked fine on a laggy screen still lands.
local LAG_MARGIN = 1.5
local BOX_HEIGHT = 7

-- The box: starts at the root, `length` studs long toward aim (flattened), centred on the root's
-- height, moved down by `down` studs.
local function boxInFront(rootPart: BasePart, aim: Vector3, length: number, down: number?): CFrame
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 0.01 then
		flat = rootPart.CFrame.LookVector
	end
	flat = flat.Unit
	local center = rootPart.Position + flat * (length / 2) - Vector3.new(0, down or 0, 0)
	return CFrame.lookAt(center, center + flat)
end

-- Every living humanoid whose body touches a box in front of rootPart, facing along aim.
-- Never returns the attacker's own humanoid. Returns at most maxTargets.
-- height: box height in studs, centred on rootPart (default 7), moved down by `down`.
function HitboxService.InFront(
	attacker: Model,
	rootPart: BasePart,
	aim: Vector3,
	range: number,
	width: number,
	maxTargets: number,
	height: number?,
	down: number? -- shift the box this many studs down (e.g. a Downslam from a jump)
): { Humanoid }
	local length = range + LAG_MARGIN
	return HitboxService.Query(
		attacker,
		boxInFront(rootPart, aim, length, down),
		Vector3.new(width, height or BOX_HEIGHT, length),
		maxTargets
	)
end

-- Same, with an exact width x height box: `length` studs from the root (+ the lag margin).
function HitboxService.InBox(attacker: Model, rootPart: BasePart, aim: Vector3, width: number, height: number, length: number, maxTargets: number): { Humanoid }
	local total = length + LAG_MARGIN
	return HitboxService.Query(attacker, boxInFront(rootPart, aim, total), Vector3.new(width, height, total), maxTargets)
end

-- Every living humanoid (each once) whose body touches the box, never the attacker's own.
function HitboxService.Query(attacker: Model, boxCFrame: CFrame, size: Vector3, maxTargets: number): { Humanoid }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }

	local found: { Humanoid } = {}
	local seen: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, params) do
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