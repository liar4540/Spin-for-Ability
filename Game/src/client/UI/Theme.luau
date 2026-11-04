--!strict
-- Theme: the one place for UI colors, fonts and the shared button feel (vault: 06 UI-UX → Style).
-- Rarity colors live in Shared/Config/Rarities (Color), not here.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromHex("#141826"), -- deep navy, used at 10% transparency
	Card = Color3.fromHex("#1F2538"), -- lighter navy: panel inner / cards / slots
	Outline = Color3.fromHex("#0A0C14"),
	Accent = Color3.fromHex("#FFC83D"), -- energy gold: buttons, highlights, selection
	Accent2 = Color3.fromHex("#3DE0FF"), -- electric cyan: spin, luck
	Good = Color3.fromHex("#4CD964"),
	Bad = Color3.fromHex("#FF4D5E"), -- close / delete
	Text = Color3.fromHex("#FFFFFF"),
	TextDim = Color3.fromHex("#8A90A6"),
}

Theme.PanelTransparency = 0.1

Theme.Fonts = {
	Title = Enum.Font.LuckiestGuy, -- titles, numbers, buttons
	Body = Enum.Font.FredokaOne, -- small text, descriptions
}

Theme.Corner = UDim.new(0.25, 0) -- chunky rounded buttons
Theme.PanelCorner = UDim.new(0, 16)
Theme.TextStroke = 2
Theme.OutlineStroke = 3

-- A text label in the house style: font, white text, black stroke so it reads on top of VFX.
function Theme.Label(parent: Instance, text: string, font: Enum.Font, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = font
	label.TextSize = size
	label.TextColor3 = Theme.Colors.Text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Theme.TextStroke
	stroke.Color = Theme.Colors.Outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = parent
	return label
end

function Theme.Round(parent: Instance, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.Corner
	corner.Parent = parent
end

-- Thick outline around a frame/button. Returns it so callers can recolor it (rarity, selection).
function Theme.Outline(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.Colors.Outline
	stroke.Thickness = thickness or Theme.OutlineStroke
	stroke.Parent = parent
	return stroke
end

-- Hover grows to 1.08x (0.1 s); click shrinks to 0.92x then bounces back (Back easing).
function Theme.PressFeel(button: GuiButton): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local fast = TweenInfo.new(0.1, Enum.EasingStyle.Quad)
	local bounce = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, fast, { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, fast, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, bounce, { Scale = 1 }):Play()
	end)
	return scale
end

return Theme
