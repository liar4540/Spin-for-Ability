--!strict
-- Pebble Toss (Common, Projectile): throws a quick spinning rock that shatters into chips on hit.
-- Look: images/abilities/pebble toss.png ("Small spinning rock, dust puff on launch, rock chips on
-- hit"; clean low-poly, grey and white). Every asset is made in Blender (Game/assets/vfx/_src/
-- build_pebble_toss_*.py): the throw animation (PebbleTossKeyframes), the rock + chip shapes
-- (carved into ReplicatedStorage.VFX.PebbleToss by VFXTemplateService) and the dust, flare and
-- speed-line textures (Config/Assets).
--
--   1. Wind-up   0 – 0.4 s    rock sits in the right hand while the arm cocks behind the head.
--   2. Release   0.4 s        "Release" marker (frame 12): the rock leaves the hand at 80 studs/s,
--                             spinning 2 turns/s, speed lines behind it; dust puff at the feet.
--   3. Hit       AbilityHit   the SERVER decides the hit (AbilityService): white star flash,
--                             6–10 chips flying out under gravity, a small dust puff.
-- The thrower plays 1–2 on the key press; everyone else from AbilityUsed; every client plays 3
-- from AbilityHit. Others' throws release on a timer (their animation reaches us by replication,
-- so we get no marker events for it).
--
-- Budget per throw: ~20 particles, 1 beam, 1 rock + up to 10 chips (no physics: moved in code).
-- Everything a throw makes lives in one Folder under workspace.ClientVFX and is destroyed when
-- the throw is over; the character dying or leaving cleans it up too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
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
	RockSpeed = def.ProjectileSpeed or 80,
	RockRange = def.Range,
	RockSpinTurns = 2, -- turns per second, topspin
	RockRadius = 0.4, -- for our own "stop at what it touched" check; the server decides real hits

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
	TrailLength = 1.5,
	TrailWidthHead = 1,
	TrailWidthTail = 0.4,
	TrailColor = "#F2F2F5",

	-- Impact
	FlareSeconds = 0.12,
	FlareSize = 4.5, -- studs across at its biggest
	FlareColor = "#FFFFFF",
	ChipCountMin = 6,
	ChipCountMax = 10,
	ChipSpeedMin = 10,
	ChipSpeedMax = 20,
	ChipGravity = 80, -- studs/second²
	ChipLifetime = 1, -- seconds, then the chip is gone
	ChipFadeFrom = 0.7, -- fraction of the lifetime when chips start fading out
	HitDustCount = 3,
	HitDustLifetime = 0.5,

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

type Chip = { Part: BasePart, Velocity: Vector3, Axis: Vector3, Spin: number, GroundY: number }

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
	local params = excludeParams(cast.Character)
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
		local hit = if step > 0 then workspace:Spherecast(position, CONFIG.RockRadius, flat * step, params) else nil
		if hit then
			position = hit.Position
			stopRock(cast)
			if cast.LocalHits then
				PebbleTossVFX.Hit(cast.Character, hit.Position, hit.Normal)
			end
			return
		end
		position += flat * step
		travelled += step
		if travelled >= CONFIG.RockRange then
			-- Flew its full range without touching anything: the server sends no hit, so we're done.
			endCast(cast)
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
	local up = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local _, at = anchor(f, "Impact", CFrame.new(position + up * 0.2))

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

	local _, ground = anchor(f, "HitDust", CFrame.new(groundBelow(position, character)))
	dust(ground, timeScale, CONFIG.HitDustLifetime, 1.5, 3, Enum.NormalId.Top):Emit(CONFIG.HitDustCount)

	-- Chips: moved in code (no physics), bounce once off the ground, fade, then gone.
	local chips: { Chip } = {}
	local floorY = groundBelow(position, character).Y
	for _ = 1, math.random(CONFIG.ChipCountMin, CONFIG.ChipCountMax) do
		local chip = template(`Chip{math.random(1, 5)}`):Clone()
		chip.CFrame = CFrame.new(position + up * 0.15) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		chip.Parent = f
		local spread = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
		local direction = (up + spread * 0.9 + Vector3.yAxis * 0.6).Unit
		local speed = CONFIG.ChipSpeedMin + math.random() * (CONFIG.ChipSpeedMax - CONFIG.ChipSpeedMin)
		table.insert(chips, {
			Part = chip,
			Velocity = direction * speed,
			Axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
			Spin = (8 + math.random() * 10) * (if math.random() < 0.5 then -1 else 1),
			GroundY = floorY + chip.Size.Magnitude * 0.3,
		})
	end

	local age = 0
	local move: RBXScriptConnection
	move = RunService.RenderStepped:Connect(function(dt)
		local t = dt * timeScale
		age += t
		if age >= CONFIG.ChipLifetime then
			move:Disconnect()
			f:Destroy()
			if cast then
				endCast(cast)
			end
			return
		end
		local fade = math.clamp((age / CONFIG.ChipLifetime - CONFIG.ChipFadeFrom) / (1 - CONFIG.ChipFadeFrom), 0, 1)
		for _, chip in chips do
			chip.Velocity -= Vector3.new(0, CONFIG.ChipGravity * t, 0)
			local cf = chip.Part.CFrame
			local p = cf.Position + chip.Velocity * t
			if p.Y < chip.GroundY and chip.Velocity.Y < 0 then
				p = Vector3.new(p.X, chip.GroundY, p.Z)
				chip.Velocity = Vector3.new(chip.Velocity.X * 0.5, -chip.Velocity.Y * 0.3, chip.Velocity.Z * 0.5)
				chip.Spin *= 0.5
			end
			chip.Part.CFrame = CFrame.new(p) * CFrame.fromAxisAngle(chip.Axis, chip.Spin * t) * cf.Rotation
			chip.Part.Transparency = fade
		end
	end)
	-- If this character's throw is cleaned up first (they left), the hit still finishes on its own.
end

PebbleTossVFX.Config = CONFIG
PebbleTossVFX.Keyframes = KEYFRAMES

return PebbleTossVFX
