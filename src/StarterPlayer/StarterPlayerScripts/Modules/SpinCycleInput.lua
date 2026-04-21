--!strict
--[[
    SpinCycleInput.lua
    Клиентский ввод для события Spin Cycle:
      - E  -> запрос "зарыться"
      - Space hold -> сигнал "держусь"
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local SpinCycleInput = {}

local active = false
local holdingSpace = false

local function setActive(value: boolean)
	if active == value then
		return
	end

	active = value
	if not active and holdingSpace then
		holdingSpace = false
		Remotes.Event("SpinCycleInput"):FireServer("hold_end")
	end
end

function SpinCycleInput:Start()
	Remotes.Event("EventStarted").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.name == "SpinCycle" then
			setActive(true)
		end
	end)

	Remotes.Event("EventEnded").OnClientEvent:Connect(function(name)
		if tostring(name) == "SpinCycle" then
			setActive(false)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not active then
			return
		end

		if input.KeyCode == Enum.KeyCode.E then
			Remotes.Event("SpinCycleInput"):FireServer("dig")
		elseif input.KeyCode == Enum.KeyCode.Space and not holdingSpace then
			holdingSpace = true
			Remotes.Event("SpinCycleInput"):FireServer("hold_start")
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gpe)
		if not active then
			return
		end

		if input.KeyCode == Enum.KeyCode.Space and holdingSpace then
			holdingSpace = false
			Remotes.Event("SpinCycleInput"):FireServer("hold_end")
		end
	end)

	print("[JMC][Client] SpinCycleInput готов")
end

return SpinCycleInput
