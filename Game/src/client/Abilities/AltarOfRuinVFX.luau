--!strict
-- AltarOfRuinVFX: the Altar of Ruin ability (Secret). Shared/Config/Abilities "AltarOfRuin" holds the numbers.
--
-- Timeline (seconds from the key press):
--   0   - 1.5   CAST      the caster bows over pressed palms (AltarOfRuinKeyframes); crimson mist pools at
--                         their feet, the ground starts to rumble
--   1.5 - 3.5   RISE      (AbilityZone "Start") the altar rises out of the ground behind them; the domain's
--                         crimson floor spreads to its full 120-stud radius; the world tints red for anyone inside
--   3.5 - 18.5  SLASHES   a boom, then a storm of slashes: black blades with white-hot edges flash all over
--                         the zone (most of them near you, so it feels everywhere at any size), fighters inside
--                         get cut over and over, slash sounds whip around you; ash drifts up
--   18.5        END       (AbilityZone "End") the altar sinks, the floor and the tint fade
-- The user's own assets (tools/build_altar_of_ruin_templates -> ReplicatedStorage.VFX.AltarOfRuin): the shrine
-- (Altar), the slash storm (SlashField, its emitters fill the zone) and two sounds (Sounds.Cast on the key
-- press, Sounds.Loop while the slashes run). Without them: a stand-in altar, our own slashes and sounds,
-- built here.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Shared:WaitForChild("Config"):WaitForChild("Abilities"))
local Pose = require(script.Parent:WaitForChild("Pose"))
local Keyframes = require(script.Parent:WaitForChild("AltarOfRuinKeyframes"))
local SlashBlade = require(script.Parent.Parent:WaitForChild("VFX"):WaitForChild("SlashBlade"))

local DEF: Types.AbilityDef = (function()
	for _, def in Abilities do
		if def.Id == "AltarOfRuin" then
			return def
		end
	end
	error("AltarOfRuin is missing from Config/Abilities")
end)()

local CONFIG = {
	CAST = DEF.WindupSeconds or 1.5,
	ALTAR_HEIGHT = 32, -- the stand-in's height (the user's shrine keeps its own size)
	SINK = 1.0, -- seconds to sink at the end
	FLOOR = Color3.fromRGB(70, 4, 14),
	EDGE = Color3.fromRGB(220, 30, 50),
	TINT_IN = 0.6, -- seconds for the red tint to come in / go out
	SLASH_RATE = 42, -- slashes per second across the zone (your screen)
	NEAR_SHARE = 0.65, -- this share lands within NEAR studs of you while you're inside
	NEAR = 26,
	SLASH_LIFE = 0.28,
	POOL = 48,
	TARGET_EVERY = 0.15, -- seconds between cuts on each fighter inside (our own cuts)
	HIT_SCALE = 0.35, -- the user's hit effect on a fighter: size (and particle speed) x this...
	HIT_RATE = 0.35, -- ...and emission rate x this, so it reads on the body without covering it
	HIT_BOX = Vector3.new(4, 5, 4), -- studs: the body-sized box it emits from
	HIT_MAX_RATE = 25, -- per emitter: the dense ones (its shroud and smoke) would hide the enemy at 175/s
	BURST_SCALE = 0.65, -- the user's one-time bursts (fire, glow, shockwave) at this size
	WHOOSH_RATE = 6, -- slash sounds per second near you
	SOUNDS = {
		Rumble = { Id = "rbxassetid://9113221411", Volume = 0.9, Pitch = 0.9 },
		Boom = { Id = "rbxassetid://9120017068", Volume = 1.1, Pitch = 0.85 },
		Loop = { Id = "rbxassetid://9114344093", Volume = 0.55, Pitch = 0.7 },
		Whoosh = { Id = "rbxassetid://9126228629", Volume = 0.32, Pitch = 1.4 },
	},
}

local AltarOfRuinVFX = {}
AltarOfRuinVFX.CONFIG = CONFIG
AltarOfRuinVFX.TimeScale = 1

local player = Players.LocalPlayer

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

local function fxPart(name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	return p
end

local function makeSound(key: string, parent: Instance, looped: boolean?): Sound
	local info = (CONFIG.SOUNDS :: any)[key]
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = info.Id
	sound.Volume = info.Volume
	sound.PlaybackSpeed = info.Pitch * AltarOfRuinVFX.TimeScale
	sound.Looped = looped == true
	sound.RollOffMinDistance = 40
	sound.RollOffMaxDistance = 500
	sound.Parent = parent
	return sound
end

local function oneShot(key: string, at: Vector3, pitch: number?)
	local holder = fxPart(`Sound_{key}`, Vector3.new(0.2, 0.2, 0.2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	holder.CFrame = CFrame.new(at)
	holder.Parent = folder()
	local sound = makeSound(key, holder)
	sound.RollOffMinDistance = 10
	if pitch then
		sound.PlaybackSpeed = pitch * AltarOfRuinVFX.TimeScale
	end
	sound:Play()
	task.delay(8, function()
		holder:Destroy()
	end)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- ReplicatedStorage.VFX.AltarOfRuin.<name> (tools/build_altar_of_ruin_templates), or nil
local function template(name: string): Instance?
	local templates = ReplicatedStorage:FindFirstChild("VFX")
	local source = templates and templates:FindFirstChild("AltarOfRuin")
	return source and source:FindFirstChild(name)
end

-- The user's own sound (template Sounds.<name>) when there is one, otherwise nil (ours from CONFIG.SOUNDS).
local function templateSound(name: string): Sound?
	local sounds = template("Sounds")
	local sound = sounds and sounds:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound:Clone() else nil
end

-- ===== The user's emitters =====

-- multiplies every size keypoint (and its envelope) by k
local function scaleSize(e: ParticleEmitter, k: number)
	local points = {}
	for _, p in e.Size.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	e.Size = NumberSequence.new(points)
end

local function burstCount(e: ParticleEmitter): number
	local n = e:GetAttribute("EmitCount")
	return if type(n) == "number" then n else 5
end

-- The user's hit effect, stuck to a fighter for as long as they stand in the zone: its continuous
-- ("Always") emitters run the whole time, shrunk to HIT_SCALE (size and speed) and HIT_RATE of their
-- rate, emitting from a body-sized box. Its one-time bursts (the big fire / shockwave) are left out.
type Attached = { Part: BasePart, Emitters: { ParticleEmitter } }
local function attachHit(source: BasePart, parent: Instance): Attached
	local hit = source:Clone()
	hit.Size = CONFIG.HIT_BOX
	local on: { ParticleEmitter } = {}
	for _, e in hit:GetDescendants() do
		if e:IsA("ParticleEmitter") then
			e.Enabled = false
			if e:GetAttribute("Always") == true then
				scaleSize(e, CONFIG.HIT_SCALE)
				e.Speed = NumberRange.new(e.Speed.Min * CONFIG.HIT_SCALE, e.Speed.Max * CONFIG.HIT_SCALE)
				e.Rate = math.min(e.Rate * CONFIG.HIT_RATE, CONFIG.HIT_MAX_RATE)
				e.Enabled = true
				table.insert(on, e)
			end
		end
	end
	hit.Parent = parent
	return { Part = hit, Emitters = on }
end

local function detachHit(a: Attached)
	for _, e in a.Emitters do
		e.Enabled = false
	end
	task.delay(1.2, function()
		a.Part:Destroy()
	end)
end

-- ===== Cast =====

function AltarOfRuinVFX.Play(character: Model, _aim: Vector3, isLocal: boolean, options: { PlayAnimation: boolean? }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local r = root :: BasePart
	if isLocal or (options and options.PlayAnimation) then
		local track = Pose.Track(character, "AltarOfRuin", Keyframes, DEF.AnimationId)
		if track then
			track:Play(0.1, 1, AltarOfRuinVFX.TimeScale)
		end
	end
	-- the cast line (the user's sound) from the caster, plus a low rumble under it
	local line = templateSound("Cast")
	if line then
		local holder = fxPart("Sound_Cast", Vector3.new(0.2, 0.2, 0.2), Color3.new(), Enum.Material.SmoothPlastic, 1)
		holder.CFrame = CFrame.new(r.Position)
		holder.Parent = folder()
		line.RollOffMinDistance = 30
		line.RollOffMaxDistance = 400
		line.PlaybackSpeed *= AltarOfRuinVFX.TimeScale
		line.Parent = holder
		line:Play()
		task.delay(12, function()
			holder:Destroy()
		end)
	end
	oneShot("Rumble", r.Position, CONFIG.SOUNDS.Rumble.Pitch)
	local mist = fxPart("AltarCastMist", Vector3.new(10, 0.5, 10), Color3.new(), Enum.Material.SmoothPlastic, 1)
	mist.CFrame = r.CFrame - Vector3.new(0, 2.8, 0)
	mist.Parent = folder()
	local e = emitter(mist, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(30, 2, 8), CONFIG.EDGE),
		LightEmission = 0.25,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 40,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	local light = Instance.new("PointLight")
	light.Color = CONFIG.EDGE
	light.Range = 16
	light.Brightness = 1
	light.Parent = mist
	task.delay(CONFIG.CAST / AltarOfRuinVFX.TimeScale + 0.3, function()
		e.Enabled = false
		light.Enabled = false
		task.delay(1.5, function()
			mist:Destroy()
		end)
	end)
end

-- ===== The altar =====

local function standIn(): Model
	local model = Instance.new("Model")
	model.Name = "AltarStandIn"
	local stone = Color3.fromRGB(40, 32, 34)
	local base = fxPart("Base", Vector3.new(22, 4, 22), stone, Enum.Material.Slate, 0)
	base.CFrame = CFrame.new(0, 2, 0)
	base.Parent = model
	local step = fxPart("Step", Vector3.new(16, 4, 16), stone, Enum.Material.Slate, 0)
	step.CFrame = CFrame.new(0, 6, 0)
	step.Parent = model
	for _, corner in { Vector3.new(6, 0, 6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, -6) } do
		local pillar = fxPart("Pillar", Vector3.new(2.4, 22, 2.4), stone, Enum.Material.Slate, 0)
		pillar.CFrame = CFrame.new(corner + Vector3.new(0, 19, 0))
		pillar.Parent = model
	end
	local roof = fxPart("Roof", Vector3.new(20, 2.5, 20), Color3.fromRGB(60, 10, 16), Enum.Material.Slate, 0)
	roof.CFrame = CFrame.new(0, 31, 0)
	roof.Parent = model
	local core = fxPart("Core", Vector3.new(3, 6, 3), CONFIG.EDGE, Enum.Material.Neon, 0)
	core.CFrame = CFrame.new(0, 12, 0) * CFrame.Angles(0, math.rad(45), 0)
	core.Parent = model
	model.PrimaryPart = base
	return model
end

-- the altar and how tall it stands
local function altarModel(): (Model, number)
	local altar = template("Altar")
	local model: Model
	local own = altar ~= nil and altar:IsA("Model")
	if own then
		model = (altar :: Model):Clone()
	else
		model = standIn()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	-- the user's shrine keeps its own size; the stand-in is scaled to ALTAR_HEIGHT. Pivot at the bottom centre.
	local cf, size = model:GetBoundingBox()
	if not own and size.Y > 0 then
		model:ScaleTo(model:GetScale() * CONFIG.ALTAR_HEIGHT / size.Y)
	end
	cf, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0)) * cf.Rotation
	return model, size.Y
end

-- ===== Domain =====

type Slash = { Blade: SlashBlade.Blade, Born: number, CFrame: CFrame, Life: number }
type Domain = {
	Character: Model,
	Center: CFrame,
	Radius: number,
	ActiveAt: number,
	EndsAt: number,
	Folder: Folder,
	Ending: boolean,
}

local domains: { [Model]: Domain } = {} -- [caster]
local tint: ColorCorrectionEffect? = nil
local tintLevel = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function localInside(): Domain?
	local mine = player.Character
	local root = mine and mine:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for _, d in domains do
		if not d.Ending and now() >= d.ActiveAt - 2 then
			local offset = root.Position - d.Center.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= d.Radius and math.abs(offset.Y) < 40 then
				return d
			end
		end
	end
	return nil
end

local function fighters(): { Model }
	local out: { Model } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged("TrainingDummy") do
		if dummy:IsA("Model") and dummy:IsDescendantOf(workspace) then
			table.insert(out, dummy)
		end
	end
	return out
end

local function randomInDisc(center: Vector3, radius: number): Vector3
	local a = math.random() * math.pi * 2
	local d = radius * math.sqrt(math.random())
	return center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

local function run(d: Domain)
	local center = d.Center
	local radius = d.Radius
	-- the altar
	local altar, height = altarModel()
	local buried = center * CFrame.new(0, -height - 2, 0)
	altar:PivotTo(buried)
	altar.Parent = d.Folder
	local altarLight = Instance.new("PointLight")
	altarLight.Color = CONFIG.EDGE
	altarLight.Range = 40
	altarLight.Brightness = 0
	local anchor = fxPart("AltarAnchor", Vector3.new(14, 1, 14), Color3.new(), Enum.Material.SmoothPlastic, 1)
	anchor.CFrame = center * CFrame.new(0, 2, 0)
	anchor.Parent = d.Folder
	altarLight.Parent = anchor
	local baseSmoke = emitter(anchor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(25, 4, 8)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 12) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 25,
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Shape = Enum.ParticleEmitterShape.Box,
	})

	-- the domain floor: a crimson disc + a glowing edge ring
	local floor = fxPart("DomainFloor", Vector3.new(0.2, 1, 1), CONFIG.FLOOR, Enum.Material.Neon, 1)
	floor.Shape = Enum.PartType.Cylinder
	floor.Parent = d.Folder
	local edge = fxPart("DomainEdge", Vector3.new(1, 0.2, 1), Color3.new(), Enum.Material.SmoothPlastic, 1)
	edge.Parent = d.Folder
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.CanvasSize = Vector2.new(1024, 1024)
	gui.Parent = edge
	local ring = Instance.new("ImageLabel")
	ring.BackgroundTransparency = 1
	ring.Image = "rbxassetid://130368105005697"
	ring.ImageColor3 = CONFIG.EDGE
	ring.Size = UDim2.fromScale(1, 1)
	ring.ImageTransparency = 1
	ring.Parent = gui

	-- ash drifting up across the zone
	local ash = fxPart("DomainAsh", Vector3.new(radius * 1.4, 1, radius * 1.4), Color3.new(), Enum.Material.SmoothPlastic, 1)
	ash.CFrame = center * CFrame.new(0, 1, 0)
	ash.Parent = d.Folder
	local ashEmitter = emitter(ash, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(60, 0, 10)),
		LightEmission = 0.6,
		Size = NumberSequence.new(0.35, 0),
		Lifetime = NumberRange.new(2, 4),
		Rate = 0,
		Speed = NumberRange.new(2, 5),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(20, 20),
		Shape = Enum.ParticleEmitterShape.Box,
	})

	-- the user's slash storm (template SlashField): its emitters fill the whole zone while the slashes run.
	-- With it, our own scattered slashes are left out (cuts on fighters inside stay).
	-- Only the emitters that were on in the user's source run continuously ("Always"); the others are a
	-- one-time burst (fire, glow, shockwave) fired once when the domain opens, at BURST_SCALE size.
	local fieldEmitters: { ParticleEmitter } = {}
	local fieldBursts: { ParticleEmitter } = {}
	local fieldTemplate = template("SlashField")
	if fieldTemplate and fieldTemplate:IsA("BasePart") then
		local field = fieldTemplate:Clone() :: BasePart
		-- keep the height the user gave it (so the particle density matches their look), bottom on the ground
		field.Size = Vector3.new(radius * 2, field.Size.Y, radius * 2)
		field.CFrame = center * CFrame.new(0, field.Size.Y / 2, 0)
		field.Parent = d.Folder
		for _, e in field:GetDescendants() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = false
				if e:GetAttribute("Always") == true then
					table.insert(fieldEmitters, e)
				else
					scaleSize(e, CONFIG.BURST_SCALE)
					table.insert(fieldBursts, e)
				end
			end
		end
	end
	local ownField = #fieldEmitters > 0
	local hitTemplate = template("HitEffect")
	local ownHit = hitTemplate ~= nil and hitTemplate:IsA("BasePart")
	local attached: { [Model]: Attached } = {} -- the user's hit effect on each fighter inside

	-- sounds: a rumble while it rises, then the user's track (template Sounds.Loop) or our loop
	local soundHolder = fxPart("DomainSounds", Vector3.new(0.2, 0.2, 0.2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	soundHolder.CFrame = center * CFrame.new(0, 6, 0)
	soundHolder.Parent = d.Folder
	makeSound("Rumble", soundHolder):Play()
	local loop = templateSound("Loop") or makeSound("Loop", soundHolder, true)
	loop.Parent = soundHolder
	loop.RollOffMinDistance = radius * 0.6
	loop.RollOffMaxDistance = radius * 2.5
	local loopVolume = loop.Volume

	-- slash pool
	local pool: { SlashBlade.Blade } = {}
	local live: { Slash } = {}
	local poolModel = Instance.new("Model")
	poolModel.Name = "Slashes"
	poolModel.Parent = d.Folder
	for _ = 1, CONFIG.POOL do
		local blade = SlashBlade.new(poolModel, 10, 0.6)
		SlashBlade.Shape(blade, 0, 1)
		SlashBlade.Move(blade, CFrame.new(0, -1e4, 0))
		table.insert(pool, blade)
	end
	local function spawnSlash(at: Vector3, length: number)
		local blade = table.remove(pool)
		if not blade then
			return
		end
		blade.Length = length
		blade.Width = 0.45 + math.random() * 0.4
		local camera = workspace.CurrentCamera
		local cf = CFrame.lookAt(at, camera.CFrame.Position) * CFrame.Angles(0, 0, math.random() * math.pi * 2)
		table.insert(live, { Blade = blade, Born = os.clock(), CFrame = cf, Life = CONFIG.SLASH_LIFE * (0.8 + math.random() * 0.4) })
	end

	local boomed = false
	local slashDebt = 0
	local whooshDebt = 0
	local lastTarget: { [Model]: number } = {}
	local endedAt: number? = nil
	local last = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local dt = (os.clock() - last) * AltarOfRuinVFX.TimeScale
		last = os.clock()
		local t = now()
		local riseStart = d.ActiveAt - (DEF.DomainRiseSeconds or 2)
		local rise = math.clamp((t - riseStart) / (d.ActiveAt - riseStart), 0, 1)
		local eased = 1 - (1 - rise) ^ 3
		local active = t >= d.ActiveAt and not d.Ending

		-- the end: sink and fade
		local out = 0
		if d.Ending then
			endedAt = endedAt or os.clock()
			out = math.clamp((os.clock() - (endedAt :: number)) / (CONFIG.SINK / AltarOfRuinVFX.TimeScale), 0, 1)
		end
		local shake = if rise < 1 then math.sin(t * 60) * 0.25 * (1 - rise) else 0
		altar:PivotTo(center * CFrame.new(shake, (-height - 2) * (1 - eased) - (height + 2) * out ^ 2, 0))
		altarLight.Brightness = (if active then 1.4 + 0.3 * math.sin(t * 9) else 1.2 * eased) * (1 - out)

		-- the floor spreads with the rise
		local spread = radius * 2 * math.max(eased, 0.05)
		floor.Size = Vector3.new(0.2, spread, spread)
		floor.CFrame = center * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90))
		floor.Transparency = 0.82 + 0.18 * (1 - eased) + 0.18 * out
		edge.Size = Vector3.new(spread, 0.2, spread)
		edge.CFrame = center * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, t * 0.15, 0)
		ring.ImageTransparency = 0.15 + 0.85 * (1 - eased) + 0.85 * out

		if active and not boomed then
			boomed = true
			oneShot("Boom", center.Position + Vector3.new(0, 8, 0))
			loop:Play()
			ashEmitter.Rate = 60
			for _, e in fieldEmitters do
				e.Enabled = true
			end
			for _, e in fieldBursts do
				e:Emit(burstCount(e))
			end
		end
		if d.Ending then
			ashEmitter.Enabled = false
			baseSmoke.Enabled = false
			for _, e in fieldEmitters do
				e.Enabled = false
			end
			for fighter, a in attached do
				detachHit(a)
				attached[fighter] = nil
			end
			loop.Volume = loopVolume * (1 - out)
		end

		-- slashes
		if active then
			local mine = player.Character
			local myRoot = mine and mine:FindFirstChild("HumanoidRootPart") :: BasePart?
			local inside = localInside() == d and myRoot ~= nil
			slashDebt += if ownField then 0 else CONFIG.SLASH_RATE * dt
			while slashDebt >= 1 do
				slashDebt -= 1
				local at: Vector3
				if inside and myRoot and math.random() < CONFIG.NEAR_SHARE then
					at = randomInDisc(myRoot.Position, CONFIG.NEAR)
					at = Vector3.new(at.X, center.Position.Y + 1 + math.random() * 10, at.Z)
				else
					at = randomInDisc(center.Position, radius) + Vector3.new(0, 1 + math.random() * 14, 0)
				end
				spawnSlash(at, 6 + math.random() * 9)
			end
			-- every fighter inside (not the caster): the user's hit effect stuck to them while inside,
			-- or our own cuts without it
			local insideNow: { [Model]: boolean } = {}
			for _, fighter in fighters() do
				if fighter ~= d.Character then
					local fr = fighter:FindFirstChild("HumanoidRootPart") :: BasePart?
					local fh = fighter:FindFirstChildOfClass("Humanoid")
					if fr and fh and fh.Health > 0 then
						local offset = fr.Position - center.Position
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= (DEF.DomainHeightLimit or 30) then
							insideNow[fighter] = true
							if ownHit then
								local a = attached[fighter]
								if not a then
									a = attachHit(hitTemplate :: BasePart, d.Folder)
									attached[fighter] = a
								end
								(a :: Attached).Part.CFrame = fr.CFrame
							elseif os.clock() - (lastTarget[fighter] or 0) >= CONFIG.TARGET_EVERY / AltarOfRuinVFX.TimeScale then
								lastTarget[fighter] = os.clock()
								spawnSlash(fr.Position + Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.3) * 3, (math.random() - 0.5) * 2), 5 + math.random() * 3)
							end
						end
					end
				end
			end
			for fighter, a in attached do
				if not insideNow[fighter] then
					detachHit(a)
					attached[fighter] = nil
				end
			end
			if inside and myRoot and not ownField then
				whooshDebt += CONFIG.WHOOSH_RATE * dt
				while whooshDebt >= 1 do
					whooshDebt -= 1
					oneShot("Whoosh", randomInDisc(myRoot.Position, 14) + Vector3.new(0, 3, 0), CONFIG.SOUNDS.Whoosh.Pitch * (0.85 + math.random() * 0.4))
				end
			end
		end
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for i = #live, 1, -1 do
			local slash = live[i]
			local age = (os.clock() - slash.Born) * AltarOfRuinVFX.TimeScale
			local grow = math.clamp(age / 0.05, 0, 1)
			local fade = math.clamp((age - slash.Life * 0.35) / (slash.Life * 0.65), 0, 1)
			SlashBlade.Shape(slash.Blade, grow, fade)
			SlashBlade.Collect(slash.Blade, slash.CFrame, parts, cframes)
			if fade >= 1 then
				SlashBlade.Shape(slash.Blade, 0, 1)
				table.insert(pool, slash.Blade)
				table.remove(live, i)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end

		if d.Ending and out >= 1 and #live == 0 then
			conn:Disconnect()
			d.Folder:Destroy()
			if domains[d.Character] == d then
				domains[d.Character] = nil
			end
		end
	end)
end

-- AbilityZone: "Start" (where, how big, when the slashes start and end) and "End".
function AltarOfRuinVFX.Zone(character: Model, phase: string, center: CFrame?, radius: number?, activeAt: number?, endsAt: number?)
	if phase == "Start" and center and radius and activeAt and endsAt then
		local old = domains[character]
		if old then
			old.Ending = true
		end
		local f = Instance.new("Folder")
		f.Name = "AltarOfRuin"
		f.Parent = folder()
		local d: Domain = {
			Character = character,
			Center = center,
			Radius = radius,
			ActiveAt = activeAt,
			EndsAt = endsAt,
			Folder = f,
			Ending = false,
		}
		domains[character] = d
		run(d)
		-- safety: end on time even if the "End" message is lost
		task.delay(math.max(0, endsAt - now()) + 1, function()
			d.Ending = true
		end)
	elseif phase == "End" then
		local d = domains[character]
		if d then
			d.Ending = true
		end
	end
end

-- The red tint for whoever stands inside any domain.
RunService.RenderStepped:Connect(function(dt)
	local inside = localInside()
	local target = if inside and now() >= inside.ActiveAt - (DEF.DomainRiseSeconds or 2) then 1 else 0
	if target == 0 and tintLevel == 0 then
		return
	end
	tintLevel = math.clamp(tintLevel + (if target > tintLevel then dt else -dt) / CONFIG.TINT_IN, 0, 1)
	if not tint or not tint.Parent then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "AltarOfRuinTint"
		cc.Parent = Lighting
		tint = cc
	end
	local cc = tint :: ColorCorrectionEffect
	cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 175, 180), tintLevel)
	cc.Saturation = -0.35 * tintLevel
	cc.Contrast = 0.18 * tintLevel
	cc.Brightness = -0.05 * tintLevel
	if tintLevel == 0 then
		cc:Destroy()
		tint = nil
	end
end)

return AltarOfRuinVFX
