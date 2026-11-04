--!strict
-- Pebble Toss (Common, Projectile): throws a quick spinning rock that shatters into chips on hit.
-- Look: images/abilities/pebble toss.png ("Small spinning rock, dust puff on launch, rock chips on
-- hit"; clean low-poly, grey and white). Every asset is made in Blender (Game/assets/vfx/_src/
-- build_pebble_toss_*.py): the throw animation (PebbleTossKeyframes), the rock + chip shapes
-- (carved into ReplicatedStorage.VFX.PebbleToss by VFXTemplateService) and the dust, flare and
-- speed-line textures (Config/Assets).
--
--   1. Wind-up   0 – 0.4 s    rock sits in the right hand while the arm cocks behind the head.
--   2. Release   0.4 s        "Release" marker (frame 12): the rock leaves the hand at 55 studs/s,
--                             spinning 2 turns/s, speed lines behind it; dust puff at the feet.
--   3. Hit       AbilityHit   the SERVER decides the hit (AbilityService + shared/Projectile: a
--                             2.5-stud hitbox for characters): white star flash, 8 chips bursting
--                             back toward the thrower, a small dust puff. Flying its full range
--                             without a hit shatters it in the air.
-- The thrower plays 1–2 on the key press; everyone else from AbilityUsed; every client plays 3
-- from AbilityHit. Others' throws release on a timer (their animation reaches us by replication,
-- so we get no marker events for it).
--
-- Budget per throw: ~20 particles, 1 beam, 1 rock + 8 chips (unanchored, no collisions).
-- Everything a throw makes lives in one Folder under workspace.ClientVFX and is destroyed when
-- the throw is over; the character dying or leaving cleans it up too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Projectile = require(Shared:WaitForChild("Projectile"))
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Assets = require(Config:WaitForChild("Assets"))

local Pose = require(script.Parent.Pose)
local KEYFRAMES = require(script.Parent.PebbleTossKeyframes)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "PebbleToss" then
		def = ability
	end
end
assert(def, "PebbleToss is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Timing (seconds, at normal speed)
	HoldFrom = 0.1, -- the rock appears in the hand
	Release = 0.4, -- the animation's "Release" marker: frame 12 @ 30 fps (= Abilities WindupSeconds)
	MarkerGrace = 0.1, -- if our own track never fires the marker, release this much later anyway

	-- Rock (studs, studs/second)
	RockSpeed = def.ProjectileSpeed or 55,
	RockRange = def.Range,
	RockSpinTurns = 2, -- turns per second, topspin
	RockSize = 1.2, -- studs across (the Blender rock is scaled to this)
	-- Where our own rock stops: the same sweep as the server (shared/Projectile), which decides real hits
	HitboxRadius = def.HitboxRadius or 2.5, -- finds characters
	RockRadius = def.ProjectileRadius or 0.6, -- walls and the ground
	ServerHitWait = 1.5, -- seconds after the rock stops: no AbilityHit by then (thrower left) → clean up

	-- Launch dust at the feet
	DustCountMin = 6,
	DustCountMax = 8,
	DustLifetime = 0.4,
	DustColor = "#C9BFB0",
	DustSizeStart = 2,
	DustSizeEnd = 3.6,
	DustSpeedMin = 4,
	DustSpeedMax = 9,
	DustAhead = 1.2, -- studs in front of the root: just ahead of the front foot

	-- Speed-line trail (Beam) behind the rock
	TrailLength = 2.5,
	TrailWidthHead = 0.6,
	TrailWidthTail = 0.6,
	TrailColor = "#F2F2F5",

	-- Impact
	FlareSeconds = 0.12,
	FlareSize = 4.5, -- studs across at its biggest
	FlareColor = "#FFFFFF",
	ImpactBack = 1, -- studs from the impact point back toward the thrower: chips start outside the target
	ChipCount = 8,
	ChipScale = 2.5, -- the Blender chips are 0.16–0.3 studs: x2.5 = 0.4–0.75, readable next to the 1.2 rock
	ChipSpeedMin = 15, -- studs/second outward (sideways, on the thrower's side)...
	ChipSpeedMax = 25,
	ChipUpSpeed = 10, -- ...plus this much upward
	ChipGravity = 80, -- studs/second²; Roblox's 196 drops them through the floor within 0.3 s
	ChipSpinMax = 20, -- radians/second
	ChipFadeSeconds = 0.8, -- fade out from the hit, then gone
	HitDustCount = 4,
	HitDustLifetime = 0.4,
	HitDustSizeStart = 1,
	HitDustSizeEnd = 2.2,

	-- Asset ids (one place to change them: Shared/Config/Assets, Abilities)
	DustTexture = Assets.Textures.PebbleDust,
	FlareTexture = Assets.Textures.PebbleFlare,
	SpeedLinesTexture = Assets.Textures.PebbleSpeedLines,
	AnimationId = def.AnimationId, -- nil: Studio test animation (Pose)
}

export type Options = {
	TimeScale: number?, -- 1 = normal speed; /vfxtest plays at 0.25
	LocalHits: boolean?, -- true: the rock decides its own hit (VFX test, no server)
	PlayAnimation: boolean?, -- play the throw animation on this character (always for our own)
}

type Cast = {
	Character: Model,
	Folder: Folder,
	TimeScale: number,
	LocalHits: boolean,
	Rock: BasePart,
	Carrier: BasePart?,
	Flying: boolean,
	Connections: { RBXScriptConnection },
}

local PebbleTossVFX = {}

local casts: { [Model]: Cast } = {} -- the newest throw of each character
local vfxFolder: Folder? = nil

local function folder(): Folder
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end
	local existing = workspace:FindFirstChild("ClientVFX")
	if existing and existing:IsA("Folder") then
		vfxFolder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "ClientVFX"
	f.Parent = workspace
	vfxFolder = f
	return f
end

local function template(name: string): BasePart
	local templates = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("PebbleToss")
	return templates:WaitForChild(name) :: BasePart
end

local function numbers(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

local function anchor(parent: Instance, name: string, cframe: CFrame): (Part, Attachment)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = parent
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	return part, attachment
end

local function emitter(parent: Instance, timeScale: number, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.TimeScale = timeScale
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Dust puff blown out along the attachment's facing (direction), low and spreading sideways.
local function dust(parent: Attachment, timeScale: number, lifetime: number, sizeStart: number, sizeEnd: number, direction: Enum.NormalId): ParticleEmitter
	return emitter(parent, timeScale, {
		Name = "Dust",
		Texture = CONFIG.DustTexture,
		Color = ColorSequence.new(Color3.fromHex(CONFIG.DustColor)),
		EmissionDirection = direction,
		LightEmission = 0,
		LightInfluence = 0.25,
		Size = numbers(0, sizeStart, 1, sizeEnd),
		Transparency = numbers(0, 0.05, 0.5, 0.35, 1, 1), -- fades out
		Lifetime = NumberRange.new(lifetime),
		Speed = NumberRange.new(CONFIG.DustSpeedMin, CONFIG.DustSpeedMax),
		Drag = 4,
		SpreadAngle = if direction == Enum.NormalId.Top then Vector2.new(75, 75) else Vector2.new(70, 15),
		Acceleration = Vector3.new(0, 1.5, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
	})
end

local function excludeParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder() }
	return params
end

local function groundBelow(position: Vector3, character: Model): Vector3
	local result = workspace:Raycast(position, Vector3.new(0, -12, 0), excludeParams(character))
	return if result then result.Position + Vector3.new(0, 0.05, 0) else position - Vector3.new(0, 3, 0)
end

local function grip(hand: BasePart): CFrame
	local attachment = hand:FindFirstChild("RightGripAttachment")
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame
	end
	return hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)
end

local function endCast(cast: Cast)
	for _, connection in cast.Connections do
		connection:Disconnect()
	end
	table.clear(cast.Connections)
	cast.Folder:Destroy()
	if casts[cast.Character] == cast then
		casts[cast.Character] = nil
	end
end

-- Stop the rock where it is (it hit something). The impact comes from Hit().
local function stopRock(cast: Cast)
	cast.Flying = false
	cast.Rock.Transparency = 1
	if cast.Carrier then
		cast.Carrier:Destroy()
		cast.Carrier = nil
	end
end

local function launchDust(cast: Cast, root: BasePart, flat: Vector3)
	local feet = groundBelow(root.Position + flat * CONFIG.DustAhead, cast.Character) + Vector3.new(0, 0.4, 0)
	local _, at = anchor(cast.Folder, "LaunchDust", CFrame.lookAt(feet, feet + flat)) -- kicked forward
	local e = dust(at, cast.TimeScale, CONFIG.DustLifetime, CONFIG.DustSizeStart, CONFIG.DustSizeEnd, Enum.NormalId.Front)
	e:Emit(math.random(CONFIG.DustCountMin, CONFIG.DustCountMax))
end

local function launch(cast: Cast, root: BasePart, from: Vector3, flat: Vector3)
	launchDust(cast, root, flat)

	-- Beam carrier: follows the rock without its spin. -Z = forward, so the tail is at +Z.
	local carrier, head = anchor(cast.Folder, "Trail", CFrame.lookAt(from, from + flat))
	local tail = Instance.new("Attachment")
	tail.Position = Vector3.new(0, 0, CONFIG.TrailLength)
	tail.Parent = carrier
	local beam = Instance.new("Beam")
	beam.Attachment0 = head -- the texture's solid left end sits at the rock
	beam.Attachment1 = tail
	beam.Texture = CONFIG.SpeedLinesTexture
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = CONFIG.TrailWidthHead
	beam.Width1 = CONFIG.TrailWidthTail
	beam.Color = ColorSequence.new(Color3.fromHex(CONFIG.TrailColor))
	beam.Transparency = numbers(0, 0, 0.6, 0.4, 1, 1) -- transparent at the tail
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Parent = carrier
	cast.Carrier = carrier

	local rock = cast.Rock
	rock.Transparency = 0
	cast.Flying = true
	local filters = Projectile.Filters(cast.Character)
	local axis = flat:Cross(Vector3.yAxis) -- topspin: rolls forward over the top
	local position = from
	local travelled = 0
	local angle = 0
	local flight: RBXScriptConnection
	flight = RunService.RenderStepped:Connect(function(dt)
		if not cast.Flying then
			flight:Disconnect()
			return
		end
		local step = CONFIG.RockSpeed * dt * cast.TimeScale
		step = math.min(step, CONFIG.RockRange - travelled)
		local hit = Projectile.Step(position, flat * step, CONFIG.HitboxRadius, CONFIG.RockRadius, filters)
		position += flat * step
		travelled += step
		if hit or travelled >= CONFIG.RockRange then
			-- It hit something, or flew its full range (it shatters in the air there).
			stopRock(cast)
			if cast.LocalHits then
				PebbleTossVFX.Hit(cast.Character, if hit then hit.Position else position, if hit then hit.Normal else -flat)
			else
				-- The server's AbilityHit plays the impact. If it never comes (the thrower left), clean up.
				task.delay(CONFIG.ServerHitWait / cast.TimeScale, function()
					if casts[cast.Character] == cast then
						endCast(cast)
					end
				end)
			end
			return
		end
		angle += math.pi * 2 * CONFIG.RockSpinTurns * dt * cast.TimeScale
		rock.CFrame = CFrame.new(position) * CFrame.fromAxisAngle(axis, angle)
		carrier.CFrame = CFrame.lookAt(position, position + flat)
	end)
	table.insert(cast.Connections, flight)
end

-- Play the throw on a character. Every client runs this for every player who uses it.
-- isLocal = our own character: we play the animation (Roblox replicates it to everyone else).
function PebbleTossVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: Options?)
	local timeScale = options and options.TimeScale or 1
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	if not root or not hand then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit

	local f = Instance.new("Folder")
	f.Name = `PebbleToss_{character.Name}`
	f.Parent = folder()
	local rock = template("Rock"):Clone()
	rock.Size *= CONFIG.RockSize / math.max(rock.Size.X, rock.Size.Y, rock.Size.Z)
	rock.Transparency = 1
	rock.CFrame = grip(hand)
	rock.Parent = f

	local cast: Cast = {
		Character = character,
		Folder = f,
		TimeScale = timeScale,
		LocalHits = options and options.LocalHits or false,
		Rock = rock,
		Carrier = nil,
		Flying = false,
		Connections = {},
	}
	local previous = casts[character]
	if previous and not previous.Flying then
		endCast(previous) -- a rock still in the hand from an interrupted throw
	end
	casts[character] = cast
	table.insert(cast.Connections, character.Destroying:Connect(function()
		endCast(cast)
	end))

	local track: AnimationTrack? = nil
	if isLocal or (options and options.PlayAnimation) then
		track = Pose.Track(character, "PebbleToss", KEYFRAMES, CONFIG.AnimationId)
		if track then
			track:Play(0.05)
			track:AdjustSpeed(timeScale)
		end
	end

	-- The rock rides in the hand until release.
	local released = false
	local holding = RunService.RenderStepped:Connect(function()
		if not released and hand.Parent then
			rock.CFrame = grip(hand)
		end
	end)
	table.insert(cast.Connections, holding)
	task.delay(CONFIG.HoldFrom / timeScale, function()
		if not released then
			rock.Transparency = 0
		end
	end)

	local function release()
		if released or not f.Parent then
			return
		end
		released = true
		holding:Disconnect()
		launch(cast, root, grip(hand).Position, flat)
	end
	local waitFor = CONFIG.Release / timeScale
	if track then
		table.insert(cast.Connections, track:GetMarkerReachedSignal("Release"):Connect(release))
		waitFor += CONFIG.MarkerGrace / timeScale
	end
	task.delay(waitFor, release)
end

-- The server says this character's rock hit something at position (surface normal).
function PebbleTossVFX.Hit(character: Model, position: Vector3, normal: Vector3)
	local cast = casts[character]
	local timeScale = if cast then cast.TimeScale else 1
	if cast then
		stopRock(cast)
	end

	local f = Instance.new("Folder")
	f.Name = "PebbleTossHit"
	f.Parent = folder()

	-- Everything starts ImpactBack studs from the impact point toward the thrower, so nothing
	-- spawns inside what was hit.
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local back = if root then root.Position - position else normal
	back = Vector3.new(back.X, 0, back.Z)
	back = if back.Magnitude > 0.01 then back.Unit else Vector3.zAxis
	local origin = position + back * CONFIG.ImpactBack
	local _, at = anchor(f, "Impact", CFrame.new(origin))

	-- White star flash: pops up and is gone in FlareSeconds.
	local flare = emitter(at, timeScale, {
		Name = "Flare",
		Texture = CONFIG.FlareTexture,
		Color = ColorSequence.new(Color3.fromHex(CONFIG.FlareColor)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = numbers(0, CONFIG.FlareSize * 0.35, 0.35, CONFIG.FlareSize, 1, CONFIG.FlareSize * 0.85),
		Transparency = numbers(0, 0, 0.6, 0.1, 1, 1),
		Lifetime = NumberRange.new(CONFIG.FlareSeconds),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-12, 12),
		ZOffset = 2,
	})
	flare:Emit(1)

	-- Small dust puff where the rock broke.
	dust(at, timeScale, CONFIG.HitDustLifetime, CONFIG.HitDustSizeStart, CONFIG.HitDustSizeEnd, Enum.NormalId.Top)
		:Emit(CONFIG.HitDustCount)

	-- Chips: real (unanchored) parts that pass through everything, burst outward on the thrower's
	-- side of the impact, spin, and fade out. A VectorForce cancels part of Roblox's gravity to
	-- leave ChipGravity. Physics can't run slower, so at TimeScale < 1 the speeds are scaled by
	-- TimeScale and gravity by TimeScale²: the same arc, played slower.
	local lift = workspace.Gravity - CONFIG.ChipGravity * timeScale * timeScale
	local fade = TweenInfo.new(CONFIG.ChipFadeSeconds / timeScale, Enum.EasingStyle.Linear)
	for _ = 1, CONFIG.ChipCount do
		local chip = template(`Chip{math.random(1, 5)}`):Clone()
		chip.Size *= CONFIG.ChipScale
		chip.Anchored = false
		chip.CanCollide = false
		chip.CanTouch = false
		chip.CanQuery = false
		chip.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		chip.Parent = f

		-- Any flat direction within 90° of the thrower: never into the target.
		local out = CFrame.fromAxisAngle(Vector3.yAxis, (math.random() - 0.5) * math.pi):VectorToWorldSpace(back)
		local speed = CONFIG.ChipSpeedMin + math.random() * (CONFIG.ChipSpeedMax - CONFIG.ChipSpeedMin)
		local spinAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		spinAxis = if spinAxis.Magnitude > 0.01 then spinAxis.Unit else Vector3.yAxis
		chip.AssemblyLinearVelocity = (out * speed + Vector3.yAxis * CONFIG.ChipUpSpeed) * timeScale
		chip.AssemblyAngularVelocity = spinAxis * (CONFIG.ChipSpinMax * (0.5 + math.random() * 0.5)) * timeScale
		if lift > 0 then
			local attachment = Instance.new("Attachment")
			attachment.Parent = chip
			local force = Instance.new("VectorForce")
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Force = Vector3.new(0, chip:GetMass() * lift, 0)
			force.Parent = chip
		end
		TweenService:Create(chip, fade, { Transparency = 1 }):Play()
	end

	-- If this character's throw is cleaned up first (they left), the hit still finishes on its own.
	task.delay(math.max(CONFIG.ChipFadeSeconds, CONFIG.HitDustLifetime) / timeScale, function()
		f:Destroy()
		if cast then
			endCast(cast)
		end
	end)
end

PebbleTossVFX.Config = CONFIG
PebbleTossVFX.Keyframes = KEYFRAMES

return PebbleTossVFX
