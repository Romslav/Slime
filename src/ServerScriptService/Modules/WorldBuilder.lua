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
local GROUND_PART_NAME = "JMC_Ground"

-- Удаляем стандартные объекты шаблонной карты Roblox, чтобы наш мир не
-- наслаивался поверх Baseplate из .rbxl/.rbxlx сцены Studio.
local function clearTemplateMap()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("SpawnLocation") and child.Name ~= "JMC_Spawn" then
			child:Destroy()
		end
	end
end

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
	for _, child in ipairs(Lighting:GetChildren()) do
		if
			child:IsA("ColorCorrectionEffect")
			or child:IsA("BloomEffect")
			or child:IsA("Atmosphere")
			or child:IsA("Sky")
			or child:IsA("BlurEffect")
			or child:IsA("SunRaysEffect")
		then
			child:Destroy()
		end
	end
end

local function setupLighting()
	resetLightingEffects()

	-- Дневной свет с мягким розово-фиолетовым градиентом.
	Lighting.Ambient = Color3.fromRGB(165, 145, 176)
	Lighting.OutdoorAmbient = Color3.fromRGB(196, 180, 215)
	Lighting.Brightness = 2.6
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 35
	Lighting.FogEnd = 720
	Lighting.FogStart = 220
	Lighting.FogColor = Color3.fromRGB(246, 223, 242)
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.15
	Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 235)
	Lighting.ColorShift_Bottom = Color3.fromRGB(201, 178, 243)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5

	-- ColorCorrection
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "JMC_ColorCorrection"
	cc.Saturation = Config.World.ColorCorrection.Saturation
	cc.Contrast = Config.World.ColorCorrection.Contrast
	cc.Brightness = Config.World.ColorCorrection.Brightness
	cc.TintColor = Config.World.ColorCorrection.TintColor
	cc.Parent = Lighting

	-- Bloom
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "JMC_Bloom"
	bloom.Intensity = Config.World.Bloom.Intensity
	bloom.Size = Config.World.Bloom.Size
	bloom.Threshold = Config.World.Bloom.Threshold
	bloom.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "JMC_SunRays"
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.2
	sunRays.Parent = Lighting

	-- Atmosphere
	local atmos = Instance.new("Atmosphere")
	atmos.Name = "JMC_Atmosphere"
	atmos.Density = Config.World.AtmosphereDensity
	atmos.Color = Config.World.AtmosphereColor
	atmos.Decay = Config.World.AtmosphereDecay
	atmos.Glare = Config.World.AtmosphereGlare
	atmos.Haze = Config.World.AtmosphereHaze
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

local function createGround(center: Vector3)
	local existing = Workspace:FindFirstChild(GROUND_PART_NAME)
	if existing then
		existing:Destroy()
	end

	local ground = Instance.new("Part")
	ground.Name = GROUND_PART_NAME
	ground.Size = Vector3.new(900, 20, 900)
	ground.Position = Vector3.new(center.X, -10, center.Z)
	ground.Anchored = true
	ground.Material = Enum.Material.Grass
	ground.Color = Color3.fromRGB(106, 181, 82)
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.BottomSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace
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
	trunk.Material = Config.World.TreeTrunkMaterial
	trunk.Color = Util.candyColor(Config.World.TreeCanopyHueRange[1], Config.World.TreeCanopyHueRange[2])
	trunk.Transparency = 0.08
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
	canopy.Material = Config.World.TreeCanopyMaterial
	canopy.Color = Util.candyColor(Config.World.TreeCanopyHueRange[1], Config.World.TreeCanopyHueRange[2])
	canopy.Reflectance = 0.04
	canopy.Transparency = Util.randf(0.26, 0.46)
	canopy.Parent = forest

	-- Точечный свет внутри кроны — чтобы неон действительно светил
	local light = Instance.new("PointLight")
	light.Brightness = 0.55
	light.Range = canopyRadius * 1.8
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
		p.Transparency = 0.5

		local angle = Util.randf(0, math.pi * 2)
		local r = Util.randf(30, 200)
		local h = Util.randf(center.Y + 10, center.Y + 90)
		p.Position = Vector3.new(center.X + math.cos(angle) * r, h, center.Z + math.sin(angle) * r)
		p.Name = "Firefly"
		p.Parent = forest
	end
end

--- Светящаяся пыльца вокруг монстра. Вызывается после того, как MonsterBodyService
--- собрал тело (иначе ядро ещё не существует). Идемпотентна.
function WorldBuilder:SpawnPollen()
	local monsterFolder = Workspace:FindFirstChild("JMC_Monster")
	local core = monsterFolder and monsterFolder:FindFirstChild("Core")
	if not (core and core:IsA("BasePart")) then
		warn("[JMC][World] SpawnPollen: Core монстра не найден")
		return
	end

	local existing = core:FindFirstChild("PollenAttachment")
	if existing then
		existing:Destroy()
	end

	local attach = Instance.new("Attachment")
	attach.Name = "PollenAttachment"
	attach.Parent = core

	local cfg = Config.World.Pollen
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Pollen"
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Rate = cfg.Rate
	particles.Lifetime = cfg.Lifetime
	particles.Speed = NumberRange.new(cfg.SpeedMin, cfg.SpeedMax)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.6),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 220, 255), Color3.fromRGB(255, 182, 220))
	particles.LightEmission = cfg.LightEmission
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rotation = NumberRange.new(0, 360)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Parent = attach
end

function WorldBuilder:Start()
	clearTemplateMap()
	setupLighting()

	-- По умолчанию центр мира (0,0,0); PlatformEngine сам подстроит высоту Y
	local center = Vector3.new(0, 0, 0)
	createGround(center)
	growForest(center)

	local forest = Workspace:FindFirstChild(FOREST_FOLDER_NAME)
	if forest and forest:IsA("Folder") then
		addFireflies(center, forest)
	end

	-- Пыльца вокруг монстра вызывается из Main после MonsterBodyService:Start()
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
