--!strict
--[[
    OverlayEffects.lua (клиент)
    ScreenGui-оверлей поверх экрана. Отрисовывает эффекты:
      slime  — зелёные капли стекают
      spicy  — красная vignette с пульсацией
      spin   — радиальный blur-паттерн
      magnet — бело-синяя лёгкая пульсация
      float  — белая пастельная дымка (Trampoline)
      tremor — лёгкое дрожание краёв (JellyTremor)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local OverlayEffects = {}

local player = Players.LocalPlayer

local screenGui: ScreenGui? = nil
local activeFrames: { [string]: Frame } = {}

local function ensureGui()
    if screenGui and screenGui.Parent then return end
    local pg = player:WaitForChild("PlayerGui")
    local g = Instance.new("ScreenGui")
    g.Name = "JMC_Overlay"
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = 100
    g.Parent = pg
    screenGui = g
end

local function clearActive(name: string)
    local f = activeFrames[name]
    if f and f.Parent then f:Destroy() end
    activeFrames[name] = nil
end

local function makeVignette(color: Color3, transparency: number): Frame
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.fromScale(1, 1)
    frame.BorderSizePixel = 0
    frame.ZIndex = 1

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color),
        ColorSequenceKeypoint.new(1, color),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.6, transparency + 0.2),
        NumberSequenceKeypoint.new(1, transparency),
    })
    grad.Rotation = 90
    -- UIGradient на Frame: нужна подложка
    local bg = Instance.new("Frame")
    bg.BackgroundColor3 = color
    bg.BackgroundTransparency = 0
    bg.BorderSizePixel = 0
    bg.Size = UDim2.fromScale(1, 1)
    bg.Parent = frame
    grad.Parent = bg

    return frame
end

-- ===== Effect implementations =====
local function fxSlime(duration: number)
    clearActive("slime")
    ensureGui()
    local root = Instance.new("Frame")
    root.Name = "Slime"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = screenGui

    -- Зелёная vignette
    local vig = makeVignette(Color3.fromRGB(80, 220, 90), 0.35)
    vig.Parent = root

    -- Капли: спавним 12 Frame-капель, они стекают
    for i = 1, 14 do
        local drop = Instance.new("Frame")
        drop.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
        drop.BorderSizePixel = 0
        drop.Size = UDim2.fromScale(0.04 + math.random() * 0.04, 0.06 + math.random() * 0.07)
        drop.Position = UDim2.new(math.random(), 0, -0.2, 0)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = drop
        drop.Parent = root

        local tw = TweenService:Create(drop, TweenInfo.new(
            duration * (0.6 + math.random() * 0.5),
            Enum.EasingStyle.Sine, Enum.EasingDirection.In),
            { Position = UDim2.new(drop.Position.X.Scale, 0, 1.2, 0) })
        tw:Play()
    end

    activeFrames["slime"] = root
    task.delay(duration, function() clearActive("slime") end)
end

local function fxSpicy(duration: number)
    clearActive("spicy")
    ensureGui()
    local root = Instance.new("Frame")
    root.Name = "Spicy"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = screenGui

    local vig = makeVignette(Color3.fromRGB(255, 40, 40), 0.3)
    vig.Parent = root

    -- Пульсация: меняем BackgroundTransparency одного слоя циклом
    local layer = vig:FindFirstChildOfClass("Frame")
    if layer then
        task.spawn(function()
            local endTick = os.clock() + duration
            while os.clock() < endTick and layer.Parent do
                local tw = TweenService:Create(layer, TweenInfo.new(0.5),
                    { BackgroundTransparency = 0.1 })
                tw:Play(); tw.Completed:Wait()
                tw = TweenService:Create(layer, TweenInfo.new(0.5),
                    { BackgroundTransparency = 0.5 })
                tw:Play(); tw.Completed:Wait()
            end
        end)
    end

    activeFrames["spicy"] = root
    task.delay(duration, function() clearActive("spicy") end)
end

local function fxSimple(name: string, color: Color3, duration: number, intensity: number?)
    clearActive(name)
    ensureGui()
    local root = Instance.new("Frame")
    root.Name = name
    root.BackgroundColor3 = color
    root.BackgroundTransparency = 1 - (intensity or 0.2)
    root.BorderSizePixel = 0
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = screenGui

    local tw = TweenService:Create(root, TweenInfo.new(0.3), { BackgroundTransparency = 0.8 })
    tw:Play()

    activeFrames[name] = root
    task.delay(duration, function()
        local fade = TweenService:Create(root, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
        fade:Play()
        fade.Completed:Wait()
        clearActive(name)
    end)
end

local EFFECTS: { [string]: (number) -> () } = {
    slime = fxSlime,
    spicy = fxSpicy,
    spin = function(dur) fxSimple("spin", Color3.fromRGB(180, 140, 255), dur, 0.15) end,
    magnet = function(dur) fxSimple("magnet", Color3.fromRGB(120, 160, 255), dur, 0.1) end,
    float = function(dur) fxSimple("float", Color3.fromRGB(255, 220, 255), dur, 0.1) end,
    tremor = function(dur) fxSimple("tremor", Color3.fromRGB(255, 180, 120), dur, 0.08) end,
}

function OverlayEffects:Start()
    Remotes.Event("OverlayFX").OnClientEvent:Connect(function(kind: string, duration: number)
        local handler = EFFECTS[kind]
        if handler then
            handler(duration or 2)
        end
    end)
    print("[JMC][Client] OverlayEffects готов")
end

return OverlayEffects
