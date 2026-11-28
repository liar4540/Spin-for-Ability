--!strict
-- StatusController: shows status effects on every fighter (players + training dummies), read from the
-- attributes the server sets, so it works the same for everyone and for any ability that causes them.
--   BleedEndsAt (server time; CombatService.ApplyBleed)  -> blood-drop icon above the head with a timer
--       bar, blood dripping / dark red streaks / a red haze on the body (VFX.BloodMoonSlash.Bleed), and
--       on every bleed tick (health drops while bleeding) a splash of blood + a short red flash
--   SlowEndsAt (server time; StateService.ApplySlow) -> an icon by SlowKind: "Freeze" (Frost Jab, Frost
--       Bloom) = snowflake, "Heavy" (Star Cannon) = a gold star pressing down; + timer bar
-- Icons: Game/assets/vfx/_src/build_blood_moon_textures.py (status_bleed.png, status_freeze.png).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FIGHTER_TAG = "Fighter"
local STATUSES = {
	{ Attribute = "BleedEndsAt", Name = "Bleed", Icon = "rbxassetid://125722237614130", Bar = Color3.fromRGB(200, 10, 30) },
	{ Attribute = "SlowEndsAt", Name = "Slow", Icon = "rbxassetid://81174984287526", Bar = Color3.fromRGB(150, 215, 255) },
}
-- the slow's icon depends on what caused it (SlowKind, set with SlowEndsAt by StateService)
local SLOW_KINDS: { [string]: { Icon: string, Bar: Color3 } } = {
	Freeze = { Icon = "rbxassetid://81174984287526", Bar = Color3.fromRGB(150, 215, 255) },
	Heavy = { Icon = "rbxassetid://76281338593248", Bar = Color3.fromRGB(255, 205, 60) },
	-- Altar of Ruin's zone slow (temporary icon: Heavy's, until a domain icon is made)
	Domain = { Icon = "rbxassetid://76281338593248", Bar = Color3.fromRGB(220, 30, 50) },
}
local ICON_PX = 34
local FLASH = Color3.fromRGB(200, 0, 20)

type Status = { Frame: Frame, Bar: Frame, EndsAt: number, Total: number }
type Watched = {
	Model: Model,
	Gui: BillboardGui?,
	Statuses: { [string]: Status },
	Bleed: Attachment?,
	LastHealth: number,
	Connections: { RBXScriptConnection },
}

local StatusController = {}

local watched: { [Model]: Watched } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function gui(w: Watched): BillboardGui?
	if w.Gui and w.Gui.Parent then
		return w.Gui
	end
	local head = w.Model:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local g = Instance.new("BillboardGui")
	g.Name = "StatusIcons"
	g.Adornee = head
	g.Size = UDim2.fromOffset(ICON_PX * 3, ICON_PX + 8)
	g.StudsOffset = Vector3.new(0, 2.4, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 120
	g.ResetOnSpawn = false
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = g
	g.Parent = head
	w.Gui = g
	return g
end

local function addIcon(w: Watched, spec: typeof(STATUSES[1]), endsAt: number)
	local g = gui(w)
	if not g then
		return
	end
	local iconId, barColor = spec.Icon, spec.Bar
	if spec.Name == "Slow" then
		local kind = SLOW_KINDS[(w.Model:GetAttribute("SlowKind") :: string?) or "Freeze"] or SLOW_KINDS.Freeze
		iconId, barColor = kind.Icon, kind.Bar
	end
	local existing = w.Statuses[spec.Name]
	if existing then -- refreshed (a new hit)
		existing.EndsAt = endsAt
		existing.Total = math.max(0.1, endsAt - now())
		local img = existing.Frame:FindFirstChild("Icon") :: ImageLabel?
		if img then
			img.Image = iconId
		end
		existing.Bar.BackgroundColor3 = barColor
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = spec.Name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(ICON_PX, ICON_PX + 8)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = iconId
	icon.Size = UDim2.fromOffset(ICON_PX, ICON_PX)
	icon.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = icon
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Position = UDim2.fromOffset(2, ICON_PX + 2)
	back.Size = UDim2.fromOffset(ICON_PX - 4, 4)
	back.Parent = frame
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = barColor
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.Parent = back
	frame.Parent = g
	w.Statuses[spec.Name] = { Frame = frame, Bar = bar, EndsAt = endsAt, Total = math.max(0.1, endsAt - now()) }
end

local function removeIcon(w: Watched, name: string)
	local status = w.Statuses[name]
	if status then
		status.Frame:Destroy()
		w.Statuses[name] = nil
	end
end

local function startBleedFx(w: Watched)
	if w.Bleed and w.Bleed.Parent then
		return
	end
	local root = w.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local template = ReplicatedStorage:FindFirstChild("VFX")
		and ReplicatedStorage.VFX:FindFirstChild("BloodMoonSlash")
		and ReplicatedStorage.VFX.BloodMoonSlash:FindFirstChild("Bleed")
	if not root or not template then
		return
	end
	local bleed = template:Clone() :: Attachment
	bleed.Name = "StatusBleed"
	for _, e in bleed:GetChildren() do
		if e:IsA("ParticleEmitter") and e.Name ~= "Splash" then
			e.Enabled = true
		end
	end
	bleed.Parent = root
	w.Bleed = bleed
end

local function stopBleedFx(w: Watched)
	local bleed = w.Bleed
	if not bleed then
		return
	end
	w.Bleed = nil
	for _, e in bleed:GetChildren() do
		if e:IsA("ParticleEmitter") then
			e.Enabled = false
		end
	end
	task.delay(1.2, function()
		bleed:Destroy()
	end)
end

-- A bleed tick: blood splashes off and the body flashes red for a moment.
local function bleedTick(w: Watched)
	local bleed = w.Bleed
	local splash = bleed and bleed:FindFirstChild("Splash") :: ParticleEmitter?
	if splash then
		splash:Emit(10)
	end
	local flash = Instance.new("Highlight")
	flash.FillColor = FLASH
	flash.FillTransparency = 0.45
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Adornee = w.Model
	flash.Parent = w.Model
	TweenService:Create(flash, TweenInfo.new(0.25), { FillTransparency = 1 }):Play()
	task.delay(0.3, function()
		flash:Destroy()
	end)
end

local function refresh(w: Watched, spec: typeof(STATUSES[1]))
	local endsAt = w.Model:GetAttribute(spec.Attribute)
	if type(endsAt) == "number" and endsAt > now() then
		addIcon(w, spec, endsAt)
		if spec.Name == "Bleed" then
			startBleedFx(w)
		end
	else
		removeIcon(w, spec.Name)
		if spec.Name == "Bleed" then
			stopBleedFx(w)
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local w: Watched = {
		Model = model,
		Gui = nil,
		Statuses = {},
		Bleed = nil,
		LastHealth = if humanoid then humanoid.Health else 0,
		Connections = {},
	}
	watched[model] = w
	for _, spec in STATUSES do
		table.insert(w.Connections, model:GetAttributeChangedSignal(spec.Attribute):Connect(function()
			refresh(w, spec)
		end))
		refresh(w, spec)
	end
	if humanoid then
		table.insert(w.Connections, humanoid.HealthChanged:Connect(function(health)
			if health < w.LastHealth and w.Statuses.Bleed then
				bleedTick(w)
			end
			w.LastHealth = health
		end))
	end
end

local function unwatch(model: Instance)
	local w = watched[model :: Model]
	if not w then
		return
	end
	watched[model :: Model] = nil
	for _, c in w.Connections do
		c:Disconnect()
	end
	if w.Gui then
		w.Gui:Destroy()
	end
	stopBleedFx(w)
end

function StatusController.Init() end

function StatusController.Start()
	for _, model in CollectionService:GetTagged(FIGHTER_TAG) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal(FIGHTER_TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(FIGHTER_TAG):Connect(unwatch)
	-- timer bars drain; an icon whose time is up goes even if the attribute is cleared late
	RunService.RenderStepped:Connect(function()
		local t = now()
		for _, w in watched do
			for name, status in w.Statuses do
				local left = status.EndsAt - t
				if left <= 0 then
					removeIcon(w, name)
					if name == "Bleed" then
						stopBleedFx(w)
					end
				else
					status.Bar.Size = UDim2.fromScale(math.clamp(left / status.Total, 0, 1), 1)
				end
			end
		end
	end)
end

return StatusController
