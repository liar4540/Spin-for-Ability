--!strict
-- Star Cannon (Legendary, channelled beam): plant, cup a star between the palms at the right hip and
-- charge for 1.5 s inside an erupting golden aura, then thrust both hands forward and fire a massive
-- gold-white beam (12 wide, 80 long, 2 s) with energy rings racing down it. Enemies inside take 10
-- on contact then 2 every 0.2 s (max 30) and are heavily slowed so they can't walk out. Kamehameha-
-- inspired but original. Locked direction; a stun / ragdoll on the caster cancels it (AbilityBeam "Stop").
-- Look: images/abilities/star cannon.png (12 panels). White / gold / bright yellow / pale gold; no fire
-- or explosions. v2 (user feedback 2026-11-27): the beam rebuilt like Blood Moon Slash - six solid,
-- detailed layers (outer glow, plasma body, amber veins, flow streaks, crisp rim lines, white core)
-- that ripple and breathe, plus a few thin BLUE lines coiling round it as they race along.
-- v3 (user request 2026-11-27): the aura and the beam are now the user's Creator Store picks ("ui goku"
-- aura, "Ultimate Kamehameha" beam) recoloured gold, on the same timeline, aim, length and stop logic.
-- Lessons from the earlier skills: layered, moving effects (flipbook flames, ribbons,
-- spinning rings, flicker), no pastel wash, slow-motion checks (TimeScale).
--
-- Built the Studio-first way: templates in ReplicatedStorage.VFX.StarCannon
-- (Game/tools/build_star_cannon_templates.luau; textures build_star_cannon_textures.py; the animation
-- is client/Abilities/StarCannonKeyframes). Tweak the templates in Studio; this script times them.
--
-- Timeline (seconds after the key press):
--   0.00 - 1.50  CHARGE  feet planted; a star forms between the palms and swells, three rings spin round
--                        it, sparks are drawn in; the aura erupts and builds (gold-white flames, rising
--                        motes and streaks, ribbons spiralling up the body, spinning rings on the ground,
--                        dust blown outward, rocks lifting off the ground); light pulses with the orb;
--                        a deep rumble rises in pitch
--   1.50         FIRE    thrust: muzzle star, release burst; the beam shoots out to its full length
--   1.50 - 3.50  BEAM    4 layers flickering (white core, gold flow, white streaks, pale outer glow),
--                        rings racing down it, sparks along it, impact light where it meets a wall,
--                        hum + bass rumble, the caster's camera trembles
--   3.50 - 3.85  FADE    the beam thins out, the aura dies down, stars twinkle where it was

local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Projectile = require(Shared:WaitForChild("Projectile"))

local Client = script.Parent.Parent
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))
local Pose = require(script.Parent.Pose)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "StarCannon" then
		def = ability
	end
end
assert(def, "StarCannon is missing from Shared/Config/Abilities")

local CONFIG = {
	FIRE_AT = def.WindupSeconds or 1.5,
	BEAM_SECONDS = def.BeamSeconds or 2,
	RANGE = def.Range,
	ANIMATION = def.AnimationId,
	HANDS = Vector3.new(0, -0.1, 1.65), -- beam origin from the root (same as the server's BEAM_HANDS)
	FADE = 0.35,
	CLEANUP_AFTER = 1.5, -- after the beam ends
	ORB = { FROM = 0.3, TO = 2.4, RING_SCALE = 1.6 },
	AURA = { START_RATE = 0.35, LIGHT = 3 },
	RIBBONS = 3,
	ROCKS = 7,
	BEAM = {
		EXTEND = 0.12, -- seconds to shoot out to full length
		FLICKER = 0.07, -- width flicker
		RING_EVERY = 0.09,
		RING_SPEED = 150,
		SHAKE = 0.12, -- studs of camera tremble (caster only)
	},
	COILS = {
		EVERY = 0.32, -- a new set of strands this often
		STRANDS = 3, -- per set, evenly round the beam
		SPEED = 75, -- studs/s along the beam
		RADIUS = 7.5, -- studs from the beam's centre (it's ~12 wide)
		TURN = 14, -- studs per full turn of the coil
	},
	IMPACT_EVERY = 0.15,
}

type Cast = {
	Folder: Folder,
	Character: Model,
	Ended: boolean,
	Stopped: boolean,
	Fired: boolean,
	Connections: { RBXScriptConnection },
	Owned: { Instance }, -- things parented into the character (the aura); destroyed with the cast
	Stop: (() -> ())?,
}

local StarCannonVFX = {}
StarCannonVFX.CONFIG = CONFIG
StarCannonVFX.TimeScale = 1 -- slow motion for checking
local function s(seconds: number): number
	return seconds / StarCannonVFX.TimeScale
end
local function slowed(inst: Instance)
	if StarCannonVFX.TimeScale == 1 then
		return
	end
	local all = inst:GetDescendants()
	table.insert(all, inst)
	for _, d in all do
		if d:IsA("ParticleEmitter") then
			d.TimeScale = StarCannonVFX.TimeScale
		elseif d:IsA("Trail") then
			d.Lifetime /= StarCannonVFX.TimeScale
		elseif d:IsA("Beam") then
			d.TextureSpeed *= StarCannonVFX.TimeScale
		end
	end
end

local localPlayer = Players.LocalPlayer
local active: { [Model]: Cast } = {}

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

local function templates(): Folder
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("StarCannon") :: Folder
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(s(seconds), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function scale(n: number): number
	return n * (if Quality.Low then 0.5 else 1)
end

local function clone(name: string, cast: Cast): Instance
	local inst = templates():FindFirstChild(name):Clone()
	slowed(inst)
	inst.Parent = cast.Folder
	return inst
end

local function emitters(inst: Instance, on: boolean, rateScale: number?)
	for _, e in inst:GetDescendants() do
		if e:IsA("ParticleEmitter") then
			if on then
				local base = e:GetAttribute("BaseRate") :: number?
				if not base then
					base = e.Rate
					e:SetAttribute("BaseRate", base)
				end
				e.Rate = scale(base :: number) * (rateScale or 1)
			end
			e.Enabled = on
		end
	end
end

local function playSound(cast: Cast, name: string, at: Vector3): Sound?
	local list = templates():FindFirstChild("Sounds")
	local template = list and list:FindFirstChild(name) :: Sound?
	if not template then
		return nil
	end
	local holder = Instance.new("Part")
	holder.Name = `Sound_{name}`
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	holder.Parent = cast.Folder
	local sound = template:Clone()
	sound.PlaybackSpeed *= StarCannonVFX.TimeScale
	sound.Parent = holder
	sound:Play()
	return sound
end

local studioAnimationId: string? = nil
local function animationId(): string?
	if RunService:IsStudio() then
		if not studioAnimationId then
			local sequence = templates():FindFirstChild("CastAnimation")
			if sequence and sequence:IsA("KeyframeSequence") then
				studioAnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			end
		end
		if studioAnimationId then
			return studioAnimationId
		end
	end
	return CONFIG.ANIMATION
end

local function ground(at: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	table.insert(ignore, folder())
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at, Vector3.new(0, -10, 0), params)
	return if hit then hit.Position else at - Vector3.new(0, 3, 0)
end

local function handsMidpoint(character: Model, root: BasePart): Vector3
	local r = character:FindFirstChild("RightHand") :: BasePart?
	local l = character:FindFirstChild("LeftHand") :: BasePart?
	if r and l then
		return (r.Position + l.Position) / 2
	end
	return root.Position + root.CFrame.LookVector * 1.5
end

-- ===== Charge: orb + aura =====

local function charge(cast: Cast, character: Model, root: BasePart)
	local c = CONFIG
	local orb = clone("Orb", cast) :: BasePart
	local rings = {}
	for i = 1, 3 do
		table.insert(rings, clone(`OrbRing{i}`, cast) :: BasePart)
	end
	emitters(orb, true)
	local orbLight = orb:FindFirstChild("Light") :: PointLight?

	-- the Creator Store aura: its emitters go straight into the matching body parts, so the flames
	-- follow every limb (one template Folder per part name; HumanoidRootPart holds the foot flames)
	local auraEmitters: { ParticleEmitter } = {}
	local auraLight: PointLight? = nil
	local auraTemplate = templates():FindFirstChild("Aura")
	for _, slot in (if auraTemplate then auraTemplate:GetChildren() else {}) do
		local bodyPart = character:FindFirstChild(slot.Name)
		if bodyPart and bodyPart:IsA("BasePart") then
			for _, item in slot:GetChildren() do
				local copy = item:Clone()
				slowed(copy)
				copy.Parent = bodyPart
				table.insert(cast.Owned, copy)
				if copy:IsA("PointLight") then
					copy.Brightness = 0
					auraLight = copy
				end
				local list = copy:GetDescendants()
				table.insert(list, copy)
				for _, e in list do
					if e:IsA("ParticleEmitter") then
						e:SetAttribute("BaseRate", e.Rate)
						e.Rate = scale(e.Rate) * c.AURA.START_RATE
						e.Enabled = true
						table.insert(auraEmitters, e)
					end
				end
			end
		end
	end
	local feet = ground(root.Position, { character })
	local groundRing = clone("Ground", cast) :: BasePart
	groundRing.CFrame = CFrame.new(feet + Vector3.new(0, 0.08, 0))
	emitters(groundRing, true)
	local groundImages = {}
	for _, gui in groundRing:GetChildren() do
		local img = gui:FindFirstChild("Image") :: ImageLabel?
		if img then
			img.ImageTransparency = 1
			tween(img, c.FIRE_AT, { ImageTransparency = 0.2 })
			table.insert(groundImages, img)
		end
	end

	local ribbons: { BasePart } = {}
	for i = 1, c.RIBBONS do
		local ribbon = clone("Ribbon", cast) :: BasePart
		ribbon.CFrame = root.CFrame
		local trail = ribbon:FindFirstChild("Trail") :: Trail?
		if trail then
			trail.Enabled = true
		end
		ribbons[i] = ribbon
	end

	type Rock = { Part: BasePart, Base: Vector3, Lift: number, Spin: Vector3, Phase: number }
	local rocks: { Rock } = {}
	for i = 1, math.floor(scale(c.ROCKS)) do
		local rock = clone("Rock", cast) :: BasePart
		local a = math.random() * math.pi * 2
		local d = 2.5 + math.random() * 3
		local size = 0.5 + math.random() * 0.6
		rock.Size = Vector3.new(size, size * 0.8, size * 0.9)
		local base = feet + Vector3.new(math.cos(a) * d, size * 0.3, math.sin(a) * d)
		rock.CFrame = CFrame.new(base) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		rocks[i] = {
			Part = rock,
			Base = base,
			Lift = 1 + math.random() * 2.5,
			Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3,
			Phase = math.random() * 6,
		}
	end

	local start = os.clock()
	local releasedAt: number? = nil
	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = (os.clock() - start) * StarCannonVFX.TimeScale
		local k = math.clamp(t / c.FIRE_AT, 0, 1) -- charge progress
		local pulse = 0.65 + 0.35 * math.sin(t * (8 + 10 * k))

		-- orb between the palms, swelling, until the beam takes over
		if not cast.Fired then
			local mid = handsMidpoint(character, root)
			local size = c.ORB.FROM + (c.ORB.TO - c.ORB.FROM) * k ^ 1.6
			size *= 0.92 + 0.08 * pulse
			orb.Size = Vector3.new(size, size, size)
			orb.CFrame = CFrame.new(mid)
			for i, ring in rings do
				local r = size * c.ORB.RING_SCALE * (1 + 0.25 * i)
				ring.Size = Vector3.new(r, 0.05, r)
				local spin = t * (3 + i * 1.3)
				ring.CFrame = CFrame.new(mid)
					* CFrame.Angles(spin * (i == 1 and 1 or 0.3), spin * (i == 2 and 1 or 0.5), spin * (i == 3 and 1 or 0.2))
			end
			if orbLight then
				orbLight.Brightness = 4 * k * pulse
			end
		end

		-- aura follows the body; builds over the charge, holds while firing
		local build = if releasedAt then 1 else 0.35 + 0.65 * k
		if auraLight then
			auraLight.Brightness = c.AURA.LIGHT * build * pulse
		end
		for _, e in auraEmitters do
			if e.Enabled then
				e.Rate = scale((e:GetAttribute("BaseRate") :: number?) or e.Rate) * build
			end
		end
		for i, img in groundImages do
			img.Rotation = t * (if i == 1 then 40 else -55)
		end

		-- ribbons spiral up the body, over and over
		for i, ribbon in ribbons do
			local phase = i / #ribbons
			local h = ((t * 1.6 + phase) % 1)
			local angle = t * 7 + phase * math.pi * 2
			local radius = 1.6 + 0.6 * math.sin(t * 5 + i)
			ribbon.CFrame = root.CFrame * CFrame.new(math.cos(angle) * radius, -2.8 + h * 6, math.sin(angle) * radius)
		end

		-- rocks lift and bob; blown away when the beam fires
		for _, rock in rocks do
			if rock.Part.Parent then
				local y = rock.Lift * math.clamp(t / 1.2, 0, 1) + 0.15 * math.sin(t * 3 + rock.Phase)
				rock.Part.CFrame = CFrame.new(rock.Base + Vector3.new(0, y, 0))
					* CFrame.Angles(rock.Spin.X * t, rock.Spin.Y * t, rock.Spin.Z * t)
			end
		end
	end)
	table.insert(cast.Connections, conn)

	return {
		Release = function()
			releasedAt = os.clock()
			emitters(orb, false)
			tween(orb, 0.1, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
			for _, ring in rings do
				for _, gui in ring:GetChildren() do
					local img = gui:FindFirstChild("Image") :: ImageLabel?
					if img then
						tween(img, 0.15, { ImageTransparency = 1 })
					end
				end
			end
			for _, rock in rocks do -- blown back off the ground, fading
				local away = (rock.Base - root.Position) * Vector3.new(1, 0, 1)
				away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(1, 0, 0)
				tween(rock.Part, 0.6, { CFrame = rock.Part.CFrame + away * 6 + Vector3.new(0, 1.5, 0), Transparency = 1 })
			end
		end,
		Finish = function(fade: number)
			for _, e in auraEmitters do
				e.Enabled = false
			end
			emitters(groundRing, false)
			for _, img in groundImages do
				tween(img, fade, { ImageTransparency = 1 })
			end
			if auraLight then
				tween(auraLight, fade, { Brightness = 0 })
			end
			for _, ribbon in ribbons do
				local trail = ribbon:FindFirstChild("Trail") :: Trail?
				if trail then -- leave it on (switching a Trail off erases it); it fades as the ribbon stops
					trail.Lifetime = s(0.2)
				end
			end
		end,
	}
end

-- ===== Beam =====

local function beam(cast: Cast, character: Model, origin: Vector3, direction: Vector3, length: number, isLocal: boolean)
	local c = CONFIG.BEAM
	-- The Creator Store beam (recoloured gold): built pointing down -Z from its Origin at the hands, a
	-- fixed length. Record its pieces in that space, then every frame stretch it to the reach: the long
	-- tubes (attribute Stretch) grow, every attachment past the muzzle slides along, the muzzle stays.
	local model = clone("Beam", cast) :: Model
	local native = (model:GetAttribute("Length") :: number?) or 70
	local home = model:GetPivot()
	type Tube = { Part: BasePart, Near: number, Far: number, Size: Vector3, Rotation: CFrame }
	type Att = { Attachment: Attachment, Position: Vector3 }
	local tubes: { Tube } = {}
	local atts: { Att } = {}
	local storeBeams: { Beam } = {}
	local beamWidths: { [Beam]: Vector2 } = {}
	-- The store bursts (swooshes, dots, rings) fire at up to ~400 studs/s and would fly 180-290 studs,
	-- far past the 80-stud range: their speed is capped every frame so no particle travels past the reach.
	type Burst = { Emitter: ParticleEmitter, Speed: NumberRange, Travel: number }
	local bursts: { Burst } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Speed.Max * d.Lifetime.Max > 1 then
			table.insert(bursts, { Emitter = d, Speed = d.Speed, Travel = d.Speed.Max * d.Lifetime.Max })
		end
		if d:IsA("BasePart") and d:GetAttribute("Stretch") then
			local rel = home:ToObjectSpace(d.CFrame)
			local half = d.Size.Z / 2
			table.insert(tubes, { Part = d, Near = -rel.Z - half, Far = -rel.Z + half, Size = d.Size, Rotation = rel.Rotation })
		elseif d:IsA("Attachment") then
			table.insert(atts, { Attachment = d, Position = home:PointToObjectSpace(d.WorldPosition) })
		elseif d:IsA("Beam") then
			table.insert(storeBeams, d)
			beamWidths[d] = Vector2.new(d.Width0, d.Width1)
		end
	end
	local pivot = CFrame.lookAt(origin, origin + direction)
	model:PivotTo(pivot)
	emitters(model, true)
	local MUZZLE = 4 -- studs at the hands that keep their shape
	local function stretch(reach: number, width: number)
		local k = math.max(reach - MUZZLE, 0.05) / (native - MUZZLE)
		local function along(d: number): number
			return if d <= MUZZLE then d else MUZZLE + (d - MUZZLE) * k
		end
		for _, tube in tubes do
			local near, far = along(tube.Near), along(tube.Far)
			tube.Part.Size = Vector3.new(tube.Size.X * width, tube.Size.Y * width, math.max(far - near, 0.05))
			tube.Part.CFrame = pivot * CFrame.new(0, 0, -(near + far) / 2) * tube.Rotation
		end
		for _, a in atts do
			local p = a.Position
			a.Attachment.WorldPosition = pivot * Vector3.new(p.X * width, p.Y * width, -along(-p.Z))
		end
		for b, w in beamWidths do
			b.Width0 = w.X * width
			b.Width1 = w.Y * width
		end
		for _, burst in bursts do
			local f = math.min(1, reach / burst.Travel)
			burst.Emitter.Speed = NumberRange.new(burst.Speed.Min * f, burst.Speed.Max * f)
		end
	end
	stretch(0.1, 0.6)
	local sparks = clone("Sparks", cast) :: BasePart
	emitters(sparks, true)

	local muzzle = clone("Muzzle", cast) :: BasePart
	muzzle.CFrame = CFrame.lookAt(origin, origin + direction)
	emitters(muzzle, true)
	local muzzleLight = muzzle:FindFirstChild("Light") :: PointLight?
	if muzzleLight then
		muzzleLight.Brightness = 6
	end

	local endPoint = origin + direction * length
	local hitsWall = length < CONFIG.RANGE - 0.5
	local impact: BasePart? = nil
	if hitsWall then
		impact = clone("Impact", cast) :: BasePart
		impact.CFrame = CFrame.lookAt(endPoint, endPoint - direction)
		local il = impact:FindFirstChild("Light") :: PointLight?
		if il then
			il.Brightness = 5
		end
	end

	local right = direction:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		right = Vector3.xAxis
	end
	right = right.Unit
	type TravelRing = { Part: BasePart, Born: number, Spin: number }
	local travel: { TravelRing } = {}
	local start = os.clock()
	local lastRing = -1
	local lastImpact = -1
	local lastCoil = -1
	type Coil = { Part: BasePart, Born: number, Phase: number, Done: number? }
	local coils: { Coil } = {}
	local fadeFrom: number? = nil
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) * StarCannonVFX.TimeScale
		if cast.Stopped and not fadeFrom then
			fadeFrom = t
		end
		local fade = if fadeFrom then math.clamp((t - fadeFrom) / CONFIG.FADE, 0, 1) else 0
		local reach = length * math.clamp(t / c.EXTEND, 0, 1)
		local flicker = 1 + c.FLICKER * math.sin(t * 47) + c.FLICKER * 0.6 * math.sin(t * 83)
		stretch(math.max(reach, 0.1), flicker * (1 - fade) * (0.6 + 0.4 * math.clamp(t / c.EXTEND, 0, 1)))
		-- blue coils: a few thin lines spiralling round the beam as they race along it
		local k = CONFIG.COILS
		if not fadeFrom and t - lastCoil >= k.EVERY then
			lastCoil = t
			local base = math.random() * math.pi * 2
			for n = 1, k.STRANDS do
				local part = clone("Coil", cast) :: BasePart
				part.CFrame = CFrame.new(origin)
				local trail = part:FindFirstChild("Trail") :: Trail?
				if trail then
					trail.Enabled = true
				end
				emitters(part, true)
				table.insert(coils, { Part = part, Born = t, Phase = base + n * 2 * math.pi / k.STRANDS, Done = nil })
			end
		end
		local up = right:Cross(direction)
		for i = #coils, 1, -1 do
			local cl = coils[i]
			local d = (t - cl.Born) * k.SPEED
			if d >= reach or fadeFrom then
				if not cl.Done then
					cl.Done = t
					emitters(cl.Part, false) -- the trail stays on and fades as the strand stops
				end
				if t - cl.Done > 0.4 then
					cl.Part:Destroy()
					table.remove(coils, i)
				end
			else
				local theta = cl.Phase + d / k.TURN * 2 * math.pi
				local radius = k.RADIUS * (0.55 + 0.45 * math.clamp(d / 12, 0, 1))
				cl.Part.CFrame = CFrame.new(origin + direction * d + (right * math.cos(theta) + up * math.sin(theta)) * radius)
			end
		end
		sparks.Size = Vector3.new(6, 6, math.max(1, reach))
		sparks.CFrame = CFrame.lookAt(origin + direction * (reach / 2), origin + direction * reach)

		-- rings race down the beam
		if not fadeFrom and t - lastRing >= c.RING_EVERY then
			lastRing = t
			local ring = clone("TravelRing", cast) :: BasePart
			table.insert(travel, { Part = ring, Born = t, Spin = (math.random() - 0.5) * 6 })
		end
		for i = #travel, 1, -1 do
			local r = travel[i]
			local age = t - r.Born
			local d = age * c.RING_SPEED
			if d > reach or not r.Part.Parent then
				r.Part:Destroy()
				table.remove(travel, i)
			else
				local u = d / math.max(reach, 1)
				local size = (11 + 5 * u) * (1 + 0.08 * math.sin(age * 30)) * (1 - fade * 0.5)
				r.Part.Size = Vector3.new(size, 0.05, size)
				r.Part.CFrame = CFrame.fromMatrix(origin + direction * d, right, direction) * CFrame.Angles(0, r.Spin * age, 0)
				for _, gui in r.Part:GetChildren() do
					local img = gui:FindFirstChild("Image") :: ImageLabel?
					if img then
						img.ImageTransparency = math.clamp(0.1 + 0.9 * u ^ 1.5 + fade, 0, 1)
					end
				end
			end
		end

		-- impact light where it meets a wall
		if impact and not fadeFrom and t - lastImpact >= CONFIG.IMPACT_EVERY then
			lastImpact = t
			for name, n in { Flash = 1, Ring = 1, Sparks = math.floor(scale(14)), Stars = math.floor(scale(4)) } do
				local e = impact:FindFirstChild(name) :: ParticleEmitter?
				if e then
					e:Emit(n)
				end
			end
		end

		-- the caster's camera trembles
		if isLocal and humanoid then
			humanoid.CameraOffset = if fade < 1
				then Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * c.SHAKE * 2 * (1 - fade)
				else Vector3.zero
		end

		if fade >= 1 then
			conn:Disconnect()
			if humanoid and isLocal then
				humanoid.CameraOffset = Vector3.zero
			end
			for _, b in storeBeams do
				b.Enabled = false
			end
			for _, tube in tubes do
				tube.Part.Transparency = 1
			end
			emitters(model, false)
			emitters(sparks, false)
			emitters(muzzle, false)
			local motes = sparks:FindFirstChild("Motes") :: ParticleEmitter?
			if motes then
				motes:Emit(math.floor(scale(30))) -- stars twinkling where the beam was
			end
			for _, r in travel do
				r.Part:Destroy()
			end
			table.clear(travel)
			for _, cl in coils do
				cl.Part:Destroy()
			end
			table.clear(coils)
			if muzzleLight then
				muzzleLight.Brightness = 0
			end
			if impact then
				local il = impact:FindFirstChild("Light") :: PointLight?
				if il then
					tween(il, 0.3, { Brightness = 0 })
				end
			end
		end
	end)
	table.insert(cast.Connections, conn)
end

-- ===== Cast =====

local function endCast(cast: Cast)
	if cast.Ended then
		return
	end
	cast.Ended = true
	for _, conn in cast.Connections do
		conn:Disconnect()
	end
	for _, inst in cast.Owned do
		inst:Destroy()
	end
	if active[cast.Character] == cast then
		active[cast.Character] = nil
	end
	cast.Folder:Destroy()
end

local function stopCast(cast: Cast)
	if cast.Stopped then
		return
	end
	cast.Stopped = true
	if cast.Stop then
		cast.Stop()
	end
	task.delay(s(CONFIG.FADE + CONFIG.CLEANUP_AFTER), function()
		endCast(cast)
	end)
end

-- Fire the beam for a cast (local prediction, or another player's from AbilityBeam "Fire").
local function fireBeam(cast: Cast, origin: Vector3, direction: Vector3, length: number, isLocal: boolean)
	if cast.Fired or cast.Stopped then
		return
	end
	cast.Fired = true
	local root = cast.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	playSound(cast, "Release", origin)
	local loop = playSound(cast, "Loop", origin + direction * 10)
	beam(cast, cast.Character, origin, direction, length, isLocal)
	task.delay(s(CONFIG.BEAM_SECONDS), function()
		if loop then
			tween(loop, CONFIG.FADE, { Volume = 0 })
		end
		stopCast(cast)
	end)
	local _ = root
end

-- Play the charge on a character (the caster on the key press; others from AbilityUsed).
function StarCannonVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: { PlayAnimation: boolean? }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = active[character]
	if old then
		endCast(old)
	end
	local f = Instance.new("Folder")
	f.Name = `StarCannon_{character.Name}`
	f.Parent = folder()
	local cast: Cast = { Folder = f, Character = character, Ended = false, Stopped = false, Fired = false, Connections = {}, Owned = {} }
	active[character] = cast
	Debris:AddItem(f, s(CONFIG.FIRE_AT + CONFIG.BEAM_SECONDS + CONFIG.FADE + CONFIG.CLEANUP_AFTER) + 2)

	local flat = Vector3.new(aim.X, 0, aim.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local track: AnimationTrack? = nil
	if isLocal or (options and options.PlayAnimation) then
		local id = animationId()
		track = if id then Pose.Track(character, "StarCannon", {}, id) else nil
		if track then
			track.Looped = false
			track:Play(0.1)
			track:AdjustSpeed(StarCannonVFX.TimeScale)
		end
	end
	if isLocal and humanoid then
		-- locked in place facing the aim (the server roots and turns us too)
		humanoid.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)
	end

	local chargeSound = playSound(cast, "Charge", root.Position)
	if chargeSound then
		tween(chargeSound, CONFIG.FIRE_AT, { PlaybackSpeed = chargeSound.PlaybackSpeed * 1.65 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	local rumble = playSound(cast, "Rumble", root.Position)

	local chargeFx = charge(cast, character, root)
	cast.Stop = function()
		chargeFx.Release()
		chargeFx.Finish(CONFIG.FADE)
		if track and track.IsPlaying and not cast.Fired then
			track:Stop(0.2)
		end
		if chargeSound then
			tween(chargeSound, 0.2, { Volume = 0 })
		end
		if rumble then
			tween(rumble, CONFIG.FADE, { Volume = 0 })
		end
		if isLocal and humanoid then
			humanoid.AutoRotate = true
		end
	end

	task.delay(s(CONFIG.FIRE_AT), function()
		if cast.Stopped or cast.Ended or not root.Parent then
			return
		end
		chargeFx.Release()
		if chargeSound then
			tween(chargeSound, 0.15, { Volume = 0 })
		end
		if isLocal then
			local origin = root.Position + forward * CONFIG.HANDS.Z + Vector3.yAxis * CONFIG.HANDS.Y
			local wall = workspace:Raycast(origin, forward * CONFIG.RANGE, Projectile.Filters(character).World)
			fireBeam(cast, origin, forward, if wall then math.max(1, wall.Distance) else CONFIG.RANGE, true)
		end
	end)
end

-- The server's word on a beam (AbilityBeam): "Fire" with where it goes (others draw it from this; the
-- caster already predicted it), or "Stop" when the caster was interrupted.
function StarCannonVFX.Beam(character: Model, phase: string, origin: Vector3?, direction: Vector3?, length: number?, _serverTime: number?)
	local cast = active[character]
	if not cast then
		return
	end
	if phase == "Stop" then
		stopCast(cast)
	elseif phase == "Fire" and origin and direction and length then
		fireBeam(cast, origin, direction, length, character == (localPlayer and localPlayer.Character))
	end
end

-- First contact on each enemy (AbilityImpact): a burst of light, rings and star sparks + the hit sound.
function StarCannonVFX.Impact(_attacker: Model, hits: { { Target: Model, Position: Vector3 } }, serverTime: number?)
	if serverTime and workspace:GetServerTimeNow() - serverTime > 1 then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "StarCannon_Hit"
	f.Parent = folder()
	Debris:AddItem(f, 3)
	local cast: Cast = { Folder = f, Character = _attacker, Ended = false, Stopped = false, Fired = false, Connections = {}, Owned = {} }
	for _, hit in hits do
		local root = hit.Target and hit.Target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local burst = clone("Impact", cast) :: BasePart
			burst.CFrame = root.CFrame
			for name, n in { Flash = 1, Ring = 1, Sparks = math.floor(scale(18)), Stars = math.floor(scale(8)) } do
				local e = burst:FindFirstChild(name) :: ParticleEmitter?
				if e then
					e:Emit(n)
				end
			end
			playSound(cast, "Hit", root.Position)
		end
	end
end

return StarCannonVFX
