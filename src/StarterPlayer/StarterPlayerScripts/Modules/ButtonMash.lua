--!strict
--[[
    ButtonMash.lua (клиент)
    Слушает SPACE/тап по экрану в момент, когда игрок пойман в Bubble Trap.
    Каждое нажатие → FireServer("ButtonMash").
    Показывает UI-индикатор «ЖМИ SPACE!» + прогресс.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ButtonMash = {}
local player = Players.LocalPlayer

local active = false
local mashCount = 0
local mashTarget = Config.Events.BubbleTrap.MashesToBreak or 14
local _gui: ScreenGui? = nil
local _progress: Frame? = nil

local function buildGui()
    if _gui then _gui:Destroy() end
    local pg = player:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "JMC_ButtonMash"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 70
    gui.Parent = pg
    _gui = gui

    local panel = Instance.new("Frame")
    panel.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    panel.Size = UDim2.new(0, 420, 0, 160)
    panel.Position = UDim2.new(0.5, -210, 0.35, 0)
    panel.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = panel

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 70)
    title.Font = Enum.Font.FredokaOne
    title.TextScaled = true
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Text = "ЖМИ SPACE / ТАП!"
    title.TextStrokeTransparency = 0
    title.Parent = panel

    local barBG = Instance.new("Frame")
    barBG.BackgroundColor3 = Color3.fromRGB(30, 60, 90)
    barBG.BorderSizePixel = 0
    barBG.Size = UDim2.new(1, -40, 0, 34)
    barBG.Position = UDim2.new(0, 20, 0, 90)
    barBG.Parent = panel
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0.3, 0)
    bgCorner.Parent = barBG

    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = Color3.fromRGB(200, 255, 240)
    bar.BorderSizePixel = 0
    bar.Size = UDim2.fromScale(0, 1)
    bar.Parent = barBG
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0.3, 0)
    barCorner.Parent = bar

    _progress = bar
end

local function closeGui()
    if _gui then _gui:Destroy(); _gui = nil end
    _progress = nil
end

local function doMash()
    if not active then return end
    mashCount = mashCount + 1
    Remotes.Event("ButtonMash"):FireServer()
    if _progress then
        local pct = math.clamp(mashCount / mashTarget, 0, 1)
        TweenService:Create(_progress, TweenInfo.new(0.1),
            { Size = UDim2.fromScale(pct, 1) }):Play()
    end
    if mashCount >= mashTarget then
        active = false
        task.delay(0.3, closeGui)
    end
end

function ButtonMash:Start()
    Remotes.Event("EventBanner").OnClientEvent:Connect(function(text, color)
        local t = tostring(text or "")
        if string.find(t, "SPACE") or string.find(t, "ПУЗЫРЬ") == nil and string.find(t, "SPACE") then
            -- запуск при «ЖМИ SPACE!»
            active = true
            mashCount = 0
            buildGui()
        elseif string.find(t, "ПУЗЫРЬ ЛОПНУЛ") then
            active = false
            closeGui()
        end
    end)

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not active then return end
        if input.KeyCode == Enum.KeyCode.Space
            or input.KeyCode == Enum.KeyCode.ButtonA
            or input.UserInputType == Enum.UserInputType.Touch then
            doMash()
        end
    end)

    print("[JMC][Client] ButtonMash готов")
end

return ButtonMash
