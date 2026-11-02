--!strict
-- SpinController: Spin button, honest reveal animation, Keep/Equip/Skip, odds popup.
--
-- Status: Milestone 1. Only a STUDIO-ONLY TEST PANEL for now (plain text + buttons),
-- so SpinService can be tested. The real spin screen (vault: 06 UI-UX) replaces it later.
-- The client only asks; the server rolls and decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Odds = require(Shared:WaitForChild("Odds"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SpinController = {}

local requestSpin: RemoteFunction
local chooseResult: RemoteFunction

local function makeButton(parent: Instance, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Text = text
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(110, 44)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.Parent = parent
	return button
end

local function buildTestPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpinTestPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(480, 150)
	frame.Position = UDim2.new(0.5, -240, 1, -170)
	frame.BackgroundTransparency = 0.3
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 0, 80)
	label.Position = UDim2.fromOffset(8, 4)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 16
	label.TextWrapped = true
	label.Text = "[Studio test panel] Press SPIN."
	label.Parent = frame

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0, 48)
	row.Position = UDim2.new(0, 8, 1, -54)
	row.BackgroundTransparency = 1
	row.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local spinButton = makeButton(row, "SPIN", 1)
	local keepButton = makeButton(row, "Keep", 2)
	local equipButton = makeButton(row, "Equip", 3)
	local skipButton = makeButton(row, "Skip", 4)

	spinButton.Activated:Connect(function()
		local response = requestSpin:InvokeServer()
		if response.Ok then
			label.Text = `{response.Rarity}: {response.AbilityId}{if response.IsNew then "  NEW!" else ""}\n`
				.. `{Odds.FormatPercent(response.Chance)} ({Odds.FormatOneIn(response.Chance)})  ·  luck {response.Luck}x  ·  reveal {response.RevealSeconds}s`
		else
			label.Text = `Can't spin: {response.Reason}`
		end
	end)

	local function choose(choice: string)
		local response = chooseResult:InvokeServer(choice)
		label.Text = if response.Ok then `{choice}: done` else `{choice} failed: {response.Reason}`
	end
	keepButton.Activated:Connect(function()
		choose("Keep")
	end)
	equipButton.Activated:Connect(function()
		choose("Equip")
	end)
	skipButton.Activated:Connect(function()
		choose("Skip")
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function SpinController.Init()
	requestSpin = Remotes.Function("RequestSpin")
	chooseResult = Remotes.Function("ChooseResult")
end

function SpinController.Start()
	if RunService:IsStudio() then
		buildTestPanel()
	end
end

return SpinController
