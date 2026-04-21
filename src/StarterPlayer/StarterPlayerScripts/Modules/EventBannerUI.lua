--!strict
--[[
    EventBannerUI.lua (клиент)
    Большой баннер с именем события: tape-in + fade-out.
    Слушает Remotes.Event("EventBanner") и Remotes.Event("EventStarted").
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local EventBannerUI = {}
local player = Players.LocalPlayer

local function buildGui(): (ScreenGui, TextLabel)
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "JMC_BannerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = pg

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.8, 0, 0, 120)
	lbl.Position = UDim2.new(0.1, 0, 0.18, 0)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ""
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.1
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextTransparency = 1
	lbl.Parent = gui

	return gui, lbl
end

local _gui: ScreenGui? = nil
local _lbl: TextLabel? = nil

local function show(text: string, color: Color3?)
	if not _lbl then
		return
	end
	_lbl.Text = text
	_lbl.TextColor3 = color or Color3.new(1, 1, 1)
	_lbl.TextTransparency = 1
	_lbl.Size = UDim2.new(0.5, 0, 0, 80)
	_lbl.Position = UDim2.new(0.25, 0, 0.18, 0)

	local appear = TweenService:Create(_lbl, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Size = UDim2.new(0.8, 0, 0, 120),
		Position = UDim2.new(0.1, 0, 0.18, 0),
	})
	appear:Play()

	task.delay(2.2, function()
		if not _lbl then
			return
		end
		local fade = TweenService:Create(_lbl, TweenInfo.new(0.6), { TextTransparency = 1 })
		fade:Play()
	end)
end

function EventBannerUI:Start()
	_gui, _lbl = buildGui()

	Remotes.Event("EventBanner").OnClientEvent:Connect(function(text, color)
		show(tostring(text or ""), color)
	end)

	Remotes.Event("EventStarted").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			show(
				payload.displayName or payload.name or "СОБЫТИЕ!",
				payload.color or Color3.fromRGB(255, 180, 220)
			)
		elseif typeof(payload) == "string" then
			show(payload, Color3.fromRGB(255, 180, 220))
		end
	end)

	print("[JMC][Client] EventBannerUI готов")
end

return EventBannerUI
