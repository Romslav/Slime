--!strict
--[[
    WorldBuilder.lua
    Строит «Neon Forest» — лес, атмосферу, освещение, скайбокс.
    Всё создаётся в рантайме через Instance.new.
--]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local WorldBuilder = {}

local FOREST_FOLDER_NAME = "JMC_Forest"

-- Создать/получить контейнер леса
local function getForestFolder(): Folder
    local existing = Workspace:FindFirstChild(FOREST_FOLDER_NAME)
    if existing and existing:IsA("Folder") then
        existing:ClearAllChildren()
        return existing
    end
    local folder = Instance.new("Folder")
    folder.Name = FOREST_FOLDER_NAME
    folder.Parent = Workspace
    return folder
end

--- Удаляет существующие PostEffects с нашими именами (идемпотентность)
local function resetLightingEffects()
    for _, name in ipairs({ "JMC_ColorCorrection", "JMC_Bloom", "JMC_Atmosphere", "JMC_Sky", "JMC_Blur" }) do
        local existing = Lighting:FindFirstChild(name)
        if existing then existing:Destroy() end
    end
end

local function setupLighting()
    resetLightingEffects()

    -- Базовые свойства Lighting
    Lighting.Ambient = Color3.fromRGB(60, 40, 80)
    Lighting.OutdoorAmbient = Color3.fromRGB(140, 90, 170)
    Lighting.Brightness = 2.2
    Lighting.ClockTime = 21           -- вечер для контраста с неоном
    Lighting.FogEnd = 400
    Lighting.FogStart = 120
    Lighting.FogColor = Color3.fromRGB(220, 120, 190)
    Lighting.GlobalShadows = true
    Lighting.ExposureCompensation = 0.1

    -- ColorCorrection
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "JMC_ColorCorrection"
    cc.Saturation = Config.World.ColorCorrection.Saturation
    cc.Contrast   = Config.World.ColorCorrection.Contrast
    cc.Brightness = Config.World.ColorCorrection.Brightness
    cc.TintColor  = Config.World.ColorCorrection.TintColor
    cc.Parent = Lighting

    -- Bloom
    local bloom = Instance.new("BloomEffect")
    bloom.Name = "JMC_Bloom"
    bloom.Intensity = Config.World.Bloom.Intensity
    bloom.Size      = Config.World.Bloom.Size
    bloom.Threshold = Config.World.Bloom.Threshold
    bloom.Parent = Lighting

    -- Atmosphere
    local atmos = Instance.new("Atmosphere")
    atmos.Name = "JMC_Atmosphere"
    atmos.Density = Config.World.AtmosphereDensity
    atmos.Color   = Config.World.AtmosphereColor
    atmos.Decay   = Config.World.AtmosphereDecay
    atmos.Glare   = Config.World.AtmosphereGlare
    atmos.Haze    = Config.World.AtmosphereHaze
    atmos.Parent = Lighting

    -- Sky — если asset IDs заданы, используем; иначе чистая атмосфера
    local s = Config.World.SkyboxAssetIds
    if s and (s.Up ~= 0 or s.Ft ~= 0) then
        local sky = Instance.new("Sky")
        sky.Name = "JMC_Sky"
        sky.SkyboxUp = string.format("rbxassetid://%d", s.Up)
        sky.SkyboxDn = string.format("rbxassetid://%d", s.Down)
        sky.SkyboxLf = string.format("rbxassetid://%d", s.Lf)
        sky.SkyboxRt = string.format("rbxassetid://%d", s.Rt)
        sky.SkyboxFt = string.format("rbxassetid://%d", s.Ft)
        sky.SkyboxBk = string.format("rbxassetid://%d", s.Bk)
        sky.CelestialBodiesShown = false
        sky.StarCount = 3000
        sky.Parent = Lighting
    end
end

local function createTree(center: Vector3, forest: Folder)
    local angle = Util.randf(0, math.pi * 2)
    local radius = Util.randf(Config.World.ForestRadiusMin, Config.World.ForestRadiusMax)
    local x = center.X + math.cos(angle) * radius
    local z = center.Z + math.sin(angle) * radius

    local trunkHeight = Util.randf(Config.World.TreeTrunkHeightMin, Config.World.TreeTrunkHeightMax)
    local trunkRadius = Util.randf(Config.World.TreeTrunkRadiusMin, Config.World.TreeTrunkRadiusMax)

    -- Ствол — Cylinder
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
    -- Cylinder по оси X: поставим вертикально через CFrame
    trunk.CFrame = CFrame.new(x, center.Y + trunkHeight / 2, z) * CFrame.Angles(0, 0, math.rad(90))
    trunk.Anchored = true
    trunk.CanCollide = false
    trunk.Material = Enum.Material.SmoothPlastic
    trunk.Color = Color3.fromRGB(80, 40, 90)
    trunk.Parent = forest

    -- Крона — Sphere с Neon материалом
    local canopyRadius = Util.randf(Config.World.TreeCanopyRadiusMin, Config.World.TreeCanopyRadiusMax)
    local canopy = Instance.new("Part")
    canopy.Name = "Canopy"
    canopy.Shape = Enum.PartType.Ball
    canopy.Size = Vector3.new(canopyRadius * 2, canopyRadius * 2, canopyRadius * 2)
    canopy.CFrame = CFrame.new(x, center.Y + trunkHeight + canopyRadius * 0.6, z)
    canopy.Anchored = true
    canopy.CanCollide = false
    canopy.Material = Enum.Material.Neon
    canopy.Color = Util.candyColor(
        Config.World.TreeCanopyHueRange[1],
        Config.World.TreeCanopyHueRange[2]
    )
    canopy.Transparency = Util.randf(0, 0.15)
    canopy.Parent = forest

    -- Точечный свет внутри кроны — чтобы неон действительно светил
    local light = Instance.new("PointLight")
    light.Brightness = 1.6
    light.Range = canopyRadius * 3
    light.Color = canopy.Color
    light.Parent = canopy
end

local function growForest(center: Vector3)
    local forest = getForestFolder()
    for _ = 1, Config.World.ForestTreeCount do
        createTree(center, forest)
    end
end

-- Рассеянные светящиеся «спорки» по небу для глубины сцены
local function addFireflies(center: Vector3, forest: Folder)
    for _ = 1, 60 do
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.6, 0.6, 0.6)
        p.Material = Enum.Material.Neon
        p.Color = Util.candyColor(0.1, 0.9)
        p.Anchored = true
        p.CanCollide = false
        p.Transparency = 0.2

        local angle = Util.randf(0, math.pi * 2)
        local r = Util.randf(30, 200)
        local h = Util.randf(center.Y + 10, center.Y + 90)
        p.Position = Vector3.new(center.X + math.cos(angle) * r, h, center.Z + math.sin(angle) * r)
        p.Name = "Firefly"
        p.Parent = forest
    end
end

function WorldBuilder:Start()
    setupLighting()

    -- По умолчанию центр мира (0,0,0); PlatformEngine сам подстроит высоту Y
    local center = Vector3.new(0, 0, 0)
    growForest(center)

    local forest = Workspace:FindFirstChild(FOREST_FOLDER_NAME)
    if forest and forest:IsA("Folder") then
        addFireflies(center, forest)
    end

    -- Убедимся, что у Workspace правильная гравитация
    Workspace.Gravity = Config.World.DefaultGravity
end

--- Временно изменить гравитацию (для события Trampoline)
function WorldBuilder:SetGravity(g: number)
    Workspace.Gravity = g
end

--- Восстановить гравитацию
function WorldBuilder:ResetGravity()
    Workspace.Gravity = Config.World.DefaultGravity
end

return WorldBuilder
