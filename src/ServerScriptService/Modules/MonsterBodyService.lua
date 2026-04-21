--!strict
--[[
    MonsterBodyService.lua (v3.0)
    Полностью заменяет PlatformEngine. Монстр — это и есть платформа.

    Владеет всем:
        - OuterShell (Glass, collidable)  — главный коллайдер с желейной физикой
        - InnerFlesh (SmoothPlastic, non-collidable) — внутренний объём
        - Core (Neon, pulsing)              — пульсирующее ядро с PointLight
        - Eyes (12)                          — следят за игроками + моргают
        - Tentacles (9)                      — покачиваются по синусу
        - Segments (Config.Platform.SegmentCount) — для TastyBite

    Публичный API (совместим с бывшим PlatformEngine):
        :Start()
        :GetCenter() -> Vector3
        :GetRadius() -> number
        :GetSurfaceY() -> number
        :GetBasePart() -> BasePart?      -- OuterShell
        :GetSegments() -> {BasePart}
        :GetFolder() -> Folder?
        :SetElasticity(e), :ResetElasticity()
        :SetFriction(f), :ResetFriction()
        :FlashColor(color, duration)
        :GetCorePart() -> BasePart?       -- новое
        .PulseTick  Signal                 -- fires каждую полуфазу
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local MonsterBodyService = {}
MonsterBodyService.PulseTick = Signal.new()

local FOLDER_NAME = "JMC_Monster"

local state = {
	folder = nil :: Folder?,
	center = Vector3.new(0, 8, 0),
	radius = Config.Platform.Radius,
	shell = nil :: BasePart?, -- главный коллайдер (= PlatformEngine.JellyBase)
	flesh = nil :: BasePart?,
	core = nil :: BasePart?,
	coreLight = nil :: PointLight?,
	segments = {} :: { BasePart },
	eyes = {} :: { { eyeball: BasePart, pupil: BasePart, lid: BasePart, baseCFrame: CFrame } },
	tentacleSegments = {} :: { { part: BasePart, base: CFrame, phase: number, amplitude: number } },
	originalElasticity = Config.Platform.Elasticity,
	pulseRunning = false,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function ensureFolder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

-- ---------------------------------------------------------------------
-- Слои тела
-- ---------------------------------------------------------------------

local function buildShell(folder: Folder, center: Vector3): BasePart
	local radius = Config.Platform.Radius
	local height = Config.Platform.Height

	local shell = Instance.new("Part")
	shell.Name = "OuterShell" -- бывший JellyBase
	shell.Shape = Enum.PartType.Cylinder
	-- Cylinder ориентируется по оси X. Положим «блином»: X=height, Y/Z=diameter.
	shell.Size = Vector3.new(height, radius * 2, radius * 2)
	shell.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	shell.Anchored = true
	shell.CanCollide = true
	shell.Material = Config.Platform.Material
	shell.Transparency = Config.Platform.Transparency
	shell.Reflectance = Config.Platform.Reflectance
	shell.Color = Config.Platform.Color

	shell.CustomPhysicalProperties = PhysicalProperties.new(
		Config.Platform.Density,
		Config.Platform.Friction,
		Config.Platform.Elasticity,
		Config.Platform.FrictionWeight,
		Config.Platform.ElasticityWeight
	)

	shell.Parent = folder

	-- Декоративные «пузырьки» внутри желе
	local attachment = Instance.new("Attachment")
	attachment.Parent = shell

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "JellyBubbles"
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Rate = 30
	particles.Lifetime = NumberRange.new(2, 4)
	particles.Speed = NumberRange.new(0.5, 1)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.LightEmission = 0.18
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 255))
	particles.Rotation = NumberRange.new(0, 360)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = attachment

	return shell
end

local function buildFlesh(folder: Folder, center: Vector3): BasePart
	local cfg = Config.Monster.InnerFlesh
	local diameter = Config.Platform.Radius * 2 - cfg.DiameterOffset
	local height = Config.Platform.Height - cfg.HeightOffset

	local flesh = Instance.new("Part")
	flesh.Name = "InnerFlesh"
	flesh.Shape = Enum.PartType.Cylinder
	flesh.Size = Vector3.new(height, diameter, diameter)
	flesh.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	flesh.Anchored = true
	flesh.CanCollide = false
	flesh.CastShadow = false
	flesh.Material = cfg.Material
	flesh.Transparency = cfg.Transparency
	flesh.Color = cfg.Color
	flesh.Parent = folder
	return flesh
end

local function buildCore(folder: Folder, center: Vector3): (BasePart, PointLight)
	local cfg = Config.Monster.Core
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(cfg.Size, cfg.Size, cfg.Size)
	-- Ядро внутри платформы, слегка ниже геометрического центра — светится сквозь glass
	core.Position = center + Vector3.new(0, cfg.VerticalOffset or 0, 0)
	core.Anchored = true
	core.CanCollide = false
	core.Material = cfg.Material
	core.Color = cfg.Color
	core.Transparency = cfg.PulseMin
	core.CastShadow = false
	core.Parent = folder

	local light = Instance.new("PointLight")
	light.Brightness = cfg.LightBrightness
	light.Range = cfg.LightRange
	light.Color = cfg.Color
	light.Shadows = false
	light.Parent = core

	return core, light
end

-- ---------------------------------------------------------------------
-- Сегменты для TastyBite (перенесены из бывшего PlatformEngine)
-- ---------------------------------------------------------------------

local function buildSegments(folder: Folder, center: Vector3): { BasePart }
	local segments = {}
	local count = Config.Platform.SegmentCount
	local radius = Config.Platform.Radius
	local height = Config.Platform.Height
	local surfaceY = center.Y + height / 2 + 0.05

	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local midAngle = angle + math.pi / count
		local seg = Instance.new("Part")
		seg.Name = string.format("Segment_%d", i)
		seg.Shape = Enum.PartType.Block
		seg.Size = Vector3.new(radius * 0.9, 0.2, radius * 0.75 * math.sin(math.pi / count) * 2)
		seg.CFrame = CFrame.new(
			center.X + math.cos(midAngle) * radius * 0.5,
			surfaceY,
			center.Z + math.sin(midAngle) * radius * 0.5
		) * CFrame.Angles(0, -midAngle, 0)
		seg.Anchored = true
		seg.CanCollide = false
		seg.Transparency = 1
		seg.Color = Color3.fromRGB(255, 80, 80)
		seg.Material = Enum.Material.Neon
		seg.Parent = folder

		local tag = Instance.new("NumberValue")
		tag.Name = "SegmentIndex"
		tag.Value = i
		tag.Parent = seg

		table.insert(segments, seg)
	end

	return segments
end

-- ---------------------------------------------------------------------
-- Глаза
-- ---------------------------------------------------------------------

local function buildEye(parent: Folder, center: Vector3, angle: number, index: number, surfaceY: number)
	local cfg = Config.Monster.Eyes
	local px = center.X + math.cos(angle) * cfg.Radius
	local pz = center.Z + math.sin(angle) * cfg.Radius
	local py = surfaceY + cfg.Height
	local eyePos = Vector3.new(px, py, pz)

	local outwardDir = (eyePos - center).Unit
	local baseCFrame = CFrame.lookAt(eyePos, eyePos + outwardDir)

	local model = Instance.new("Model")
	model.Name = string.format("Eye_%d", index)
	model.Parent = parent

	local eyeball = Instance.new("Part")
	eyeball.Name = "Eyeball"
	eyeball.Shape = Enum.PartType.Ball
	eyeball.Size = Vector3.new(cfg.EyeballSize, cfg.EyeballSize, cfg.EyeballSize)
	eyeball.CFrame = baseCFrame
	eyeball.Anchored = true
	eyeball.CanCollide = false
	eyeball.Material = Enum.Material.SmoothPlastic
	eyeball.Color = Color3.fromRGB(245, 245, 245)
	eyeball.CastShadow = false
	eyeball.Parent = model

	local pupil = Instance.new("Part")
	pupil.Name = "Pupil"
	pupil.Shape = Enum.PartType.Ball
	pupil.Size = Vector3.new(cfg.PupilSize, cfg.PupilSize, cfg.PupilSize)
	pupil.CFrame = baseCFrame * CFrame.new(0, 0, -cfg.EyeballSize * 0.45)
	pupil.Anchored = true
	pupil.CanCollide = false
	pupil.Material = Enum.Material.Neon
	pupil.Color = Color3.fromRGB(30, 0, 40)
	pupil.CastShadow = false
	pupil.Parent = model

	local lid = Instance.new("Part")
	lid.Name = "Eyelid"
	lid.Shape = Enum.PartType.Ball
	lid.Size = Vector3.new(cfg.EyeballSize * 1.02, cfg.EyeballSize * 1.02, cfg.EyeballSize * 1.02)
	lid.CFrame = baseCFrame
	lid.Anchored = true
	lid.CanCollide = false
	lid.Material = Enum.Material.SmoothPlastic
	lid.Color = Config.Monster.InnerFlesh.Color
	lid.Transparency = 1
	lid.CastShadow = false
	lid.Parent = model

	table.insert(state.eyes, {
		eyeball = eyeball,
		pupil = pupil,
		lid = lid,
		baseCFrame = baseCFrame,
	})
end

local function buildEyes(folder: Folder, center: Vector3, surfaceY: number)
	local eyesFolder = Instance.new("Folder")
	eyesFolder.Name = "Eyes"
	eyesFolder.Parent = folder

	local count = Config.Monster.Eyes.Count
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		buildEye(eyesFolder, center, angle, i, surfaceY)
	end
end

-- ---------------------------------------------------------------------
-- Щупальца
-- ---------------------------------------------------------------------

local function buildTentacle(parent: Folder, center: Vector3, angle: number, index: number, surfaceY: number)
	local cfg = Config.Monster.Tentacles
	local baseX = center.X + math.cos(angle) * cfg.PlacementRadius
	local baseZ = center.Z + math.sin(angle) * cfg.PlacementRadius
	-- Щупальца — это «ноги» монстра, свисают ВНИЗ от нижней грани платформы
	local bottomY = center.Y - Config.Platform.Height / 2

	local model = Instance.new("Model")
	model.Name = string.format("Tentacle_%d", index)
	model.Parent = parent

	-- Слегка отклоняем кончик наружу для естественного силуэта
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))

	for segIdx = 1, cfg.Segments do
		-- Идём вниз: 1-й сегмент сразу под платформой, последний — у земли
		local segY = bottomY - (segIdx - 0.5) * cfg.SegmentLength
		local pos = Vector3.new(baseX, segY, baseZ) + outward * (segIdx - 1) * 0.6

		local seg = Instance.new("Part")
		seg.Name = string.format("Segment_%d", segIdx)
		seg.Shape = Enum.PartType.Cylinder
		-- Сужение к кончику: верхний сегмент толстый, нижний тонкий
		local thicknessFactor = 1 - (segIdx - 1) * 0.12
		seg.Size = Vector3.new(
			cfg.SegmentLength,
			cfg.SegmentThickness * thicknessFactor,
			cfg.SegmentThickness * thicknessFactor
		)
		-- Cylinder лежит по X → поставим вертикально
		seg.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		seg.Anchored = true
		seg.CanCollide = false
		seg.Material = Enum.Material.SmoothPlastic
		seg.Color = cfg.Color:Lerp(Color3.fromRGB(255, 150, 255), (segIdx - 1) / cfg.Segments)
		seg.Transparency = 0.15
		seg.CastShadow = false
		seg.Parent = model

		table.insert(state.tentacleSegments, {
			part = seg,
			base = seg.CFrame,
			phase = angle + segIdx * 0.45,
			-- Кончик качается сильнее основания
			amplitude = cfg.WaveAmplitude * segIdx,
		})
	end
end

local function buildTentacles(folder: Folder, center: Vector3, surfaceY: number)
	local tFolder = Instance.new("Folder")
	tFolder.Name = "Tentacles"
	tFolder.Parent = folder

	local count = Config.Monster.Tentacles.Count
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		buildTentacle(tFolder, center, angle, i, surfaceY)
	end
end

-- ---------------------------------------------------------------------
-- Рантайм: пульсация, слежение, покачивание, pulse-дыхание shell
-- ---------------------------------------------------------------------

local function findClosestPlayerPosition(fromPos: Vector3, range: number): Vector3?
	local best: Vector3? = nil
	local bestDist = range
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local d = (hrp.Position - fromPos).Magnitude
			if d < bestDist then
				bestDist = d
				best = hrp.Position
			end
		end
	end
	return best
end

local function startCorePulse()
	local cfg = Config.Monster.Core
	local core = state.core
	local light = state.coreLight
	if not core or not light then
		return
	end

	RunService.Heartbeat:Connect(function()
		if not core.Parent then
			return
		end
		local t = tick() * (2 * math.pi / cfg.PulsePeriod)
		local k = (math.sin(t) + 1) / 2
		core.Transparency = lerp(cfg.PulseMin, cfg.PulseMax, k)
		light.Range = lerp(cfg.LightRange * 0.88, cfg.LightRange * 1.05, k)
		light.Brightness = lerp(cfg.LightBrightness * 0.82, cfg.LightBrightness * 1.08, k)
	end)
end

local function startEyeTracking()
	local cfg = Config.Monster.Eyes
	local interval = 1 / cfg.LookUpdateHz
	local elapsed = 0
	local pupilOffset = cfg.EyeballSize * 0.45

	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < interval then
			return
		end
		elapsed = 0
		local now = tick()
		for idx, eye in ipairs(state.eyes) do
			if not eye.eyeball.Parent then
				continue
			end
			local eyePos = eye.eyeball.Position
			local target = findClosestPlayerPosition(eyePos, cfg.LookRange)
			local lookDir: Vector3
			if target then
				lookDir = (target - eyePos).Unit
			else
				local seed = idx * 7.13
				local nx = math.noise(now * cfg.WanderSpeed, seed)
				local ny = math.noise(now * cfg.WanderSpeed, seed + 13.1)
				local nz = math.noise(now * cfg.WanderSpeed, seed + 27.7)
				lookDir = Vector3.new(nx, ny * 0.2, nz).Unit
			end
			eye.pupil.CFrame = CFrame.new(eyePos + lookDir * pupilOffset)
		end
	end)
end

local function scheduleBlinking()
	local cfg = Config.Monster.Eyes
	for _, eye in ipairs(state.eyes) do
		task.spawn(function()
			while eye.lid.Parent do
				local wait = cfg.BlinkMinInterval + math.random() * (cfg.BlinkMaxInterval - cfg.BlinkMinInterval)
				task.wait(wait)
				if not eye.lid.Parent then
					break
				end
				local tweenDown = TweenService:Create(
					eye.lid,
					TweenInfo.new(cfg.BlinkDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Transparency = 0 }
				)
				tweenDown:Play()
				tweenDown.Completed:Wait()
				local tweenUp = TweenService:Create(
					eye.lid,
					TweenInfo.new(cfg.BlinkDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
					{ Transparency = 1 }
				)
				tweenUp:Play()
			end
		end)
	end
end

local function startTentacleWave()
	local cfg = Config.Monster.Tentacles
	RunService.Heartbeat:Connect(function()
		local t = tick() * cfg.WaveSpeed
		for _, seg in ipairs(state.tentacleSegments) do
			if not seg.part.Parent then
				continue
			end
			local sway = math.sin(t + seg.phase) * seg.amplitude
			local rollAxis = CFrame.Angles(sway, 0, sway * 0.6)
			seg.part.CFrame = seg.base * rollAxis
		end
	end)
end

local function startShellPulse()
	if state.pulseRunning then
		return
	end
	state.pulseRunning = true
	local shell = state.shell
	if not shell then
		return
	end

	local originalSize = shell.Size
	local pulseSize = originalSize * (1 + Config.Platform.PulseScale)

	task.spawn(function()
		while state.pulseRunning and shell.Parent do
			local tween = TweenService:Create(
				shell,
				TweenInfo.new(Config.Platform.PulseDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Size = pulseSize }
			)
			tween:Play()
			tween.Completed:Wait()
			MonsterBodyService.PulseTick:Fire("expand")
			if not state.pulseRunning or not shell.Parent then
				break
			end
			tween = TweenService:Create(
				shell,
				TweenInfo.new(Config.Platform.PulseDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Size = originalSize }
			)
			tween:Play()
			tween.Completed:Wait()
			MonsterBodyService.PulseTick:Fire("contract")
		end
	end)
end

-- ---------------------------------------------------------------------
-- Воздушная пушка — запускает игроков с нижнего уровня на платформу
-- ---------------------------------------------------------------------

local function buildAirCannon(folder: Folder, center: Vector3)
	local cfg = Config.AirCannon
	local platH = Config.Platform.Height
	local platR = Config.Platform.Radius
	local bottomY = center.Y - platH / 2
	local surfaceY = center.Y + platH / 2

	-- Пушка на оси Z (не X), чтобы не перекрывала билборд
	local sideOffset = platR + cfg.SideDistance
	local cannonBase = Vector3.new(center.X, bottomY - cfg.BodyHeight / 2, center.Z + sideOffset)

	-- Вспомогательная функция: вертикальный цилиндр в нужной точке
	local function vertCylinder(pos: Vector3, h: number, r: number): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(h, r * 2, r * 2)
		-- Cylinder по оси X → поворачиваем на 90° чтобы стоял вертикально
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Parent = folder
		return p
	end

	-- Корпус: голубое стеклянное желе
	local body = vertCylinder(cannonBase, cfg.BodyHeight, cfg.BodyRadius)
	body.Name = "AirCannonBody"
	body.CanCollide = true
	body.Material = Enum.Material.Glass
	body.Color = cfg.BodyColor
	body.Transparency = 0.4
	body.Reflectance = 0.3

	local bodyLight = Instance.new("PointLight")
	bodyLight.Color = cfg.BodyColor
	bodyLight.Brightness = 1.35
	bodyLight.Range = 18
	bodyLight.Parent = body

	-- Сопло: неоновое кольцо на верхушке, чуть шире корпуса
	local nozzleCenter = cannonBase + Vector3.new(0, cfg.BodyHeight / 2 + cfg.NozzleHeight / 2, 0)
	local nozzle = vertCylinder(nozzleCenter, cfg.NozzleHeight, cfg.NozzleRadius)
	nozzle.Name = "AirCannonNozzle"
	nozzle.Material = Enum.Material.Neon
	nozzle.Color = cfg.NozzleColor
	nozzle.Transparency = 0.1

	-- Декоративные кольца вдоль корпуса (все используют cannonBase как X/Z)
	for i = 1, cfg.RingCount do
		local t = i / (cfg.RingCount + 1)
		local ringPos = Vector3.new(cannonBase.X, cannonBase.Y - cfg.BodyHeight / 2 + cfg.BodyHeight * t, cannonBase.Z)
		local ring = vertCylinder(ringPos, 0.8, cfg.BodyRadius + 0.9)
		ring.Name = string.format("CannonRing_%d", i)
		ring.Material = Enum.Material.Neon
		ring.Color = cfg.NozzleColor
		ring.Transparency = 0.2
	end

	-- Частицы воздуха из сопла (бьют вверх)
	local nozzleAttach = Instance.new("Attachment")
	-- У Cylinder вертикальная ось после поворота совпадает с локальной X,
	-- поэтому разворачиваем Attachment так, чтобы EmissionDirection.Top смотрел вверх.
	nozzleAttach.CFrame = CFrame.new(cfg.NozzleHeight / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
	nozzleAttach.Parent = nozzle

	local airParticles = Instance.new("ParticleEmitter")
	airParticles.Name = "AirBlast"
	airParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	airParticles.Rate = 80
	airParticles.Lifetime = NumberRange.new(0.5, 1.5)
	airParticles.Speed = NumberRange.new(12, 30)
	airParticles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.4, 1.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	airParticles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	airParticles.Color = ColorSequence.new(Color3.fromRGB(200, 245, 255), Color3.fromRGB(255, 255, 255))
	airParticles.LightEmission = 0.18
	airParticles.EmissionDirection = Enum.NormalId.Top
	airParticles.SpreadAngle = Vector2.new(16, 16)
	airParticles.RotSpeed = NumberRange.new(-90, 90)
	airParticles.Rotation = NumberRange.new(0, 360)
	airParticles.Parent = nozzleAttach

	-- Зона поимки: небольшая локальная область под самой пушкой.
	-- Срабатывает только со стороны, где пушка установлена.
	local catchY = bottomY - cfg.CatchDepth
	local triggerCenter = Vector3.new(cannonBase.X, catchY, cannonBase.Z)
	local catchZone = Instance.new("Part")
	catchZone.Name = "AirCannonTrigger"
	catchZone.Shape = Enum.PartType.Cylinder
	-- Cylinder лежит горизонтально (ось X = длина → поворот 90° по Z)
	catchZone.Size = Vector3.new(4, cfg.TriggerRadius * 2, cfg.TriggerRadius * 2)
	catchZone.CFrame = CFrame.new(triggerCenter) * CFrame.Angles(0, 0, math.rad(90))
	catchZone.Anchored = true
	catchZone.CanCollide = false
	catchZone.Transparency = 1
	catchZone.CastShadow = false
	catchZone.Parent = folder

	local cooldowns: { [Player]: number } = {}
	local launchOrigin = nozzleCenter + Vector3.new(0, cfg.NozzleHeight / 2 + 1.75, 0)
	local launchFlat = Vector3.new(center.X - launchOrigin.X, 0, center.Z - launchOrigin.Z)
	local launchHorizDir = launchFlat.Magnitude > 0.5 and launchFlat.Unit or Vector3.new(0, 0, -1)

	local function clearLaunchAssist(hrp: BasePart)
		local existing = hrp:FindFirstChild("AirCannonLaunch")
		if existing then
			existing:Destroy()
		end
	end

	local function launchPlayer(player: Player, char: Model, humanoid: Humanoid, hrp: BasePart)
		local now = tick()
		if (cooldowns[player] or 0) + cfg.Cooldown > now then
			return
		end

		cooldowns[player] = now

		local angle = math.rad(cfg.LaunchAngle)
		local vVert = cfg.LaunchSpeed * math.sin(angle)
		local vHoriz = cfg.LaunchSpeed * math.cos(angle)
		local launchVelocity = launchHorizDir * vHoriz + Vector3.new(0, vVert, 0)

		clearLaunchAssist(hrp)

		-- Всегда ставим персонажа в сопло, чтобы толчок шёл из самой пушки,
		-- а траектория не упиралась в нижнюю часть платформы.
		char:PivotTo(CFrame.lookAt(launchOrigin, launchOrigin + launchHorizDir))
		hrp.AssemblyLinearVelocity = Vector3.zero
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		hrp:ApplyImpulse(launchVelocity * hrp.AssemblyMass)

		local bv = Instance.new("BodyVelocity")
		bv.Name = "AirCannonLaunch"
		bv.Velocity = launchVelocity
		bv.MaxForce = Vector3.new(2e6, 2e6, 2e6)
		bv.P = 1e6
		bv.Parent = hrp

		task.delay(0.35, function()
			if bv and bv.Parent then
				bv:Destroy()
			end
		end)
	end

	local function tryLaunchFromHit(hit: BasePart)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char or not char:IsA("Model") then
			return
		end

		local player = Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp or not hrp:IsA("BasePart") then
			return
		end

		launchPlayer(player, char, humanoid, hrp)
	end

	body.Touched:Connect(tryLaunchFromHit)
	nozzle.Touched:Connect(tryLaunchFromHit)
	catchZone.Touched:Connect(tryLaunchFromHit)

	-- Heartbeat-поллинг: как fallback для быстро падающих игроков,
	-- если Touched пропустил столкновение.
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if not char then
				continue
			end

			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not hrp or not humanoid then
				continue
			end

			local pos = hrp.Position
			local dx = pos.X - triggerCenter.X
			local dz = pos.Z - triggerCenter.Z
			local radialDist = math.sqrt(dx * dx + dz * dz)
			local isBelowPlatform = pos.Y <= bottomY
			local isFalling = hrp.AssemblyLinearVelocity.Y <= 0

			if isBelowPlatform and isFalling and radialDist <= cfg.TriggerRadius then
				launchPlayer(player, char, humanoid, hrp)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p: Player)
		cooldowns[p] = nil
	end)
end

-- ---------------------------------------------------------------------
-- Публичный API (совместимый с бывшим PlatformEngine)
-- ---------------------------------------------------------------------

function MonsterBodyService:Start()
	local folder = ensureFolder()
	state.folder = folder

	local center = Vector3.new(0, 8, 0)
	state.center = center
	state.radius = Config.Platform.Radius
	local surfaceY = center.Y + Config.Platform.Height / 2

	-- SpawnLocation прямо на поверхности монстра — чтобы респавн возвращал игрока
	-- на платформу после падения. Единственный спавн в игре.
	local oldSpawn = Workspace:FindFirstChild("JMC_Spawn")
	if oldSpawn then
		oldSpawn:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "JMC_Spawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Position = Vector3.new(center.X, surfaceY + 1, center.Z)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = Workspace

	state.shell = buildShell(folder, center)
	state.flesh = buildFlesh(folder, center)
	local core, light = buildCore(folder, center)
	state.core = core
	state.coreLight = light
	state.segments = buildSegments(folder, center)
	buildEyes(folder, center, surfaceY)
	buildTentacles(folder, center, surfaceY)
	buildAirCannon(folder, center)

	startShellPulse()
	startCorePulse()
	startEyeTracking()
	scheduleBlinking()
	startTentacleWave()

	print(
		string.format(
			"[JMC][Monster] Платформа-монстр собрана: R=%.1f, H=%.1f, segments=%d, eyes=%d, tentacleSegs=%d",
			state.radius,
			Config.Platform.Height,
			#state.segments,
			#state.eyes,
			#state.tentacleSegments
		)
	)
end

function MonsterBodyService:GetCenter(): Vector3
	return state.center
end

function MonsterBodyService:GetRadius(): number
	return state.radius
end

function MonsterBodyService:GetSurfaceY(): number
	return state.center.Y + Config.Platform.Height / 2
end

function MonsterBodyService:GetBasePart(): BasePart?
	return state.shell
end

function MonsterBodyService:GetSegments(): { BasePart }
	return state.segments
end

function MonsterBodyService:GetFolder(): Folder?
	return state.folder
end

function MonsterBodyService:GetCorePart(): BasePart?
	return state.core
end

function MonsterBodyService:SetElasticity(e: number)
	local shell = state.shell
	if not shell then
		return
	end
	shell.CustomPhysicalProperties = PhysicalProperties.new(
		Config.Platform.Density,
		Config.Platform.Friction,
		e,
		Config.Platform.FrictionWeight,
		Config.Platform.ElasticityWeight
	)
end

function MonsterBodyService:ResetElasticity()
	self:SetElasticity(state.originalElasticity)
end

function MonsterBodyService:SetFriction(f: number)
	local shell = state.shell
	if not shell then
		return
	end
	shell.CustomPhysicalProperties = PhysicalProperties.new(
		Config.Platform.Density,
		f,
		state.originalElasticity,
		Config.Platform.FrictionWeight,
		Config.Platform.ElasticityWeight
	)
end

function MonsterBodyService:ResetFriction()
	self:SetFriction(Config.Platform.Friction)
end

function MonsterBodyService:FlashColor(color: Color3, duration: number)
	local shell = state.shell
	if not shell then
		return
	end
	local originalColor = shell.Color
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Sine)
	local toWarn = TweenService:Create(shell, info, { Color = color })
	toWarn:Play()
	task.delay(duration, function()
		if not shell.Parent then
			return
		end
		local back = TweenService:Create(shell, info, { Color = originalColor })
		back:Play()
	end)
end

return MonsterBodyService
