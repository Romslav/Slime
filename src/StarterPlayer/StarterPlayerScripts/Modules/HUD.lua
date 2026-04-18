--!strict
--[[
    HUD.lua (клиент)
    Основной игровой HUD:
      - Топ-центр: таймер текущей сессии в круге + количество монет
      - Правый верх: текущая трансформация (иконка)
      - Правый низ: кнопка магазина
      - Левый низ: счётчик игроков в круге (синхронизируется с сервером через leaderstats)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUD = {}
local player = Players.LocalPlayer

local function formatTime(sec: number): string
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

local function buildGui(): ScreenGui
    local pg = player:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "JMC_HUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10
    gui.Parent = pg
    return gui
end

local function makeLabel(parent: GuiObject, text: string, icon: string?): TextLabel
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundColor3 = Color3.fromRGB(30, 10, 40)
    lbl.BackgroundTransparency = 0.3
    lbl.BorderSizePixel = 0
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextScaled = true
    lbl.Text = (icon and (icon .. " ") or "") .. text
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.3, 0)
    corner.Parent = lbl
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(255, 120, 200)
    stroke.Parent = lbl
    lbl.Parent = parent
    return lbl
end

function HUD:Start()
    local gui = buildGui()

    -- Top-center row: time + coins
    local topRow = Instance.new("Frame")
    topRow.Name = "TopRow"
    topRow.BackgroundTransparency = 1
    topRow.Size = UDim2.new(0.6, 0, 0, 52)
    topRow.Position = UDim2.new(0.2, 0, 0, 40)
    topRow.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 12)
    layout.Parent = topRow

    local timeLbl = makeLabel(topRow, "00:00", "⏱")
    timeLbl.Size = UDim2.new(0, 220, 1, 0)
    local coinsLbl = makeLabel(topRow, "0", "💰")
    coinsLbl.Size = UDim2.new(0, 220, 1, 0)

    -- Транс-статус справа вверху
    local transLbl = makeLabel(gui, "", "✨")
    transLbl.Size = UDim2.new(0, 260, 0, 44)
    transLbl.Position = UDim2.new(1, -280, 0, 40)
    transLbl.Visible = false

    -- Кнопка магазина
    local shopBtn = Instance.new("TextButton")
    shopBtn.Name = "ShopBtn"
    shopBtn.Text = "🛒 МАГАЗИН"
    shopBtn.Font = Enum.Font.FredokaOne
    shopBtn.TextScaled = true
    shopBtn.TextColor3 = Color3.new(1, 1, 1)
    shopBtn.BackgroundColor3 = Color3.fromRGB(255, 90, 200)
    shopBtn.Size = UDim2.new(0, 200, 0, 56)
    shopBtn.Position = UDim2.new(1, -220, 1, -80)
    shopBtn.AutoButtonColor = true
    local shopCorner = Instance.new("UICorner")
    shopCorner.CornerRadius = UDim.new(0.3, 0)
    shopCorner.Parent = shopBtn
    shopBtn.Parent = gui

    shopBtn.Activated:Connect(function()
        Remotes.Event("RequestShopOpen"):FireServer()
    end)

    -- Revenge баннер (появляется при получении RevengeOffer)
    local revLbl = Instance.new("TextLabel")
    revLbl.Name = "RevengeBanner"
    revLbl.BackgroundColor3 = Color3.fromRGB(200, 30, 60)
    revLbl.BackgroundTransparency = 0.2
    revLbl.Font = Enum.Font.FredokaOne
    revLbl.TextColor3 = Color3.new(1, 1, 1)
    revLbl.TextScaled = true
    revLbl.Size = UDim2.new(0, 440, 0, 60)
    revLbl.Position = UDim2.new(0.5, -220, 0.85, 0)
    revLbl.Visible = false
    local revCorner = Instance.new("UICorner")
    revCorner.CornerRadius = UDim.new(0.3, 0)
    revCorner.Parent = revLbl
    revLbl.Parent = gui

    Remotes.Event("RevengeOffer").OnClientEvent:Connect(function(data)
        revLbl.Text = string.format(
            "💢 ОТОМСТИТЬ %s (-%d%%, %dс)",
            data.offenderName or "?",
            math.floor((data.discount or 0.5) * 100),
            data.durationSec or 30
        )
        revLbl.Visible = true
        task.delay(data.durationSec or 30, function()
            revLbl.Visible = false
        end)
    end)

    -- Трансформации
    Remotes.Event("TransformationApplied").OnClientEvent:Connect(function(stage, name)
        if stage and stage > 0 and name then
            transLbl.Text = "✨ " .. name .. " (" .. stage .. ")"
            transLbl.Visible = true
        else
            transLbl.Visible = false
        end
    end)

    -- Обновление времени/монет через leaderstats сервера
    local function syncLeaderstats()
        local ls = player:FindFirstChild("leaderstats")
        if not ls then return end
        local coinsVal = ls:FindFirstChild("Coins")
        local timeVal = ls:FindFirstChild("Time")
        if coinsVal then
            coinsLbl.Text = "💰 " .. tostring(coinsVal.Value)
            coinsVal:GetPropertyChangedSignal("Value"):Connect(function()
                coinsLbl.Text = "💰 " .. tostring(coinsVal.Value)
            end)
        end
        if timeVal then
            timeLbl.Text = "⏱ " .. tostring(timeVal.Value)
            timeVal:GetPropertyChangedSignal("Value"):Connect(function()
                timeLbl.Text = "⏱ " .. tostring(timeVal.Value)
            end)
        end
    end

    if player:FindFirstChild("leaderstats") then
        syncLeaderstats()
    end
    player.ChildAdded:Connect(function(ch)
        if ch.Name == "leaderstats" then
            task.wait(0.2)
            syncLeaderstats()
        end
    end)

    print("[JMC][Client] HUD готов")
end

return HUD
