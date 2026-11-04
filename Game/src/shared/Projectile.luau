--!strict
-- Projectile: one straight-line step of a thrown projectile. The server uses it for real hits and
-- the client for where its own rock stops (and /vfxtest's local hits), so both agree on the spot.
-- Each step sweeps two spheres along the path:
--   hitbox  big (HitboxRadius) and only touches characters: players and training dummies.
--   body    the size of the thing thrown (ProjectileRadius): walls and the ground stop it.
-- The thrower is never hit. Whichever sphere touches first is the hit.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DUMMY_TAG = "TrainingDummy"

export type Hit = {
	Position: Vector3, -- the point touched, on the surface of what was hit
	Normal: Vector3,
	Humanoid: Humanoid?, -- set when a character was hit
}

export type Filters = { Characters: RaycastParams, World: RaycastParams }

local Projectile = {}

-- Who can be hit, decided once per throw (a flight lasts about a second).
function Projectile.Filters(thrower: Model): Filters
	local characters: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character ~= thrower then
			table.insert(characters, player.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(DUMMY_TAG) do
		if dummy ~= thrower and dummy:IsDescendantOf(workspace) then
			table.insert(characters, dummy)
		end
	end

	local hitbox = RaycastParams.new()
	hitbox.FilterType = Enum.RaycastFilterType.Include
	hitbox.FilterDescendantsInstances = characters

	-- The body sweep ignores characters (the hitbox finds those) and the client's own effects.
	local ignore = table.clone(characters)
	table.insert(ignore, thrower)
	local clientVFX = workspace:FindFirstChild("ClientVFX")
	if clientVFX then
		table.insert(ignore, clientVFX)
	end
	local world = RaycastParams.new()
	world.FilterType = Enum.RaycastFilterType.Exclude
	world.FilterDescendantsInstances = ignore

	return { Characters = hitbox, World = world }
end

-- Sweep from position along step. Returns the first hit, or nil if the path is clear.
function Projectile.Step(position: Vector3, step: Vector3, hitboxRadius: number, bodyRadius: number, filters: Filters): Hit?
	if step.Magnitude <= 0 then
		return nil
	end
	local character = workspace:Spherecast(position, hitboxRadius, step, filters.Characters)
	local world = workspace:Spherecast(position, bodyRadius, step, filters.World)
	if world and (not character or world.Distance < character.Distance) then
		return { Position = world.Position, Normal = world.Normal, Humanoid = nil }
	end
	if character then
		local model = character.Instance:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		return { Position = character.Position, Normal = character.Normal, Humanoid = humanoid }
	end
	return nil
end

return Projectile
