--!strict
--[[
	EventHintUI.lua
	Постоянная подсказка для действий во время событий.
	Показывается и скрывается через RemoteEvent "EventHint".
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local EventHintUI = {}
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local panel: Frame? = nil
local label: TextLabel? = nil

local function ensureGui()
	if gui and panel and label then
		return
	end

	local pg = player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "JMC_EventHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 65
	gui.Parent = pg

	panel = Instance.new("Frame")
	panel.BackgroundColor3 = Color3.fromRGB(48, 34, 72)
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.29, 0)
	panel.Size = UDim2.new(0, 560, 0, 62)
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.65
	stroke.Thickness = 2
	stroke.Parent = panel

	label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -28, 1, 0)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 245, 200)
	label.TextStrokeTransparency = 0.55
	label.Text = ""
	label.Parent = panel
end

local function show(text: string, color: Color3?)
	ensureGui()
	if not panel or not label then
		return
	end

	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 245, 200)
	panel.Visible = true
	panel.BackgroundTransparency = 1
	label.TextTransparency = 1

	TweenService:Create(panel, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.18,
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.2), {
		TextTransparency = 0,
	}):Play()
end

local function hide()
	if not panel or not label then
		return
	end

	local fadePanel = TweenService:Create(panel, TweenInfo.new(0.18), {
		BackgroundTransparency = 1,
	})
	local fadeText = TweenService:Create(label, TweenInfo.new(0.18), {
		TextTransparency = 1,
	})
	fadePanel:Play()
	fadeText:Play()
	local conn
	conn = fadeText.Completed:Connect(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if panel then
			panel.Visible = false
		end
	end)
end

function EventHintUI:Start()
	ensureGui()

	Remotes.Event("EventHint").OnClientEvent:Connect(function(text, color)
		local msg = tostring(text or "")
		if msg == "" then
			hide()
		else
			show(msg, color)
		end
	end)

	print("[JMC][Client] EventHintUI готов")
end

return EventHintUI
