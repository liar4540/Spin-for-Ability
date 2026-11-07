--!strict
-- CombatController: M1 / block / dash input (100–200 ms input buffer), instant local animation + VFX, mobile combat buttons, soft targeting.
-- Status: Milestone 1 start. Only the server → client side so far: being knocked back, and a
-- short flash on whoever gets hit. M1, block and dash input come next (vault: 07 Tech Plan, 08 Roadmap).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Knockback = require(Shared:WaitForChild("Knockback"))

local HIT_FLASH_SECONDS = 0.15
local HIT_FLASH_COLOR = Color3.fromRGB(255, 170, 60)
-- Abilities whose own on-hit VFX already marks the target (and whose palette has no orange).
local OWN_HIT_FLASH: { [string]: boolean } = {
	FrostJab = true, -- frost coat (FrostJabVFX)
	ThunderLance = true, -- electric arcs on the target (ThunderLanceVFX)
}

local CombatController = {}

-- One Highlight per hit model, reused for every hit.
local flashes: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any

local function flash(model: Model)
	local highlight = flashes[model]
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.FillColor = HIT_FLASH_COLOR
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
		flashes[model] = highlight
	end
	local h = highlight :: Highlight
	h.FillTransparency = 0.35
	h.OutlineTransparency = 0
	h.Enabled = true
	task.delay(HIT_FLASH_SECONDS, function()
		h.Enabled = false
	end)
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function CombatController.Init() end

-- Called once after every Init(). Connect events, start loops.
function CombatController.Start()
	-- Our client owns our character's physics, so the server asks us to apply knockback.
	Remotes.Event("Knockback").OnClientEvent:Connect(function(velocity: Vector3)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Knockback.Apply(root, velocity)
		end
	end)

	Remotes.Event("HitEffect").OnClientEvent:Connect(function(model: Model, abilityId: string, _position: Vector3)
		if model and model.Parent and not OWN_HIT_FLASH[abilityId] then
			flash(model)
		end
	end)
end

return CombatController
