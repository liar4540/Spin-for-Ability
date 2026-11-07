--!strict
-- Client main script: starts every controller in order.
-- The client only asks the server and shows results; it never decides rolls, damage or money.

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	Init: () -> (),
	Start: () -> (),
}

local ORDER = {
	"HUDController",
	"CombatController",
	"ReactionController",
	"AbilityController",
	"InventoryController",
	"ShopController",
	"SettingsController",
	"VFXTestController",
}

local loaded: { Controller } = {}
for _, name in ORDER do
	local controller = require(Controllers:WaitForChild(name)) :: Controller
	controller.Init()
	table.insert(loaded, controller)
end
for _, controller in loaded do
	controller.Start()
end
