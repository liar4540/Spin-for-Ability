--!strict
-- LightningBolt: procedural lightning drawn with pooled Beams (written for Thunder Lance; any skill can
-- use it). One bolt = a jagged line from A to B:
--   * Segments + 1 points evenly spaced along A-B; each middle point is pushed sideways at random,
--     up to MaxOffset, and less toward both ends (x sin(pi t)) so the bolt stays attached at A and B.
--   * Each segment is a Beam between two Attachments: soft-edged white line texture (glow_line.png),
--     LightEmission 1, FaceCamera, Width0 = Width1 = Thickness, Segments 1, coloured by Color.
--   * Optional: one branch from a random middle point, 30-50% of the bolt's length (Branch), or
--     several branches with their own length and angle (Branches, the sky strike).
--   * Optional Layers: every segment drawn as several stacked Beams (outer glow, middle, core), each
--     its own width, colour and transparency; branches can use only some of the layers.
--   * It stays at full for Hold, then fades from Transparency to 1 over Lifetime, then its Beams go
--     back to the pool. Dim() turns a live bolt down (a flicker dip) without redrawing it.
-- Randomness comes from the Random passed in, so a server seed gives every client the same bolt
-- (Vault: Lightning Strikes and Thunder - seed from the server event).
-- Instances are never made per frame: every Attachment lives on ONE anchored holder part
-- (workspace.ClientVFX.LightningBolts) and Beams are reused. One Heartbeat connection fades every bolt
-- and is disconnected when none are left. Bolts more than CULL_STUDS from the camera aren't drawn.

local RunService = game:GetService("RunService")

local TEXTURE = "rbxassetid://77325461611512" -- glow_line.png (Game/assets/vfx/textures)
local CULL_STUDS = 200
local MAX_POOL = 160 -- Beams kept for reuse (the sky strike draws up to 90 at once, plus the spear's)

export type Params = {
	From: Vector3,
	To: Vector3,
	Segments: number,
	MaxOffset: number?, -- studs (default 0.6)
	Thickness: number,
	Color: Color3,
	Lifetime: number, -- game seconds to fade out
	Rng: Random,
	Branch: boolean?,
	Transparency: number?, -- at the start (default 0)
	TimeScale: number?, -- playback speed (VFX tests: 0.25)
	ZOffset: number?,
	Layers: { Layer }?, -- stacked Beams per segment (outer first); replaces Thickness / Color / Transparency
	Branches: Branches?, -- several shaped branches (instead of Branch)
	Hold: number?, -- game seconds at full before the fade starts (default 0)
	Intensity: number?, -- 0..1: opacity and width scale (a weaker stroke); default 1
}

export type Layer = {
	Width: number,
	Color: Color3,
	Transparency: number?, -- default 0
	ZOffset: number?,
	LightEmission: number?, -- default 1 (additive); lower keeps a coloured glow from washing to white
}

export type Branches = {
	Count: number,
	LengthMin: number, -- studs
	LengthMax: number,
	AngleMin: number, -- degrees away from the bolt's own direction
	AngleMax: number,
	Segments: number,
	MaxOffset: number?, -- default: the bolt's MaxOffset x 0.4
	Layers: { number }?, -- which of the bolt's Layers branches draw (default all)
	Width: number?, -- x each layer's width (default 0.6)
}

type Link = { A0: Attachment, A1: Attachment, Beam: Beam, Alpha: number, Width: number }

export type Bolt = {
	Links: { Link },
	Born: number, -- os.clock()
	Hold: number, -- real seconds
	Lifetime: number, -- real seconds
	Intensity: number,
	Done: boolean,
}

local LightningBolt = {}

local holder: Part? = nil
local free: { Link } = {}
local active: { Bolt } = {}
local heartbeat: RBXScriptConnection? = nil
local inUse = 0

local function getHolder(): Part
	if holder and holder.Parent then
		return holder
	end
	local vfx = workspace:FindFirstChild("ClientVFX")
	if not vfx then
		vfx = Instance.new("Folder")
		vfx.Name = "ClientVFX"
		vfx.Parent = workspace
	end
	local part = Instance.new("Part")
	part.Name = "LightningBolts"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.05
	part.CFrame = CFrame.identity -- attachment Positions are world positions
	part.Parent = vfx
	holder = part
	table.clear(free) -- a new holder: the old pool went with the old one
	return part
end

local function newLink(h: Part): Link
	-- parent the attachments before positioning them (a WorldPosition set before parenting is local)
	local a0 = Instance.new("Attachment")
	a0.Parent = h
	local a1 = Instance.new("Attachment")
	a1.Parent = h
	local beam = Instance.new("Beam")
	beam.Texture = TEXTURE
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Enabled = false
	beam.Parent = h
	return { A0 = a0, A1 = a1, Beam = beam, Alpha = 0, Width = 0 }
end

local function take(): Link
	local h = getHolder()
	local link = table.remove(free)
	if link and link.Beam.Parent then
		return link
	end
	return newLink(h)
end

local function give(link: Link)
	link.Beam.Enabled = false
	inUse -= 1
	if #free < MAX_POOL then
		table.insert(free, link)
	else
		link.Beam:Destroy()
		link.A0:Destroy()
		link.A1:Destroy()
	end
end

-- A link's look at fade t (0..1) and the bolt's intensity: opacity and width scale down together.
local function paint(link: Link, t: number, intensity: number)
	local opacity = (1 - link.Alpha) * (1 - t * t) * intensity
	link.Beam.Transparency = NumberSequence.new(1 - opacity)
	local width = link.Width * (0.5 + 0.5 * intensity)
	link.Beam.Width0 = width
	link.Beam.Width1 = width
end

local function step()
	local now = os.clock()
	for i = #active, 1, -1 do
		local bolt = active[i]
		local age = now - bolt.Born - bolt.Hold
		local t = if bolt.Lifetime > 0 then math.max(age, 0) / bolt.Lifetime else 1
		if bolt.Done or t >= 1 then
			for _, link in bolt.Links do
				give(link)
			end
			bolt.Done = true
			table.remove(active, i)
		elseif age > 0 then
			for _, link in bolt.Links do
				paint(link, t, bolt.Intensity)
			end
		end
	end
	if #active == 0 and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- The bolt's points from A to B (Segments + 1 of them).
function LightningBolt.Points(from: Vector3, to: Vector3, segments: number, maxOffset: number, rng: Random): { Vector3 }
	local dir = to - from
	local length = dir.Magnitude
	local axis = if length > 1e-4 then dir / length else Vector3.yAxis
	local any = if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local side = axis:Cross(any).Unit
	local up = axis:Cross(side).Unit
	local points = { from }
	for i = 1, segments - 1 do
		local t = i / segments
		local falloff = math.sin(t * math.pi) -- 0 at both ends, 1 in the middle
		local offset = (side * rng:NextNumber(-1, 1) + up * rng:NextNumber(-1, 1)) * maxOffset * falloff
		table.insert(points, from + dir * t + offset)
	end
	table.insert(points, to)
	return points
end

-- A unit vector `degrees` away from `dir`, turned round it at random.
local function tilt(dir: Vector3, degrees: number, rng: Random): Vector3
	local any = if math.abs(dir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local axis = CFrame.fromAxisAngle(dir, rng:NextNumber(0, math.pi * 2)):VectorToWorldSpace(dir:Cross(any).Unit)
	return CFrame.fromAxisAngle(axis, math.rad(degrees)):VectorToWorldSpace(dir)
end

-- Draw one bolt; returns nil when it's too far from the camera to be worth drawing.
function LightningBolt.Draw(p: Params): Bolt?
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - (p.From + p.To) / 2).Magnitude > CULL_STUDS then
		return nil
	end
	local maxOffset = p.MaxOffset or 0.6
	local layers: { Layer } = p.Layers
		or { { Width = p.Thickness, Color = p.Color, Transparency = p.Transparency, ZOffset = p.ZOffset } }
	local allLayers = {}
	for i in layers do
		allLayers[i] = i
	end
	local points = LightningBolt.Points(p.From, p.To, p.Segments, maxOffset, p.Rng)
	-- every path: its points, the layers it draws and its width scale
	local paths: { { Points: { Vector3 }, Layers: { number }, Width: number } } = {
		{ Points = points, Layers = allLayers, Width = 1 },
	}
	local along = p.To - p.From
	if p.Branches and p.Segments >= 4 then
		local b = p.Branches
		local dir = along.Unit
		for _ = 1, b.Count do
			local base = points[p.Rng:NextInteger(2, p.Segments - 1)]
			local out = tilt(dir, p.Rng:NextNumber(b.AngleMin, b.AngleMax), p.Rng)
			local tip = base + out * p.Rng:NextNumber(b.LengthMin, b.LengthMax)
			table.insert(paths, {
				Points = LightningBolt.Points(base, tip, b.Segments, b.MaxOffset or maxOffset * 0.4, p.Rng),
				Layers = b.Layers or allLayers,
				Width = b.Width or 0.6,
			})
		end
	elseif p.Branch and p.Segments >= 4 then
		local at = p.Rng:NextInteger(2, p.Segments - 1)
		local base = points[at]
		local length = along.Magnitude * p.Rng:NextNumber(0.3, 0.5)
		local dir = (points[at + 1] - base).Unit
		local kick = dir:Cross(if math.abs(dir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
		local tip = base + (dir + kick * p.Rng:NextNumber(-0.8, 0.8)).Unit * length
		table.insert(paths, { Points = LightningBolt.Points(base, tip, 3, maxOffset * 0.6, p.Rng), Layers = allLayers, Width = 0.6 })
	end
	local timeScale = p.TimeScale or 1
	local bolt: Bolt = {
		Links = {},
		Born = os.clock(),
		Hold = (p.Hold or 0) / timeScale,
		Lifetime = p.Lifetime / timeScale,
		Intensity = p.Intensity or 1,
		Done = false,
	}
	for _, path in paths do
		for _, layerIndex in path.Layers do
			local layer = layers[layerIndex]
			local colour = ColorSequence.new(layer.Color)
			for i = 1, #path.Points - 1 do
				local link = take()
				inUse += 1
				link.A0.Position = path.Points[i]
				link.A1.Position = path.Points[i + 1]
				link.Alpha = layer.Transparency or 0
				link.Width = layer.Width * path.Width
				link.Beam.Color = colour
				link.Beam.ZOffset = layer.ZOffset or 0
				link.Beam.LightEmission = layer.LightEmission or 1
				paint(link, 0, bolt.Intensity)
				link.Beam.Enabled = true
				table.insert(bolt.Links, link)
			end
		end
	end
	table.insert(active, bolt)
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
	return bolt
end

-- Turn a live bolt down (or back up) without redrawing it: a flicker dip between strokes.
function LightningBolt.Dim(bolt: Bolt?, intensity: number)
	if not bolt or bolt.Done then
		return
	end
	bolt.Intensity = intensity
	for _, link in bolt.Links do
		paint(link, 0, intensity)
	end
end

-- Change a bolt's colour (and width) while it keeps fading: e.g. the previous crackle bolt left behind
-- as a dark afterimage when a new one is drawn, without any extra Beams.
function LightningBolt.Recolour(bolt: Bolt?, color: Color3, widthScale: number?)
	if not bolt or bolt.Done then
		return
	end
	local colour = ColorSequence.new(color)
	for _, link in bolt.Links do
		link.Beam.Color = colour
		if widthScale then
			link.Width *= widthScale
			link.Beam.Width0 *= widthScale
			link.Beam.Width1 *= widthScale
		end
	end
end

-- Move a whole bolt by `delta` (keeps its shape): e.g. a trail bolt that stays on a fast spear's tail
-- between redraws instead of being left behind.
function LightningBolt.Shift(bolt: Bolt?, delta: Vector3)
	if not bolt or bolt.Done or delta.Magnitude < 1e-4 then
		return
	end
	for _, link in bolt.Links do
		link.A0.Position += delta
		link.A1.Position += delta
	end
end

-- Take it away now: its Beams go back to the pool at once (the frame's next bolts can reuse them).
function LightningBolt.Release(bolt: Bolt?)
	if bolt and not bolt.Done then
		bolt.Done = true
		for _, link in bolt.Links do
			give(link)
		end
		table.clear(bolt.Links) -- step() drops it from the active list without giving them twice
	end
end

-- Fill the pool up to `count` Beams now (in use or free), so a skill's first cast makes everything it
-- will ever need and later casts never add instances (the pool must not grow cast after cast).
function LightningBolt.Prewarm(count: number)
	local h = getHolder()
	for _ = inUse + #free + 1, math.min(count, MAX_POOL) do
		table.insert(free, newLink(h))
	end
end

-- Beams drawn right now (for the per-cast budget check).
function LightningBolt.InUse(): number
	return inUse
end

-- Beams in the pool, used or not (stays flat once warm: the pool must not grow cast after cast).
function LightningBolt.PoolSize(): number
	local h = holder
	if not h or not h.Parent then
		return 0
	end
	local n = 0
	for _, child in h:GetChildren() do
		if child:IsA("Beam") then
			n += 1
		end
	end
	return n
end

return LightningBolt
