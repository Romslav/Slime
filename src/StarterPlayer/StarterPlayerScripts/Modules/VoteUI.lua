--!strict
--[[
    VoteUI.lua (клиент)
    Рисует нижний баннер голосования на длительность VoteOpened.duration секунд.
    По тапу шлёт VoteCast(index).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local VoteUI = {}
local player = Players.LocalPlayer

local _gui: ScreenGui? = nil

local function clearGui()
    if _gui then _gui:Destroy(); _gui = nil end
end

local function render(options: { string }, duration: number)
    clearGui()
    local pg = player:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "JMC_VoteUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 60
    gui.Parent = pg
    _gui = gui

    local panel = Instance.new("Frame")
    panel.BackgroundColor3 = Color3.fromRGB(30, 10, 40)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    panel.Size = UDim2.new(0, 520, 0, 180)
    panel.Position = UDim2.new(0.5, -260, 1, -220)
    panel.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 6)
    title.Font = Enum.Font.FredokaOne
    title.TextScaled = true
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Text = string.format("🗳 ГОЛОСУЙ: какое событие следующее? (%dс)", duration)
    title.Parent = panel

    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, -20, 1, -60)
    row.Position = UDim2.new(0, 10, 0, 50)
    row.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 10)
    layout.Parent = row

    for i, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Font = Enum.Font.FredokaOne
        btn.TextScaled = true
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.BackgroundColor3 = Color3.fromRGB(255, 120, 200)
        btn.Size = UDim2.new(0, 150, 1, 0)
        btn.Text = opt
        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 8)
        bCorner.Parent = btn
        btn.Parent = row

        btn.Activated:Connect(function()
            Remotes.Event("VoteCast"):FireServer(i)
            btn.Text = "✔ " .. opt
            btn.BackgroundColor3 = Color3.fromRGB(100, 200, 140)
        end)
    end

    task.delay(duration + 0.5, function()
        if _gui == gui then
            clearGui()
        end
    end)
end

function VoteUI:Start()
    Remotes.Event("VoteOpened").OnClientEvent:Connect(function(data)
        if typeof(data) ~= "table" then return end
        render(data.options or {}, data.duration or 20)
    end)
    Remotes.Event("VoteClosed").OnClientEvent:Connect(function(data)
        clearGui()
    end)
    print("[JMC][Client] VoteUI готов")
end

return VoteUI
