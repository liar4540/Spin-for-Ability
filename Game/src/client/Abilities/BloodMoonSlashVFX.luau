--!strict
-- Blood Moon Slash (Legendary, Melee), v2: an iaido draw. A katana rides sheathed at the left hip; the
-- right hand reaches across, black flames waver up round the caster while Blood Moon energy gathers,
-- then the blade is drawn in one horizontal cut and a giant dark crimson crescent tears forward 30 studs,
-- piercing every enemy (20 damage, then Bleeding Wound). It stops at walls.
-- Look: images/abilities/blood moon slash.png (12 panels). White-hot edge, deep crimson body with dark
-- veins, a near-black smoky smear, black flames, red sparks and embers. No fire-orange, explosions,
-- lightning, ice or purple. v2 changes (user feedback 2026-11-26): a real katana instead of a glowing
-- rod, a darker / more solid / more detailed slash with black flames and more movement (wavering width,
-- breathing curve, tilt sway, two echo arcs trailing), the cross-body draw, ominous sounds, no drum.
--
-- Built the Studio-first way: templates in ReplicatedStorage.VFX.BloodMoonSlash
-- (Game/tools/build_blood_moon_templates.luau; katana = free Creator Store model 17863301465; textures
-- from build_blood_moon_textures.py; animation = client/Abilities/BloodMoonSlashKeyframes). Tweak the
-- templates in Studio; this script places and times them. The bleed itself (drops, icon) is drawn by
-- client/Controllers/StatusController from the enemy's BleedEndsAt attribute.
--
-- Timeline (seconds after the key press):
--   0.00 - 0.30  REACH    katana + sheath fade in at the left hip; the hand reaches across to the hilt
--   0.05 - 0.78  CHARGE   black flames waver up round the caster, crimson sparks are drawn in, the blade
--                         smoulders with black flame and its light swells; an ominous build ends on the draw
--   0.52         DRAW     the katana leaves the sheath with the hand (eases into the grip); swing trail on
--   0.58         RELEASE  burst at the blade tip, whoosh; the crescent tears out of the cut
--   0.58 - 0.91  FLIGHT   crescent: 5 layers wavering and breathing, 2 echo arcs trailing, black flames
--   0.91 - 1.26  BREAK    it slows, tears apart into black flame, streaks and embers
--   1.50 - 1.80  the katana and sheath burn away in black flame; cleanup ~3.2 s

local Debris = game:GetService("Debris")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
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
	if ability.Id == "BloodMoonSlash" then
		def = ability
	end
end
assert(def, "BloodMoonSlash is missing from Shared/Config/Abilities")

local CONFIG = {
	RELEASE_AT = def.WindupSeconds or 0.58, -- the draw's fastest moment (BloodMoonSlashKeyframes)
	RANGE = def.Range,
	SPEED = def.ProjectileSpeed or 90,
	ANIMATION = def.AnimationId,
	SKIP_LATE_AFTER = 1.0,

	KATANA = {
		SHOW = 0.15, -- fade-in
		DRAW_FROM = 0.52, -- leaves the sheath with the hand
		GRIP_BLEND = 0.07, -- seconds to settle into the drawn grip
		FLAME_FROM = 0.15,
		FLAME_UNTIL = 1.1,
		LIGHT = 2.5,
		FADE_AT = 1.5,
		FADE = 0.3,
	},
	AURA = { FROM = 0.05, UNTIL = 0.78 },
	CRESCENT = {
		START_AHEAD = 2.5,
		HEIGHT = 0.5,
		RADIUS = 16, -- chord 30 at HALF_ANGLE 70
		HALF_ANGLE = { 20, 70 },
		UNFURL = 0.1,
		TILT_DEG = 12,
		-- movement
		WOBBLE = 0.12, -- width flutter (fraction)
		WOBBLE_HZ = 6,
		BREATHE = 0.05, -- radius breathing (fraction)
		SWAY_DEG = 5, -- tilt sway
		BREAK_SECONDS = 0.35,
		BREAK_DRIFT = 12,
		-- name, layers, width scale, radius scale, tilt offset (deg), lag (s), extra transparency
		ARCS = {
			{ "Main", { "Smear", "Body", "Veins", "Core", "Edge" }, 1, 1, 0, 0, 0 },
			{ "Echo1", { "Smear", "Body", "Edge" }, 0.45, 0.88, 9, 0.045, 0.35 },
			{ "Echo2", { "Body", "Edge" }, 0.35, 1.12, -7, 0.09, 0.55 },
		},
	},
	BURST = { FLASH = 1, RING = 0, SPARKS = 30, FLAME = 14, LIGHT = 6, LIGHT_SECONDS = 0.3 }, -- ring read as a pink bubble
	HIT = { CUT = 1, SPARKS = 18, BLOOD = 14 },
	CLEANUP_AT = 3.2,
}

type Cast = { Folder: Folder, Ended: boolean }

local BloodMoonSlashVFX = {}
BloodMoonSlashVFX.CONFIG = CONFIG
BloodMoonSlashVFX.TimeScale = 1 -- slow motion for checking (every time goes through s())
local function s(seconds: number): number
	return seconds / BloodMoonSlashVFX.TimeScale
end
local function slowed(inst: Instance)
	if BloodMoonSlashVFX.TimeScale == 1 then
		return
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.TimeScale = BloodMoonSlashVFX.TimeScale
		elseif d:IsA("Trail") then
			d.Lifetime /= BloodMoonSlashVFX.TimeScale
		elseif d:IsA("Beam") then
			d.TextureSpeed *= BloodMoonSlashVFX.TimeScale
		end
	end
end

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
	return ReplicatedStorage:WaitForChild("VFX"):WaitForChild("BloodMoonSlash") :: Folder
end

local function newCast(name: string): Cast
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = folder()
	local cast: Cast = { Folder = f, Ended = false }
	Debris:AddItem(f, s(CONFIG.CLEANUP_AT) + 1)
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

local function after(seconds: number, fn: () -> ())
	task.delay(s(seconds), fn)
end

local function count(n: number): number
	return math.max(1, math.floor(n * (if Quality.Low then 0.5 else 1)))
end

local function setEmitters(inst: Instance, names: { string }, on: boolean)
	for _, name in names do
		local e = inst:FindFirstChild(name)
		if e and e:IsA("ParticleEmitter") then
			if on then
				e.Rate *= if Quality.Low then 0.5 else 1
			end
			e.Enabled = on
		end
	end
end

-- Sound on a small anchored part. endAt = start part-way in so the sound ENDS then (an ominous build).
local function playSound(cast: Cast, name: string, at: Vector3, endAt: number?)
	local list = templates():FindFirstChild("Sounds")
	local template = list and list:FindFirstChild(name) :: Sound?
	if not template then
		return
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
	sound.PlaybackSpeed *= BloodMoonSlashVFX.TimeScale
	sound.Parent = holder
	if endAt and sound.TimeLength > 0 then
		-- audio seconds that play in `endAt` real seconds at this PlaybackSpeed
		local audio = s(endAt) * sound.PlaybackSpeed
		sound.TimePosition = math.max(0, sound.TimeLength - audio)
	end
	sound:Play()
	Debris:AddItem(holder, 8)
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

-- ===== Katana + sheath =====

type Sword = { Katana: Model, Sheath: Model, Weld: Weld, BladeFx: BasePart, Parts: { BasePart } }

-- Weld every part of a template model to its PrimaryPart, unanchored; returns the visible parts.
local function rig(model: Model): { BasePart }
	local primary = model.PrimaryPart :: BasePart
	local visible: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			if part ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = part
				if part.Transparency < 1 then
					table.insert(visible, part)
				end
			end
		end
	end
	return visible
end

local function weldTo(part0: BasePart, part1: BasePart, c0: CFrame): Weld
	local weld = Instance.new("Weld")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0
	weld.C1 = CFrame.identity
	weld.Parent = part1
	return weld
end

local function mountSword(cast: Cast, character: Model): Sword?
	local torso = character:FindFirstChild("LowerTorso") :: BasePart?
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	if not torso or not hand then
		return nil
	end
	local T = templates()
	local mount = (T:FindFirstChild("SheathMount") :: CFrameValue).Value
	local katana = T.Katana:Clone() :: Model
	local sheath = T.Sheath:Clone() :: Model
	slowed(katana)
	local parts = rig(katana)
	for _, part in rig(sheath) do
		table.insert(parts, part)
	end
	katana:PivotTo(torso.CFrame * mount)
	sheath:PivotTo(torso.CFrame * mount)
	local weld = weldTo(torso, katana.PrimaryPart :: BasePart, mount)
	weldTo(torso, sheath.PrimaryPart :: BasePart, mount)
	katana.Parent = cast.Folder
	sheath.Parent = cast.Folder
	for _, part in parts do
		local target = part.Transparency
		part.Transparency = 1
		tween(part, CONFIG.KATANA.SHOW, { Transparency = target })
	end
	return { Katana = katana, Sheath = sheath, Weld = weld, BladeFx = katana:FindFirstChild("BladeFX") :: BasePart, Parts = parts }
end

-- The katana leaves the sheath with the hand and eases into the drawn grip.
local function drawSword(sword: Sword, character: Model)
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end
	local grip = sword.Katana.PrimaryPart :: BasePart
	local target = (templates():FindFirstChild("HandGrip") :: CFrameValue).Value
	local from = hand.CFrame:ToObjectSpace(grip.CFrame)
	sword.Weld.Part0 = hand
	sword.Weld.C0 = from
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / s(CONFIG.KATANA.GRIP_BLEND), 0, 1)
		a = 1 - (1 - a) ^ 2
		if sword.Weld.Parent then
			sword.Weld.C0 = from:Lerp(target, a)
		end
		if a >= 1 or not sword.Weld.Parent then
			conn:Disconnect()
		end
	end)
	local swing = sword.BladeFx:FindFirstChild("Swing") :: Trail?
	if swing then
		swing.Enabled = true
	end
end

local function chargeSword(sword: Sword)
	local k = CONFIG.KATANA
	local fx = sword.BladeFx
	after(k.FLAME_FROM, function()
		setEmitters(fx, { "BlackFlame", "RedFlame", "Embers" }, true)
		local light = fx:FindFirstChild("Light") :: PointLight?
		if light then
			tween(light, CONFIG.RELEASE_AT - k.FLAME_FROM, { Brightness = k.LIGHT }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	after(k.FLAME_UNTIL, function()
		setEmitters(fx, { "BlackFlame", "RedFlame", "Embers" }, false)
	end)
	after(k.FADE_AT, function()
		local flame = fx:FindFirstChild("BlackFlame") :: ParticleEmitter?
		if flame then
			flame:Emit(count(14)) -- burns away in black flame
		end
		for _, part in sword.Parts do
			tween(part, k.FADE, { Transparency = 1 })
		end
		local light = fx:FindFirstChild("Light") :: PointLight?
		if light then
			tween(light, k.FADE, { Brightness = 0 })
		end
	end)
end

-- ===== Aura =====

local function aura(cast: Cast, root: BasePart)
	local a = CONFIG.AURA
	local part = templates().Aura:Clone() :: BasePart
	slowed(part)
	part.Anchored = false
	part.Massless = true
	part.CFrame = root.CFrame * CFrame.new(0, -2.6, 0)
	weldTo(root, part, CFrame.new(0, -2.6, 0))
	part.Parent = cast.Folder
	after(a.FROM, function()
		setEmitters(part, { "BlackFlame", "RedFlame", "Gather" }, true)
	end)
	after(a.UNTIL, function()
		setEmitters(part, { "BlackFlame", "RedFlame", "Gather" }, false)
	end)
end

-- ===== Crescent =====

type Layer = { Width: number, Behind: number, Points: { Attachment }, Beams: { Beam } }
type Arc = { Layers: { Layer }, RadiusScale: number, Tilt: number, Lag: number, Alpha: number }

local function newLayer(carrier: BasePart, prototypes: Folder, name: string, widthScale: number): Layer
	local prototype = prototypes:FindFirstChild(name) :: Beam
	local layer: Layer = {
		Width = (carrier:GetAttribute(`{name}Width`) :: number? or 4) * widthScale,
		Behind = carrier:GetAttribute(`{name}Behind`) :: number? or 0,
		Points = {},
		Beams = {},
	}
	for i = 1, 3 do
		local a = Instance.new("Attachment")
		a.Parent = carrier
		layer.Points[i] = a
	end
	for i = 1, 2 do
		local beam = prototype:Clone()
		beam.Attachment0 = layer.Points[i]
		beam.Attachment1 = layer.Points[i + 1]
		beam.Enabled = true
		beam.Parent = carrier
		layer.Beams[i] = beam
	end
	return layer
end

local function crescent(cast: Cast, character: Model, origin: Vector3, forward: Vector3)
	local c = CONFIG.CRESCENT
	local wall = workspace:Raycast(origin, forward * CONFIG.RANGE, Projectile.Filters(character).World)
	local travel = if wall then math.max(0, wall.Distance - 0.5) else CONFIG.RANGE
	local flatRight = forward:Cross(Vector3.yAxis)

	local carrier = templates().Crescent:Clone() :: BasePart
	slowed(carrier)
	local prototypes = Instance.new("Folder") -- the Beam prototypes; every arc clones them
	for _, beam in carrier:GetChildren() do
		if beam:IsA("Beam") then
			beam.Parent = prototypes
		end
	end
	carrier.CFrame = CFrame.lookAt(origin, origin + forward)
	carrier.Parent = cast.Folder
	local carrierLight = carrier:FindFirstChild("Light") :: PointLight?
	local lightBrightness = if carrierLight then carrierLight.Brightness else 0

	local arcs: { Arc } = {}
	for index, spec in c.ARCS do
		if Quality.Low and index > 2 then
			break
		end
		local layers: { Layer } = {}
		for _, name in spec[2] :: { string } do
			if not (Quality.Low and name == "Veins") then
				table.insert(layers, newLayer(carrier, prototypes, name, spec[3] :: number))
			end
		end
		table.insert(arcs, {
			Layers = layers,
			RadiusScale = spec[4] :: number,
			Tilt = math.rad(spec[5] :: number),
			Lag = spec[6] :: number,
			Alpha = spec[7] :: number,
		})
	end
	prototypes:Destroy()

	local emitters: { ParticleEmitter } = {}
	for _, e in carrier:GetChildren() do
		if e:IsA("ParticleEmitter") then
			e.Rate *= if Quality.Low then 0.5 else 1
			e.Enabled = true
			table.insert(emitters, e)
		end
	end
	local breakBursts: { [string]: number } = { BlackFlame = 40, Streaks = 30, Embers = 40, RedFlame = 15 }

	local start = os.clock()
	local flight = travel / CONFIG.SPEED
	local broken = false
	local seed = math.random() * 10
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if cast.Ended then
			conn:Disconnect()
			return
		end
		local t = (os.clock() - start) * BloodMoonSlashVFX.TimeScale
		if not broken and t > flight then
			broken = true
			for _, e in emitters do
				e.Enabled = false
				local n = breakBursts[e.Name]
				if n then
					e:Emit(count(n))
				end
			end
		end
		local done = true
		for index, arc in arcs do
			local ta = t - arc.Lag
			local fade, front
			if ta <= 0 then
				fade, front = 1, c.START_AHEAD
			elseif ta <= flight then
				fade, front = 0, c.START_AHEAD + CONFIG.SPEED * ta
			else
				local b = math.clamp((ta - flight) / c.BREAK_SECONDS, 0, 1)
				fade = b
				front = c.START_AHEAD + travel + c.BREAK_DRIFT * (ta - flight) * (1 - b * 0.5)
			end
			if fade < 1 or ta <= 0 then
				done = false
			end
			local unfurl = math.clamp(math.max(ta, 0) / c.UNFURL, 0, 1)
			unfurl = 1 - (1 - unfurl) ^ 3
			local halfAngle = math.rad(c.HALF_ANGLE[1] + (c.HALF_ANGLE[2] - c.HALF_ANGLE[1]) * unfurl)
			local radius = c.RADIUS * arc.RadiusScale * (1 + c.BREATHE * math.sin(t * 17 + seed + index))
			local tilt = math.rad(c.TILT_DEG) + arc.Tilt + math.rad(c.SWAY_DEG) * math.sin(t * 11 + seed * 2 + index)
			local right = flatRight * math.cos(tilt) + Vector3.yAxis * math.sin(tilt)
			local up = right:Cross(forward)
			local lead = origin + forward * front + Vector3.yAxis * c.HEIGHT
			local centre = lead - forward * radius
			local handle = 4 / 3 * math.tan(halfAngle / 4) * radius

			if index == 1 then
				local sag = radius * (1 - math.cos(halfAngle))
				carrier.Size = Vector3.new(2 * radius * math.sin(halfAngle), 3, math.max(1, sag))
				carrier.CFrame = CFrame.fromMatrix(lead - forward * (sag / 2), right, up, -forward)
				if carrierLight then
					carrierLight.Brightness = lightBrightness * (1 - fade)
				end
			end

			local alive = (1 - fade) * (0.7 + 0.3 * unfurl)
			for li, layer in arc.Layers do
				local flutter = 1 + c.WOBBLE * math.sin(2 * math.pi * c.WOBBLE_HZ * t + li * 1.7 + seed)
				local width = layer.Width * alive * flutter
				for i, a in layer.Points do
					local phi = ((i - 1) / 2 - 0.5) * 2 * halfAngle
					local behind = layer.Behind * (1 + fade)
					local position = centre + forward * (radius * math.cos(phi) - behind) + right * (radius * math.sin(phi))
					local tangent = (right * math.cos(phi) - forward * math.sin(phi)).Unit
					a.WorldCFrame = CFrame.fromMatrix(position, tangent, up)
				end
				for i, beam in layer.Beams do
					beam.CurveSize0 = handle
					beam.CurveSize1 = handle -- P2 = Attachment1 - X * CurveSize1 (Roblox docs)
					beam.Width0 = if i == 1 then 0 else width
					beam.Width1 = if i == 1 then width else 0
					beam.Transparency = NumberSequence.new(math.clamp(arc.Alpha + (1 - arc.Alpha) * fade * 1.2, 0, 1))
				end
			end
		end
		if done then
			conn:Disconnect()
			for _, arc in arcs do
				for _, layer in arc.Layers do
					for _, beam in layer.Beams do
						beam.Enabled = false
					end
				end
			end
		end
	end)
end

local function releaseBurst(cast: Cast, at: Vector3)
	local burst = templates().Burst:Clone() :: BasePart
	slowed(burst)
	burst.CFrame = CFrame.new(at)
	burst.Parent = cast.Folder
	local b = CONFIG.BURST
	for name, n in { Flash = b.FLASH, Ring = b.RING, Sparks = count(b.SPARKS), BlackFlame = count(b.FLAME) } do
		local e = burst:FindFirstChild(name) :: ParticleEmitter?
		if e and n > 0 then
			e:Emit(n)
		end
	end
	local light = burst:FindFirstChild("Light") :: PointLight?
	if light then
		light.Brightness = b.LIGHT
		tween(light, b.LIGHT_SECONDS, { Brightness = 0 })
	end
end

-- Play the slash on a character. Every client runs this for every player who uses it.
function BloodMoonSlashVFX.Play(character: Model, aim: Vector3, isLocal: boolean, options: { PlayAnimation: boolean? }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local cast = newCast(`BloodMoonSlash_{character.Name}`)
	if isLocal or (options and options.PlayAnimation) then
		local id = animationId()
		local track = if id then Pose.Track(character, "BloodMoonSlash", {}, id) else nil
		if track then
			track.Looped = false
			track:Play(0.08)
			track:AdjustSpeed(BloodMoonSlashVFX.TimeScale)
		end
	end
	playSound(cast, "Charge", root.Position, CONFIG.RELEASE_AT)

	local sword = mountSword(cast, character)
	if sword then
		chargeSword(sword)
	end
	aura(cast, root)

	after(CONFIG.KATANA.DRAW_FROM, function()
		if sword and character.Parent then
			drawSword(sword, character)
		end
		playSound(cast, "Draw", root.Position)
	end)

	after(CONFIG.RELEASE_AT, function()
		if not root.Parent then
			return
		end
		local flat = Vector3.new(aim.X, 0, aim.Z)
		local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local tip = sword and sword.BladeFx:FindFirstChild("Tip") :: Attachment?
		releaseBurst(cast, if tip then tip.WorldPosition else root.Position + forward * 2)
		playSound(cast, "Whoosh", root.Position + forward * 4)
		crescent(cast, character, root.Position, forward)
	end)
end

-- The server says the crescent hit these enemies (AbilityImpact): cut flash, sparks, a spray of blood
-- and the cut sound. The bleed that follows is StatusController's (from the BleedEndsAt attribute).
function BloodMoonSlashVFX.Impact(_attacker: Model, hits: { { Target: Model, Position: Vector3 } }, serverTime: number?)
	local age = if serverTime then math.max(0, workspace:GetServerTimeNow() - serverTime) else 0
	if age > CONFIG.SKIP_LATE_AFTER then
		return
	end
	local cast = newCast("BloodMoonSlash_Hit")
	for _, hit in hits do
		local target = hit.Target
		local root = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local cut = templates().HitCut:Clone() :: BasePart
		slowed(cut)
		cut.CFrame = root.CFrame
		cut.Parent = cast.Folder
		for name, n in { Cut = CONFIG.HIT.CUT, Sparks = count(CONFIG.HIT.SPARKS), Blood = count(CONFIG.HIT.BLOOD) } do
			local e = cut:FindFirstChild(name) :: ParticleEmitter?
			if e then
				e:Emit(n)
			end
		end
		playSound(cast, "Hit", root.Position)
	end
end

return BloodMoonSlashVFX
