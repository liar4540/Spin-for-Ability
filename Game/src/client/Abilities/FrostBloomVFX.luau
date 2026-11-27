--!strict
-- Frost Bloom (Epic, AoE): a frost rune under the caster, a crystal lotus blooms out of the ground,
-- cold mist spreads over the 18-stud circle, everyone inside is chilled (slowed) at full bloom.
-- Look: the Frost Bloom reference sheet (12 panels, Hit 0 - Hit +11). Palette pale cyan / ice blue /
-- white / crystal blue. Calm and magical: no explosions, spikes, storms, lightning or fire.
--
-- Built the Studio-first way: every visual piece is a template in ReplicatedStorage.VFX.FrostBloom
-- (built by Game/tools/build_frost_bloom_templates.luau, textures by
-- Game/assets/vfx/_src/build_frost_bloom_textures.py). Tweak colours, sizes and particles there in
-- Studio; this script only clones, places and times them. The cast animation was made with the Studio
-- MCP's generate_animation (ServerStorage.RBX_ASSISTANT_ANIMGEN), uploaded as CONFIG.ANIMATION.
--
-- Timeline (seconds after the key press, at TIME_SCALE 1):
--   0.0 - 0.6  GATHER   rune fades in and grows under the caster, slowly turning; light streaks and
--                       sparkles rise from the circle; the caster lowers a hand (animation)
--   0.6        ACTIVATE rune flashes, cold mist starts rolling over the circle
--   0.6 - 1.0  BLOOM    22 crystal petals rise out of the ground and open outward (core, inner, outer)
--   1.0        FULL     the hit (server, WindupSeconds): icy pulse ring sweeps out to the edge, sparkles
--   1.0 - 2.3  HOLD     the flower turns very slowly, mist and motes drift
--   2.3 - 3.3  DISSOLVE petals fade and sink, the rune fades, the bloom breaks into falling snowflakes
--   ~6         cleanup (the last mist puffs have faded)
-- On every target the server hit (AbilityImpact): a frost coat (Highlight) and icy particles at the
-- feet for the slow's 3 s.
--
-- Network: the caster's client plays it on the key press; every other client from AbilityUsed. The
-- server decides the hit and tells everyone (AbilityImpact); impacts older than SKIP_LATE_AFTER are
-- skipped. Budget per cast (full quality): 22 petals (~130 small parts, moved with one BulkMoveTo per
-- frame), 3 flat SurfaceGuis, 1 light, 1 Highlight, 4 emitters. Low quality: 8 petals, half the particles.

local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Config:WaitForChild("Abilities"))
local Rarities = require(Config:WaitForChild("Rarities"))

local Client = script.Parent.Parent
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))
local Pose = require(script.Parent.Pose)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "FrostBloom" then
		def = ability
	end
end
assert(def, "FrostBloom is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Gameplay lives in Shared/Config/Abilities (the server reads it); copied here to read in one place.
	DAMAGE = def.Damage * Rarities.Defs[def.Rarity].Power, -- 20
	RADIUS = def.Range, -- 18
	FULL_BLOOM = def.WindupSeconds or 1.0, -- the hit
	SLOW_SECONDS = def.SlowSeconds or 3,

	-- The cast animation, made with the Studio MCP's generate_animation (1.57 s). In Studio the
	-- KeyframeSequence template VFX.FrostBloom.CastAnimation plays (edit it there and it shows at once);
	-- the live game plays the uploaded AnimationId (the experience needs access to that asset).
	ANIMATION = def.AnimationId,
	TIME_SCALE = 1, -- playback speed; every duration is divided by it
	SKIP_LATE_AFTER = 2.0, -- seconds (server time) after the hit: older AbilityImpact events are skipped
	GROUND_DROP = 8, -- studs searched below the root for the ground (same as the server)

	GATHER = {
		RUNE_FROM = 0.55, -- x full size when it appears
		RUNE_TURN_DEG = 25, -- turned during the gather
		STREAKS_FROM = 0.2,
		STREAKS_TO = 0.75,
		STREAK_RATE = 32,
		LIGHT = 1.5,
	},
	ACTIVATE_AT = 0.6,
	BLOOM = {
		-- name, count, base radius (studs from the centre), open tilt (deg from upright), yaw offset (deg)
		RINGS = {
			{ "PetalCore", 6, 1.2, 18, 0 },
			{ "PetalInner", 8, 1.8, 30, 22.5 },
			{ "PetalOuter", 8, 2.6, 55, 0 },
		},
		STAGGER = 0.05, -- each ring starts this much after the previous one (core first)
		SECONDS = 0.4, -- rise + open, ends at FULL_BLOOM
		SINK = 0.9, -- x petal length below the ground at the start
	},
	FULL = {
		PULSE_SECONDS = 0.55,
		PULSE_TO = 38, -- studs across: just past the circle's edge
		MOTE_BURST = 30,
		MIST_BURST = 20,
		LIGHT_PEAK = 5,
		LIGHT_HOLD = 2,
	},
	HOLD = {
		FLOWER_TURN_DEG_PER_S = 8,
		RUNE_TURN_DEG_PER_S = 6,
	},
	DISSOLVE_AT = 2.3,
	DISSOLVE = {
		SECONDS = 1.0,
		SINK = 0.6, -- studs
		FLAKE_BURST = 60,
		FLAKE_RATE = 40,
		FLAKE_SECONDS = 0.6,
	},
	CLEANUP_AT = 6.0,
	HIGHLIGHT = {
		FILL = Color3.fromRGB(190, 235, 255),
		FILL_T = 0.6,
		OUTLINE = Color3.fromRGB(150, 225, 255),
	},
	CHILL = {
		FILL = Color3.fromRGB(205, 240, 255),
		FILL_T = 0.72,
		OUTLINE_T = 0.55,
		FEET_RATE = 8,
	},
}

type Petal = { Parts: { BasePart }, Offsets: { CFrame }, Base: { number }, Yaw: number, Radius: number, Tilt: number, Length: number, Start: number }
type Cast = { Folder: Folder, TimeScale: number, Ended: boolean, Connections: { RBXScriptConnection }, Extras: { Instance } }

local FrostBloomVFX = {}
FrostBloomVFX.CONFIG = CONFIG

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
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("FrostBloom") :: Folder
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

local function endCast(cast: Cast)
	if cast.Ended then
		return
	end
	cast.Ended = true
	for _, c in cast.Connections do
		c:Disconnect()
	end
	for _, extra in cast.Extras do
		extra:Destroy()
	end
	cast.Folder:Destroy()
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function easeOut(a: number): number -- quint out
	local inv = 1 - math.clamp(a, 0, 1)
	return 1 - inv * inv * inv * inv * inv
end

local function groundUnder(character: Model, root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder() }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.GROUND_DROP, 0), params)
	return if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
end

-- Clone a petal template and remember each part's offset from its pivot (so a whole petal moves with
-- one CFrame, and all petals with one BulkMoveTo per frame).
local function newPetal(cast: Cast, name: string, yaw: number, radius: number, tilt: number, start: number): Petal?
	local template = templates():FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	local pivot = model:GetPivot()
	local petal: Petal = {
		Parts = {},
		Offsets = {},
		Base = {},
		Yaw = yaw,
		Radius = radius,
		Tilt = tilt,
		Length = (model:GetAttribute("Length") :: number?) or 5,
		Start = start,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Base" then
			table.insert(petal.Parts, part)
			table.insert(petal.Offsets, pivot:ToObjectSpace(part.CFrame))
			table.insert(petal.Base, part.Transparency)
		end
	end
	model.Parent = cast.Folder
	return petal
end

-- Play the bloom on a character. Every client runs this for every player who casts it.
function FrostBloomVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: { TimeScale: number?, PlayAnimation: boolean? }?)
	local timeScale = options and options.TimeScale or CONFIG.TIME_SCALE
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local function s(seconds: number): number
		return seconds / timeScale
	end
	local low = Quality.Low
	local T = templates()

	local f = Instance.new("Folder")
	f.Name = `FrostBloom_{character.Name}`
	f.Parent = folder()
	local cast: Cast = { Folder = f, TimeScale = timeScale, Ended = false, Connections = {}, Extras = {} }
	Debris:AddItem(f, s(CONFIG.CLEANUP_AT) + 2) -- backstop

	if isLocal or (options and options.PlayAnimation) then
		local id = animationId()
		local track = if id then Pose.Track(character, "FrostBloom", {}, id) else nil
		if track then
			track.Looped = false
			track:Play(0.1)
			track:AdjustSpeed(timeScale)
		end
	end

	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local ground = groundUnder(character, root)
	local center = CFrame.lookAt(ground, ground + flat)

	-- Rune (the AoE circle)
	local rune = T.Rune:Clone() :: BasePart
	local runeGui = rune:FindFirstChild("Gui") :: SurfaceGui
	local runeImg = runeGui:FindFirstChild("Rune") :: ImageLabel
	local runeGlow = runeGui:FindFirstChild("Glow") :: ImageLabel
	local light = rune:FindFirstChild("Light") :: PointLight
	local fullSize = rune.Size
	local runeAlpha, glowAlpha = runeImg.ImageTransparency, runeGlow.ImageTransparency
	runeImg.ImageTransparency, runeGlow.ImageTransparency = 1, 1
	local g = CONFIG.GATHER
	rune.Size = Vector3.new(fullSize.X * g.RUNE_FROM, fullSize.Y, fullSize.Z * g.RUNE_FROM)
	rune.CFrame = center + Vector3.new(0, 0.06, 0)
	rune.Parent = f
	tween(rune, s(CONFIG.ACTIVATE_AT), { Size = fullSize }, Enum.EasingStyle.Quint)
	tween(runeImg, s(CONFIG.ACTIVATE_AT), { ImageTransparency = runeAlpha + 0.2 })
	tween(runeGlow, s(CONFIG.ACTIVATE_AT), { ImageTransparency = glowAlpha + 0.15 })
	tween(light, s(CONFIG.ACTIVATE_AT), { Brightness = g.LIGHT })

	-- Ground emitters
	local mist = T.Mist:Clone() :: BasePart
	mist.CFrame = center + Vector3.new(0, 0.3, 0)
	mist.Parent = f
	local mistE = mist:FindFirstChild("Mist") :: ParticleEmitter
	local motes = mist:FindFirstChild("Motes") :: ParticleEmitter
	local streaks = mist:FindFirstChild("Streaks") :: ParticleEmitter
	local flakes = mist:FindFirstChild("Flakes") :: ParticleEmitter
	local rateScale = if low then 0.5 else 1
	for _, e in { mistE, motes, streaks, flakes } do
		e.TimeScale = timeScale
	end
	local mistRate, moteRate = mistE.Rate * rateScale, motes.Rate * rateScale
	motes.Rate = moteRate
	motes.Enabled = true
	streaks.Rate = g.STREAK_RATE * rateScale

	-- Petals (rise out of the ground and open)
	local petals: { Petal } = {}
	local b = CONFIG.BLOOM
	for ringIndex, ring in b.RINGS do
		local name, count, radius, tilt, yawOffset = ring[1] :: string, ring[2] :: number, ring[3] :: number, ring[4] :: number, ring[5] :: number
		if low and name ~= "PetalOuter" then
			continue
		end
		local start = CONFIG.ACTIVATE_AT + (ringIndex - 1) * b.STAGGER
		for i = 0, count - 1 do
			local petal = newPetal(cast, name, math.rad(yawOffset + i * 360 / count), radius, math.rad(tilt), start)
			if petal then
				table.insert(petals, petal)
			end
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = CONFIG.HIGHLIGHT.FILL
	highlight.OutlineColor = CONFIG.HIGHLIGHT.OUTLINE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = f
	highlight.Parent = f

	local parts: { BasePart } = {}
	for _, petal in petals do
		for _, part in petal.Parts do
			table.insert(parts, part)
		end
	end
	local cframes: { CFrame } = table.create(#parts)

	local startedAt = os.clock()
	local fired = { activate = false, full = false, dissolve = false, streaksOff = false, streaksOn = false }
	local d = CONFIG.DISSOLVE
	local h = CONFIG.HOLD
	local step: RBXScriptConnection
	step = RunService.RenderStepped:Connect(function()
		if cast.Ended or not f.Parent then
			step:Disconnect()
			return
		end
		local t = (os.clock() - startedAt) * timeScale

		-- rune turn
		local runeTurn = math.rad(g.RUNE_TURN_DEG) * easeOut(t / CONFIG.ACTIVATE_AT) + math.rad(h.RUNE_TURN_DEG_PER_S) * math.max(0, t - CONFIG.ACTIVATE_AT)
		rune.CFrame = center * CFrame.Angles(0, runeTurn, 0) + Vector3.new(0, 0.06, 0)

		-- events
		if not fired.streaksOn and t >= g.STREAKS_FROM then
			fired.streaksOn = true
			streaks.Enabled = true
		end
		if not fired.streaksOff and t >= g.STREAKS_TO then
			fired.streaksOff = true
			streaks.Enabled = false
		end
		if not fired.activate and t >= CONFIG.ACTIVATE_AT then
			fired.activate = true
			runeImg.ImageTransparency = runeAlpha
			runeGlow.ImageTransparency = glowAlpha
			runeGui.Brightness = 5
			tween(runeGui, s(0.5), { Brightness = 2.5 })
			mistE.Rate = mistRate
			mistE.Enabled = true
			tween(highlight, s(b.SECONDS), { FillTransparency = CONFIG.HIGHLIGHT.FILL_T, OutlineTransparency = 0 })
		end
		if not fired.full and t >= CONFIG.FULL_BLOOM then
			fired.full = true
			local full = CONFIG.FULL
			local pulse = T.Pulse:Clone() :: BasePart
			local ring = (pulse:FindFirstChild("Gui") :: SurfaceGui):FindFirstChild("Ring") :: ImageLabel
			pulse.CFrame = center + Vector3.new(0, 0.12, 0)
			pulse.Parent = f
			tween(pulse, s(full.PULSE_SECONDS), { Size = Vector3.new(full.PULSE_TO, pulse.Size.Y, full.PULSE_TO) }, Enum.EasingStyle.Quart)
			tween(ring, s(full.PULSE_SECONDS), { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			motes:Emit(math.floor(full.MOTE_BURST * rateScale))
			mistE:Emit(math.floor(full.MIST_BURST * rateScale))
			light.Brightness = full.LIGHT_PEAK
			tween(light, s(0.6), { Brightness = full.LIGHT_HOLD })
			highlight.FillTransparency = 0.35
			tween(highlight, s(0.4), { FillTransparency = CONFIG.HIGHLIGHT.FILL_T })
		end
		if not fired.dissolve and t >= CONFIG.DISSOLVE_AT then
			fired.dissolve = true
			mistE.Enabled = false
			motes.Enabled = false
			flakes.Rate = d.FLAKE_RATE * rateScale
			flakes.Enabled = true
			flakes:Emit(math.floor(d.FLAKE_BURST * rateScale))
			task.delay(s(d.FLAKE_SECONDS), function()
				flakes.Enabled = false
			end)
			tween(runeImg, s(d.SECONDS + 0.1), { ImageTransparency = 1 })
			tween(runeGlow, s(d.SECONDS), { ImageTransparency = 1 })
			tween(light, s(d.SECONDS), { Brightness = 0 })
			tween(highlight, s(d.SECONDS * 0.8), { FillTransparency = 1, OutlineTransparency = 1 })
		end

		-- petals: rise + open, slow turn, then fade + sink
		local spin = math.rad(h.FLOWER_TURN_DEG_PER_S) * math.max(0, t - CONFIG.FULL_BLOOM)
		local fade = math.clamp((t - CONFIG.DISSOLVE_AT) / d.SECONDS, 0, 1)
		local n = 0
		for _, petal in petals do
			local a = easeOut((t - petal.Start) / b.SECONDS)
			local y = -petal.Length * b.SINK * (1 - a) - d.SINK * fade
			local tilt = petal.Tilt * a
			local pivot = center * CFrame.Angles(0, petal.Yaw + spin, 0) * CFrame.new(0, y, petal.Radius) * CFrame.Angles(tilt, 0, 0)
			for i, part in petal.Parts do
				n += 1
				cframes[n] = pivot * petal.Offsets[i]
				if fade > 0 then
					part.Transparency = petal.Base[i] + (1 - petal.Base[i]) * fade
				end
			end
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		if t >= CONFIG.DISSOLVE_AT + d.SECONDS then
			for _, part in parts do
				part:Destroy()
			end
			table.clear(parts)
			table.clear(petals)
			step:Disconnect()
		end
	end)
	table.insert(cast.Connections, step) -- the bloom stays where it was cast, even if the caster dies
	task.delay(s(CONFIG.CLEANUP_AT), function()
		endCast(cast)
	end)
end

-- Frozen Chill on every target the server hit: a frost coat and icy particles at the feet for the
-- slow's duration (what is left of it, if this event arrived late).
function FrostBloomVFX.Impact(_attacker: Model, hits: { { Target: Model, Position: Vector3 } }, serverTime: number?)
	local age = if serverTime then math.max(0, workspace:GetServerTimeNow() - serverTime) else 0
	if age > CONFIG.SKIP_LATE_AFTER then
		return
	end
	local remaining = CONFIG.SLOW_SECONDS - age
	local T = templates()
	local c = CONFIG.CHILL
	for _, hit in hits do
		local target = hit.Target
		local root = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not target or not root then
			continue
		end
		-- one chill at a time per target (a new hit refreshes it)
		local old = target:FindFirstChild("FrostBloomChill")
		if old then
			old:Destroy()
		end
		local chill = Instance.new("Folder")
		chill.Name = "FrostBloomChill"
		chill.Parent = target

		local coat = Instance.new("Highlight")
		coat.FillColor = c.FILL
		coat.OutlineColor = CONFIG.HIGHLIGHT.OUTLINE
		coat.FillTransparency = 0.3
		coat.OutlineTransparency = c.OUTLINE_T
		coat.DepthMode = Enum.HighlightDepthMode.Occluded
		coat.Adornee = target
		coat.Parent = chill
		tween(coat, 0.35, { FillTransparency = c.FILL_T })

		local feet = Instance.new("Attachment")
		feet.Name = "FrostBloomFeet"
		feet.Position = Vector3.new(0, -root.Size.Y / 2 - 2.2, 0)
		feet.Parent = root
		local mistTemplate = T.Mist
		for _, name in { "Flakes", "Motes" } do
			local e = (mistTemplate:FindFirstChild(name) :: ParticleEmitter):Clone()
			e.Shape = Enum.ParticleEmitterShape.Box
			e.Rate = c.FEET_RATE * (if Quality.Low then 0.5 else 1)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Acceleration = Vector3.new(0, 0.6, 0)
			e.Lifetime = NumberRange.new(0.8, 1.4)
			e.Enabled = true
			e.Parent = feet
			e:Emit(6)
		end
		Debris:AddItem(feet, remaining + 1.5)

		task.delay(math.max(0, remaining - 0.4), function()
			if coat.Parent then
				tween(coat, 0.4, { FillTransparency = 1, OutlineTransparency = 1 })
			end
			for _, e in feet:GetChildren() do
				if e:IsA("ParticleEmitter") then
					e.Enabled = false
				end
			end
			task.delay(0.45, function()
				chill:Destroy()
			end)
		end)
	end
end

return FrostBloomVFX
