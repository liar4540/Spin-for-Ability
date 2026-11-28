--!strict
-- SeverVFX: the Sever ability (Ascended). Shared/Config/Abilities "Sever" holds the gameplay numbers.
--
-- Timeline (seconds from the key press):
--   0    - 1.1   HAND SIGNS  the caster weaves signs (SeverKeyframes) and turns with the camera (own client);
--                            a dark crimson aura boils off them, crackling white sparks, a pulsing ground ring
--   1.1  - 1.35  LOCK        the aim is fixed; the aura tightens
--   1.35         RELEASE     the server sends the direction it read from the caster's facing (AbilityLaunch):
--                            impact frame (one black-and-white flash) + shake for anyone close, a # grid of
--                            black blades with white-hot edges tears forward at 300 studs/s (Range 120, stops
--                            at walls), leaving cut scars on the ground
--   +0.4  +0.75  FADE        the grid thins out at the end of its path; scars linger ~2.5 s
-- Hits (AbilityImpact): a crossed slash flashes on each enemy struck, with a hit sound.
-- No templates: everything is built here from parts and Roblox's default particle textures.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Projectile = require(Shared:WaitForChild("Projectile"))
local Types = require(Shared:WaitForChild("Types"))
local Abilities = require(Shared:WaitForChild("Config"):WaitForChild("Abilities"))
local Pose = require(script.Parent:WaitForChild("Pose"))
local Keyframes = require(script.Parent:WaitForChild("SeverKeyframes"))
local SlashBlade = require(script.Parent.Parent:WaitForChild("VFX"):WaitForChild("SlashBlade"))

local DEF: Types.AbilityDef = (function()
	for _, def in Abilities do
		if def.Id == "Sever" then
			return def
		end
	end
	error("Sever is missing from Config/Abilities")
end)()

local CONFIG = {
	TRACK = DEF.AimTrackSeconds or 1.1,
	RELEASE = DEF.WindupSeconds or 1.35,
	RANGE = DEF.Range,
	WIDTH = DEF.CrescentWidth or 40,
	HEIGHT = DEF.CrescentHeight or 30,
	SPEED = DEF.ProjectileSpeed or 300,
	GROUND = 3, -- root to feet
	VERTICAL = 6, -- blades running up and down
	HORIZONTAL = 4, -- blades running side to side
	BLADE_WIDTH = 1.5, -- studs across a blade's middle
	GROW = 0.08, -- the grid snaps open this fast after the release
	FADE = 0.35,
	SCAR_SECONDS = 2.5,
	FLASH = 0.08, -- impact frame length
	FLASH_RANGE = 250, -- studs: players this close get the impact frame and shake
	AURA = Color3.fromRGB(120, 8, 22),
	SOUNDS = {
		Charge = { Id = "rbxassetid://1837834352", Volume = 0.7, Pitch = 1.1 },
		Release = { Id = "rbxassetid://9126228629", Volume = 1.2, Pitch = 0.72 },
		Crack = { Id = "rbxassetid://9120017068", Volume = 0.8, Pitch = 1.3 },
		Hit = { Id = "rbxassetid://108257794693139", Volume = 0.75, Pitch = 0.9 },
	},
}

local SeverVFX = {}
SeverVFX.CONFIG = CONFIG
SeverVFX.TimeScale = 1 -- slow motion for checking

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

local function s(seconds: number): number
	return seconds / SeverVFX.TimeScale
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

local function playSound(key: string, at: Vector3, endAt: number?)
	local info = (CONFIG.SOUNDS :: any)[key]
	if not info then
		return
	end
	local holder = fxPart(`Sound_{key}`, Vector3.new(0.2, 0.2, 0.2), Color3.new(), Enum.Material.SmoothPlastic, 1)
	holder.CFrame = CFrame.new(at)
	holder.Parent = folder()
	local sound = Instance.new("Sound")
	sound.SoundId = info.Id
	sound.Volume = info.Volume
	sound.PlaybackSpeed = info.Pitch * SeverVFX.TimeScale
	sound.RollOffMaxDistance = 400
	sound.Parent = holder
	if endAt then
		-- start part-way in so the build ENDS at the release
		task.spawn(function()
			if not sound.IsLoaded then
				sound.Loaded:Wait()
			end
			local audio = s(endAt) * sound.PlaybackSpeed
			sound.TimePosition = math.max(0, sound.TimeLength - audio)
			sound:Play()
		end)
	else
		sound:Play()
	end
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

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

-- ===== Hand signs: aura on the caster =====

local function aura(root: BasePart): (Attachment, { ParticleEmitter }, PointLight)
	local att = Instance.new("Attachment")
	att.Name = "SeverAura"
	att.Parent = root
	local smoke = emitter(att, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(20, 4, 8), CONFIG.AURA),
		LightEmission = 0.2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.0),
		Rate = 45,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	local wisps = emitter(att, {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(200, 20, 40), Color3.fromRGB(40, 0, 8)),
		LightEmission = 0.45,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.4, 0.7),
		Rate = 35,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 2,
	})
	local sparks = emitter(att, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 240)),
		LightEmission = 1,
		Size = seq(0.35, 0),
		Lifetime = NumberRange.new(0.15, 0.3),
		Rate = 30,
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 40, 60)
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = att
	return att, { smoke, wisps, sparks }, light
end

local function groundBelow(at: Vector3, character: Model): Vector3
	local hit = workspace:Raycast(at, Vector3.new(0, -12, 0), Projectile.Filters(character).World)
	return if hit then hit.Position else at - Vector3.new(0, CONFIG.GROUND, 0)
end

function SeverVFX.Play(character: Model, _aim: Vector3, isLocal: boolean, options: { PlayAnimation: boolean? }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local r = root :: BasePart
	if isLocal or (options and options.PlayAnimation) then
		local track = Pose.Track(character, "Sever", Keyframes, DEF.AnimationId)
		if track then
			track:Play(0.08, 1, SeverVFX.TimeScale)
		end
	end
	playSound("Charge", r.Position, CONFIG.RELEASE)

	local att, emitters, light = aura(r)
	-- a ring on the ground that tightens as the signs finish
	local ring = fxPart("SeverRing", Vector3.new(0.1, 14, 14), CONFIG.AURA, Enum.Material.Neon, 0.6)
	ring.Shape = Enum.PartType.Cylinder
	ring.Parent = folder()
	local feet = groundBelow(r.Position, character)

	local start = os.clock()
	local conn: RBXScriptConnection
	local function finish()
		conn:Disconnect()
		for _, e in emitters do
			e.Enabled = false
		end
		light.Enabled = false
		ring:Destroy()
		task.delay(1.2, function()
			att:Destroy()
		end)
	end
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) * SeverVFX.TimeScale
		local state = character:GetAttribute("CombatState")
		-- interrupted (stunned, ragdolled...) during the hand signs: the server cancelled the cast
		local cancelled = t > 0.35 and t < CONFIG.RELEASE and state ~= "Casting"
		if t >= CONFIG.RELEASE or cancelled or not r.Parent then
			finish()
			return
		end
		if isLocal and t < CONFIG.TRACK then
			-- the caster turns with the camera until the aim locks (the server reads this facing)
			local camera = workspace.CurrentCamera
			local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			if look.Magnitude > 0.01 then
				r.CFrame = CFrame.lookAt(r.Position, r.Position + look.Unit)
			end
		end
		local k = math.clamp(t / CONFIG.RELEASE, 0, 1)
		local locked = t >= CONFIG.TRACK
		light.Brightness = (0.6 + 0.6 * k) * (1 + 0.25 * math.sin(t * 30))
		local d = 14 - 8 * k
		ring.Size = Vector3.new(0.1, d, d)
		ring.Transparency = if locked then 0.35 else 0.6 - 0.2 * k
		ring.CFrame = CFrame.new(feet + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, t * 2, math.rad(90))
		emitters[1].Rate = if locked then 80 else 45
	end)
end

-- ===== Release: the grid =====

local function impactFrame(origin: Vector3)
	local mine = player.Character
	local myRoot = mine and mine:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not myRoot or (myRoot.Position - origin).Magnitude > CONFIG.FLASH_RANGE then
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SeverImpactFrame"
	cc.Saturation = -1
	cc.Contrast = 0.9
	cc.Brightness = 0.05
	cc.Parent = Lighting
	task.delay(s(CONFIG.FLASH), function()
		cc:Destroy()
	end)
	-- shake: stronger the closer you are
	local strength = 0.9 * (1 - (myRoot.Position - origin).Magnitude / CONFIG.FLASH_RANGE)
	local name = `SeverShake{math.random(1, 1e6)}`
	local ends = os.clock() + s(0.35)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
		local left = ends - os.clock()
		if left <= 0 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local a = strength * left / s(0.35)
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * a * 3), math.rad((math.random() - 0.5) * a * 3), 0)
	end)
end

type Slot = { Blade: SlashBlade.Blade, Offset: CFrame }

local function scars(character: Model, origin: Vector3, direction: Vector3, travel: number)
	local feet = groundBelow(origin, character)
	local right = direction:Cross(Vector3.yAxis).Unit
	local parts: { BasePart } = {}
	for i = 1, CONFIG.VERTICAL do
		local x = -CONFIG.WIDTH / 2 + CONFIG.WIDTH * (i - 0.5) / CONFIG.VERTICAL
		local mid = feet + right * x + direction * (travel / 2) + Vector3.new(0, 0.06, 0)
		local cut = fxPart("SeverScar", Vector3.new(0.45, 0.06, travel), Color3.fromRGB(14, 6, 8), Enum.Material.SmoothPlastic, 0.05)
		cut.CFrame = CFrame.lookAt(mid, mid + direction)
		cut.Parent = folder()
		local glow = fxPart("SeverScarGlow", Vector3.new(0.18, 0.08, travel), Color3.fromRGB(200, 20, 40), Enum.Material.Neon, 0.3)
		glow.CFrame = cut.CFrame + Vector3.new(0, 0.02, 0)
		glow.Parent = folder()
		table.insert(parts, cut)
		table.insert(parts, glow)
	end
	task.spawn(function()
		task.wait(s(CONFIG.SCAR_SECONDS))
		local fade = s(0.8)
		local t0 = os.clock()
		while os.clock() - t0 < fade do
			local a = (os.clock() - t0) / fade
			for _, p in parts do
				p.Transparency = math.max(p.Transparency, a)
			end
			RunService.Heartbeat:Wait()
		end
		for _, p in parts do
			p:Destroy()
		end
	end)
end

function SeverVFX.Launch(character: Model, origin: Vector3, direction: Vector3, _serverTime: number, _seed: number)
	local dir = Vector3.new(direction.X, 0, direction.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local wall = workspace:Raycast(origin, dir * CONFIG.RANGE, Projectile.Filters(character).World)
	local travel = if wall then math.max(1, wall.Distance - 0.5) else CONFIG.RANGE

	playSound("Release", origin)
	playSound("Crack", origin)
	impactFrame(origin)

	local model = Instance.new("Model")
	model.Name = "SeverGrid"
	model.Parent = folder()
	local slots: { Slot } = {}
	local lift = CONFIG.HEIGHT / 2 - CONFIG.GROUND -- the grid's centre above the root (bottom at the feet)
	for i = 1, CONFIG.VERTICAL do
		local x = -CONFIG.WIDTH / 2 + CONFIG.WIDTH * (i - 0.5) / CONFIG.VERTICAL
		local blade = SlashBlade.new(model, CONFIG.HEIGHT * 1.15, CONFIG.BLADE_WIDTH)
		table.insert(slots, { Blade = blade, Offset = CFrame.new(x, lift, 0) })
	end
	for j = 1, CONFIG.HORIZONTAL do
		local y = -CONFIG.GROUND + CONFIG.HEIGHT * (j - 0.5) / CONFIG.HORIZONTAL
		local blade = SlashBlade.new(model, CONFIG.WIDTH * 1.12, CONFIG.BLADE_WIDTH)
		table.insert(slots, { Blade = blade, Offset = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)) })
	end

	-- a burst of dust and crimson at the caster's feet
	local burst = fxPart("SeverBurst", Vector3.new(1, 1, 1), Color3.new(), Enum.Material.SmoothPlastic, 1)
	burst.CFrame = CFrame.new(groundBelow(origin, character))
	burst.Parent = folder()
	local dust = emitter(burst, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(70, 60, 60)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = seq(0.3, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(80, 10),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 3,
		Rate = 0,
	})
	dust:Emit(24)
	task.delay(2, function()
		burst:Destroy()
	end)

	local start = os.clock()
	local flightTime = travel / CONFIG.SPEED
	local done = false
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) * SeverVFX.TimeScale
		local d = math.min(travel, CONFIG.SPEED * t)
		local grow = math.clamp(t / CONFIG.GROW, 0.25, 1)
		local fade = math.clamp((t - flightTime) / CONFIG.FADE, 0, 1)
		local at = origin + dir * d
		local frame = CFrame.lookAt(at, at + dir)
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for _, slot in slots do
			SlashBlade.Shape(slot.Blade, grow * (1 + 0.15 * fade), fade)
			SlashBlade.Collect(slot.Blade, frame * slot.Offset, parts, cframes)
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		if fade >= 1 and not done then
			done = true
			conn:Disconnect()
			model:Destroy()
		end
	end)
	task.delay(s(flightTime), function()
		scars(character, origin, dir, travel)
	end)
end

-- ===== Hits =====

function SeverVFX.Impact(_character: Model, hits: { { Target: Model, Position: Vector3 } }, _serverTime: number)
	for _, hit in hits do
		local target = hit.Target
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local at = if targetRoot then targetRoot.Position else hit.Position
		playSound("Hit", at)
		local model = Instance.new("Model")
		model.Name = "SeverHit"
		model.Parent = folder()
		local a = SlashBlade.new(model, 9, 0.7)
		local b = SlashBlade.new(model, 9, 0.7)
		local camera = workspace.CurrentCamera
		local face = CFrame.lookAt(at, camera.CFrame.Position)
		local start = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) * SeverVFX.TimeScale
			local grow = math.clamp(t / 0.06, 0, 1)
			local fade = math.clamp((t - 0.1) / 0.25, 0, 1)
			SlashBlade.Shape(a, grow, fade)
			SlashBlade.Shape(b, grow, fade)
			SlashBlade.Move(a, face * CFrame.Angles(0, 0, math.rad(40)))
			SlashBlade.Move(b, face * CFrame.Angles(0, 0, math.rad(-40)))
			if fade >= 1 then
				conn:Disconnect()
				model:Destroy()
			end
		end)
	end
end

return SeverVFX
