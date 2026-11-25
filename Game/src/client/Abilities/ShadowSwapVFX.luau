--!strict
-- Shadow Swap (Epic, Movement): melt into shadow and reappear behind the nearest enemy (35 studs).
-- No damage and no status (changed with the user): a combo opener, a better Gale Step that finds you.
-- Look: the Shadow Swap reference sheet (12 panels, Hit 0 - Hit +11). Palette deep purple / black /
-- dark violet / magenta. Fast, clean, assassin-like: no explosions or flashy blasts.
--
-- Built the Studio-first way: every visual piece is a template in ReplicatedStorage.VFX.ShadowSwap
-- (Game/tools/build_shadow_swap_templates.luau; textures from build_shadow_swap_textures.py). Tweak
-- them in Studio; this script only clones, places and times them. Movement is layered on purpose
-- (feedback after Frost Bloom: effects must feel alive): flipbook smoke that curls and tears, strands
-- that twist round each other, an afterimage in the shimmering ForceField material, a spinning swirl.
--
-- Timeline (seconds after the key press):
--   0.00 - 0.15  GATHER    crouch; shadow smoke and violet motes rise round the feet, a swirl turns
--   0.15         VANISH    the server moves the caster behind the target; a shimmering afterimage is
--                          left behind and fades, smoke + embers + tearing wisps burst out
--   0.15 - 0.29  RIBBON    1 dark + 2 glowing strands fly an arcing path, twisting round each other,
--                          shedding smoke and embers; the caster is hidden
--   0.29 - 0.55  REFORM    the strands spiral round the landing spot and rise (the materialization swirl);
--                          a dense smoke burst, the ground swirl spins open, a violet flare; the caster
--                          fades back in already in a combat stance
--   ~2.5         cleanup (the ribbon trails and smoke have faded)
--
-- Network: the caster's client predicts everything on the key press (same targeting as the server,
-- shared/Teleport) and moves itself, so it feels instant; the server still decides and moves the
-- caster. Everyone else plays GATHER from AbilityUsed and the rest from AbilityTeleport (from, to).

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
local Teleport = require(Shared:WaitForChild("Teleport"))

local Client = script.Parent.Parent
local Quality = require(Client:WaitForChild("VFX"):WaitForChild("Quality"))
local Pose = require(script.Parent.Pose)

local def: Types.AbilityDef? = nil
for _, ability in Abilities do
	if ability.Id == "ShadowSwap" then
		def = ability
	end
end
assert(def, "ShadowSwap is missing from Shared/Config/Abilities")

local CONFIG = {
	-- Gameplay lives in Shared/Config/Abilities (the server reads it).
	RANGE = def.Range, -- 35
	BEHIND = def.BehindStuds or 3,
	VANISH_AT = def.WindupSeconds or 0.15,
	ANIMATION = def.AnimationId,
	ANIMATION_SPEED = 1.5, -- the generated clip crouches until ~0.45 s; at 1.5x the vanish is mid-crouch
	SKIP_LATE_AFTER = 1.0, -- seconds (server time): an older AbilityTeleport only reveals the caster
	GROUND_DROP = 8,

	GATHER = { SWIRL_FROM = 1.6, SWIRL_TURN_DEG = 220 },
	BURST = { DARK = 14, VIOLET = 8, EMBERS = 18, WISPS = 10 }, -- vanish puff
	REAPPEAR = { DARK = 20, VIOLET = 12, EMBERS = 26, WISPS = 8 }, -- denser puff on arrival
	AFTERIMAGE = {
		COLOR = Color3.fromRGB(150, 70, 255),
		SECONDS = 0.45,
		DRIFT = Vector3.new(0, 0.6, 0), -- floats up a little as it fades
	},
	RIBBON = {
		FLIGHT = 0.14, -- seconds from vanish to the far end
		ARC = 2.4, -- studs the path rises in the middle
		BULGE = 3.0, -- studs it curves sideways
		TWIST_TURNS = 1.6, -- strands wrap round each other this many times along the path
		TWIST_RADIUS = 0.9,
		SWIRL_SECONDS = 0.26, -- then they spiral round the landing spot
		SWIRL_TURNS = 1.1,
		SWIRL_RADIUS = { 2.6, 0.9 }, -- from, to
		SWIRL_RISE = 3.2, -- studs they climb while spiralling
		LINGER = 1.2, -- trails + drifting smoke fade out over this
	},
	REFORM = {
		REVEAL_SECONDS = 0.1, -- caster fades back in
		SWIRL_SIZE = { 2, 7.5 },
		SWIRL_SECONDS = 0.55,
		SWIRL_SPIN_DEG = -300,
		FLARE = { COLOR = Color3.fromRGB(170, 80, 255), BRIGHTNESS = 6, RANGE = 12, SECONDS = 0.35 },
	},
	CLEANUP_AT = 2.5,
}

type Cast = { Folder: Folder, Ended: boolean }

local ShadowSwapVFX = {}
ShadowSwapVFX.CONFIG = CONFIG
-- Playback speed for checking the effect in slow motion (1 = normal). Every time below goes through s().
ShadowSwapVFX.TimeScale = 1
local function s(seconds: number): number
	return seconds / ShadowSwapVFX.TimeScale
end
-- Slow every emitter / trail in a cloned template to the current TimeScale.
local function slowed(inst: Instance)
	if ShadowSwapVFX.TimeScale == 1 then
		return
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.TimeScale = ShadowSwapVFX.TimeScale
		elseif d:IsA("Trail") then
			d.Lifetime /= ShadowSwapVFX.TimeScale
		end
	end
end

local localPlayer = Players.LocalPlayer
-- The caster's own client predicted its teleport: the server's AbilityTeleport only corrects it.
local predicted: { [Model]: number } = {}

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
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("ShadowSwap") :: Folder
end

local function newCast(name: string): Cast
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = folder()
	Debris:AddItem(f, s(CONFIG.CLEANUP_AT) + 1)
	local cast: Cast = { Folder = f, Ended = false }
	task.delay(s(CONFIG.CLEANUP_AT), function()
		cast.Ended = true
		f:Destroy()
	end)
	return cast
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(s(seconds), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function ground(from: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	table.insert(ignore, folder())
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(from, Vector3.new(0, -CONFIG.GROUND_DROP, 0), params)
	return if hit then hit.Position else from - Vector3.new(0, 3, 0)
end

local function scaledCount(n: number): number
	return math.max(1, math.floor(n * (if Quality.Low then 0.5 else 1)))
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

-- Hide / show a character on this client only (LocalTransparencyModifier), fading back in.
local function setHidden(character: Model, hidden: boolean, fadeSeconds: number?)
	local items: { Instance } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(items, d)
		end
	end
	if hidden or not fadeSeconds or fadeSeconds <= 0 then
		for _, d in items do
			(d :: any).LocalTransparencyModifier = if hidden then 1 else 0
		end
		return
	end
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / s(fadeSeconds), 0, 1)
		for _, d in items do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 1 - a
			end
		end
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

local function burst(cast: Cast, at: Vector3, counts: { DARK: number, VIOLET: number, EMBERS: number, WISPS: number })
	local part = templates().Burst:Clone() :: BasePart
	part.CFrame = CFrame.new(at)
	slowed(part)
	part.Parent = cast.Folder
	local function emit(name: string, n: number)
		local e = part:FindFirstChild(name) :: ParticleEmitter?
		if e then
			e:Emit(scaledCount(n))
		end
	end
	emit("DarkSmoke", counts.DARK)
	emit("VioletSmoke", counts.VIOLET)
	emit("Embers", counts.EMBERS)
	emit("Wisps", counts.WISPS)
end

-- A shimmering copy of the body where it stood (ForceField material moves on its own), fading up.
local function afterimage(cast: Cast, character: Model, from: Vector3)
	if Quality.Low then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = from - root.Position -- the body may already have been moved here by the server
	local a = CONFIG.AFTERIMAGE
	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") or part == root or part.Transparency >= 1 then
			continue
		end
		local copy: BasePart
		if part:IsA("MeshPart") then
			local ok, clone = pcall(function()
				return part:Clone()
			end)
			if not ok or not clone then
				continue
			end
			copy = clone
			copy:ClearAllChildren()
			clone.TextureID = "" -- the clothing texture tints ForceField (came out orange, not violet)
		else
			local p = Instance.new("Part")
			p.Size = part.Size
			copy = p
		end
		copy.Name = "Afterimage"
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Material = Enum.Material.ForceField
		copy.Color = a.COLOR
		copy.Transparency = 0
		copy.CFrame = part.CFrame + offset
		copy.Parent = cast.Folder
		tween(copy, a.SECONDS, { Transparency = 1, CFrame = copy.CFrame + a.DRIFT })
	end
end

local function gatherAtFeet(cast: Cast, character: Model, root: BasePart)
	local g = CONFIG.GATHER
	local part = templates().Gather:Clone() :: BasePart
	local full = part.Size
	part.Size = Vector3.new(g.SWIRL_FROM, full.Y, g.SWIRL_FROM)
	part.CFrame = CFrame.new(ground(root.Position, { character }) + Vector3.new(0, 0.08, 0))
	slowed(part)
	part.Parent = cast.Folder
	local img = (part:FindFirstChild("Gui") :: SurfaceGui):FindFirstChild("Image") :: ImageLabel
	local alpha = img.ImageTransparency
	img.ImageTransparency = 1
	tween(part, CONFIG.VANISH_AT, { Size = full }, Enum.EasingStyle.Quint)
	tween(img, CONFIG.VANISH_AT * 0.6, { ImageTransparency = alpha })
	tween(img, CONFIG.VANISH_AT + 0.25, { Rotation = g.SWIRL_TURN_DEG }, Enum.EasingStyle.Linear)
	for _, name in { "Rise", "Motes" } do
		local e = part:FindFirstChild(name) :: ParticleEmitter
		e.Rate *= if Quality.Low then 0.5 else 1
		e.Enabled = true
	end
	task.delay(s(CONFIG.VANISH_AT), function()
		for _, name in { "Rise", "Motes" } do
			local e = part:FindFirstChild(name) :: ParticleEmitter?
			if e then
				e.Enabled = false
			end
		end
		tween(img, 0.25, { ImageTransparency = 1 })
	end)
end

-- The ribbon: strands fly an arcing, twisting path, then spiral round the landing spot and rise.
local function ribbon(cast: Cast, from: Vector3, to: Vector3)
	local r = CONFIG.RIBBON
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local side = forward:Cross(Vector3.yAxis) * (if math.random() < 0.5 then 1 else -1)
	local swirlBase = to - Vector3.new(0, 2, 0) -- spiral from about the feet up

	local specs = { { "StrandDark", 0 }, { "StrandGlow", 2 * math.pi / 3 }, { "StrandGlow", 4 * math.pi / 3 } }
	if Quality.Low then
		specs = { specs[1], specs[2] }
	end
	type Strand = { Part: BasePart, Phase: number }
	local strands: { Strand } = {}
	for _, spec in specs do
		local part = (templates():FindFirstChild(spec[1] :: string) :: BasePart):Clone()
		part.CFrame = CFrame.new(from)
		slowed(part)
		part.Parent = cast.Folder
		local trail = part:FindFirstChild("Trail") :: Trail
		trail.Enabled = true
		for _, e in part:GetChildren() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = true
			end
		end
		table.insert(strands, { Part = part, Phase = spec[2] :: number })
	end

	local function pathPoint(a: number, phase: number): Vector3
		local s = math.sin(math.pi * a)
		local centre = from:Lerp(to, a) + Vector3.yAxis * r.ARC * s + side * r.BULGE * s
		local theta = a * r.TWIST_TURNS * 2 * math.pi + phase
		return centre + (side * math.cos(theta) + Vector3.yAxis * math.sin(theta)) * r.TWIST_RADIUS * s
	end
	local function swirlPoint(b: number, phase: number): Vector3
		local radius = r.SWIRL_RADIUS[1] + (r.SWIRL_RADIUS[2] - r.SWIRL_RADIUS[1]) * b
		local theta = phase + b * r.SWIRL_TURNS * 2 * math.pi
		local enter = math.clamp(b * 6, 0, 1) -- ease in from where the path ended
		local p = swirlBase + Vector3.new(math.cos(theta) * radius, r.SWIRL_RISE * b, math.sin(theta) * radius)
		return to:Lerp(p, enter)
	end

	local start = os.clock()
	local total = r.FLIGHT + r.SWIRL_SECONDS
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if cast.Ended then
			conn:Disconnect()
			return
		end
		local t = (os.clock() - start) * ShadowSwapVFX.TimeScale
		for _, strand in strands do
			local position: Vector3
			if t < r.FLIGHT then
				position = pathPoint(t / r.FLIGHT, strand.Phase)
			else
				position = swirlPoint(math.clamp((t - r.FLIGHT) / r.SWIRL_SECONDS, 0, 1), strand.Phase)
			end
			local previous = strand.Part.Position
			local dir = position - previous
			strand.Part.CFrame = if dir.Magnitude > 0.01 then CFrame.lookAt(position, position + dir) else CFrame.new(position)
		end
		if t >= total then
			conn:Disconnect()
			for _, strand in strands do
				-- Trails stay on: switching a Trail off erases it at once. The strand stops moving, so the
				-- ribbon just fades out over the trail's lifetime.
				for _, e in strand.Part:GetChildren() do
					if e:IsA("ParticleEmitter") then
						e.Enabled = false
					end
				end
			end
		end
	end)
end

local function reform(cast: Cast, character: Model, to: Vector3)
	local f = CONFIG.REFORM
	burst(cast, to, CONFIG.REAPPEAR)
	setHidden(character, false, f.REVEAL_SECONDS)

	local swirl = templates().Swirl:Clone() :: BasePart
	local size = f.SWIRL_SIZE
	swirl.Size = Vector3.new(size[1], swirl.Size.Y, size[1])
	swirl.CFrame = CFrame.new(ground(to + Vector3.new(0, 1, 0), { character }) + Vector3.new(0, 0.1, 0))
	slowed(swirl)
	swirl.Parent = cast.Folder
	local img = (swirl:FindFirstChild("Gui") :: SurfaceGui):FindFirstChild("Image") :: ImageLabel
	tween(swirl, f.SWIRL_SECONDS, { Size = Vector3.new(size[2], swirl.Size.Y, size[2]) }, Enum.EasingStyle.Quart)
	tween(img, f.SWIRL_SECONDS, { Rotation = f.SWIRL_SPIN_DEG }, Enum.EasingStyle.Quart)
	tween(img, f.SWIRL_SECONDS, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local light = Instance.new("PointLight")
		light.Color = f.FLARE.COLOR
		light.Brightness = f.FLARE.BRIGHTNESS
		light.Range = f.FLARE.RANGE
		light.Shadows = false
		light.Parent = root
		tween(light, f.FLARE.SECONDS, { Brightness = 0 })
		Debris:AddItem(light, s(f.FLARE.SECONDS) + 0.1)
	end
end

-- vanish -> ribbon -> reform, starting now. `from` is where the caster stood.
local function teleportEffects(cast: Cast, character: Model, from: Vector3, to: Vector3)
	afterimage(cast, character, from)
	burst(cast, from, CONFIG.BURST)
	setHidden(character, true)
	ribbon(cast, from, to)
	task.delay(s(CONFIG.RIBBON.FLIGHT), function()
		if character.Parent then
			reform(cast, character, to)
		end
	end)
end

-- Can the local player cast it right now? (an enemy within range)
function ShadowSwapVFX.CanUse(character: Model): boolean
	return Teleport.Nearest(character, CONFIG.RANGE) ~= nil
end

-- The target we lock onto, sent to the server with UseAbility; Play() then uses the same one.
local picked: { [Model]: Model } = {}
function ShadowSwapVFX.Pick(character: Model): Model?
	local target = Teleport.Nearest(character, CONFIG.RANGE)
	if target then
		picked[character] = target
	end
	return target
end

-- The key press (caster) or AbilityUsed (everyone else): the crouch + gathering shadows. The caster's
-- own client also predicts the teleport itself at VANISH_AT.
function ShadowSwapVFX.Play(character: Model, _aim: Vector3, isLocal: boolean, options: { PlayAnimation: boolean? }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local cast = newCast(`ShadowSwap_{character.Name}`)

	if isLocal or (options and options.PlayAnimation) then
		local id = animationId()
		local track = if id then Pose.Track(character, "ShadowSwap", {}, id) else nil
		if track then
			track.Looped = false
			track:Play(0.05)
			track:AdjustSpeed(CONFIG.ANIMATION_SPEED * ShadowSwapVFX.TimeScale)
		end
	end

	gatherAtFeet(cast, character, root)

	if not isLocal then
		return
	end
	local target = picked[character] or Teleport.Nearest(character, CONFIG.RANGE)
	picked[character] = nil
	if not target then
		return
	end
	predicted[character] = os.clock()
	task.delay(s(CONFIG.VANISH_AT), function()
		if not root.Parent then
			return
		end
		local landing = Teleport.Behind(character, target, CONFIG.BEHIND)
		if not landing then
			return
		end
		local from = root.Position
		teleportEffects(cast, character, from, landing.Position)
		-- Move ourselves now so it feels instant; the server moves us to the same spot and corrects any drift.
		character:PivotTo(landing)
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

-- The server moved the caster (AbilityTeleport). Others play the vanish -> ribbon -> reform here; the
-- caster's own client already did, unless its prediction never ran (then it plays it now).
function ShadowSwapVFX.Teleport(character: Model, from: Vector3, to: Vector3, _target: Model?, serverTime: number)
	local mine = predicted[character]
	if mine and os.clock() - mine < 1 then
		predicted[character] = nil
		return
	end
	if workspace:GetServerTimeNow() - serverTime > CONFIG.SKIP_LATE_AFTER then
		setHidden(character, false)
		return
	end
	local cast = newCast(`ShadowSwap_{character.Name}_tp`)
	teleportEffects(cast, character, from, to)
end

if localPlayer then
	localPlayer.CharacterRemoving:Connect(function(character)
		predicted[character] = nil
	end)
end

return ShadowSwapVFX
