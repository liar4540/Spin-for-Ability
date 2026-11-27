--!strict
-- ShiftLockController: Shift toggles shift lock. While it's on:
--   * the mouse is locked to the centre and the camera sits over the character's right shoulder,
--   * the character always faces where the camera looks (so M1s, skills and dashes go where you aim),
--   * a small crosshair marks the aim point.
-- Hold Left Ctrl to use the mouse (inventory, shop...) without turning shift lock off.
-- Roblox's own shift lock is switched off in default.project.json (StarterPlayer.EnableMouseLockOption),
-- otherwise both would answer the same key.
-- Touch-only devices don't get it (the camera there is the thumbstick's).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local TOGGLE_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true }
local FREE_MOUSE_KEY = Enum.KeyCode.LeftControl
local SHOULDER = Vector3.new(1.75, 0.25, 0) -- camera offset: right and a little up
-- The body is not turned to the camera in these states: something else is moving it.
local NO_TURN: { [string]: boolean } = { Ragdolled = true, Stunned = true, GuardBroken = true, Dashing = true, Casting = true, Dead = true }

local ShiftLockController = {}

local enabled = false
local applied = false -- were the mouse / AutoRotate changes made (so we know to undo them)
local crosshair: Frame? = nil

local function buildCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftLock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	local dot = Instance.new("Frame")
	dot.Name = "Crosshair"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Parent = dot
	dot.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	crosshair = dot
end

local function release(humanoid: Humanoid?)
	if not applied then
		return
	end
	applied = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if humanoid then
		humanoid.AutoRotate = true
	end
	if crosshair then
		crosshair.Visible = false
	end
end

local function step()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not enabled or not humanoid or not root or humanoid.Health <= 0 or not camera then
		release(humanoid)
		return
	end
	if UserInputService:IsKeyDown(FREE_MOUSE_KEY) then
		-- the mouse is free for a moment (menus); the body stays as it is
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		if crosshair then
			crosshair.Visible = false
		end
		return
	end
	applied = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	humanoid.AutoRotate = false -- abilities switch AutoRotate back on when they end; this turns the body itself
	if crosshair then
		crosshair.Visible = true
	end

	local state = character:GetAttribute("CombatState")
	if not (type(state) == "string" and NO_TURN[state]) and not humanoid.Sit then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
	-- Over-the-shoulder: after the default camera and the combat camera shake have placed it.
	camera.CFrame *= CFrame.new(SHOULDER)
end

function ShiftLockController.Toggle()
	enabled = not enabled
	if not enabled then
		local character = player.Character
		release(character and character:FindFirstChildOfClass("Humanoid"))
	end
end

function ShiftLockController.IsOn(): boolean
	return enabled
end

-- Called once at startup, before any Start(). Create state, read config. Don't yield.
function ShiftLockController.Init() end

-- Called once after every Init(). Connect events, start loops.
function ShiftLockController.Start()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return
	end
	task.spawn(buildCrosshair)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and TOGGLE_KEYS[input.KeyCode] then
			ShiftLockController.Toggle()
		end
	end)
	RunService:BindToRenderStep("ShiftLock", Enum.RenderPriority.Camera.Value + 2, step)
end

return ShiftLockController
