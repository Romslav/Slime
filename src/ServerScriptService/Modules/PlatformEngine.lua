--!strict
--[[
    PlatformEngine.lua
    Желейная платформа — сердце игры. Полностью скриптовая:
        - одна большая base-part (Cylinder, Glass)
        - 8 сегментов-секторов поверх для Tasty Bite
        - Pulse-дыхание через TweenService
        - CustomPhysicalProperties для «скользкости»

    Публичный API:
        Platform:Start()
        Platform:GetCenter() -> Vector3
        Platform:GetRadius() -> number
        Platform:GetSurfaceY() -> number
        Platform:GetBasePart() -> BasePart
        Platform:GetSegments() -> {BasePart}
        Platform:SetElasticity(e)
        Platform:ResetElasticity()
        Platform.PulseTick  -> Signal (Fires каждую полуфазу)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local PlatformEngine = {}

local FOLDER_NAME = "JMC_Platform"

-- Состояние модуля
local state: {
    folder: Folder?,
    base: BasePart?,
    segments: { BasePart },
    center: Vector3,
    radius: number,
    originalElasticity: number,
    pulseRunning: boolean,
} = {
    folder = nil,
    base = nil,
    segments = {},
    center = Vector3.new(0, 8, 0),
    radius = Config.Platform.Radius,
    originalElasticity = Config.Platform.Elasticity,
    pulseRunning = false,
}

PlatformEngine.PulseTick = Signal.new()

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

local function buildBase(folder: Folder, center: Vector3): BasePart
    local radius = Config.Platform.Radius
    local height = Config.Platform.Height

    local base = Instance.new("Part")
    base.Name = "JellyBase"
    base.Shape = Enum.PartType.Cylinder
    -- Cylinder ориентируется по оси X. Нам нужен «блин» — плоский диск.
    -- Size.X = height (тонкий), Y/Z = diameter.
    base.Size = Vector3.new(height, radius * 2, radius * 2)
    -- Положим лёжа (ось X → вертикаль)
    base.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
    base.Anchored = true
    base.CanCollide = true
    base.Material = Config.Platform.Material
    base.Transparency = Config.Platform.Transparency
    base.Reflectance = Config.Platform.Reflectance
    base.Color = Config.Platform.Color

    base.CustomPhysicalProperties = PhysicalProperties.new(
        Config.Platform.Density,
        Config.Platform.Friction,
        Config.Platform.Elasticity,
        Config.Platform.FrictionWeight,
        Config.Platform.ElasticityWeight
    )

    base.Parent = folder

    -- Декоративные «пузырьки» внутри желе
    local attachment = Instance.new("Attachment")
    attachment.Parent = base
    attachment.CFrame = CFrame.new(0, 0, 0)

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
    particles.LightEmission = 0.6
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 255))
    particles.Rotation = NumberRange.new(0, 360)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = attachment

    -- Светящийся ободок (Highlight) для читаемости границы
    local highlight = Instance.new("SelectionBox")
    highlight.Adornee = base
    highlight.Color3 = Color3.fromRGB(255, 100, 220)
    highlight.LineThickness = 0.05
    highlight.Transparency = 0.5
    highlight.SurfaceTransparency = 1
    highlight.Parent = base

    return base
end

-- Сегменты-сектора для «Tasty Bite»: 8 невидимых частей-клиньев.
-- Мы не делаем настоящие клинья (сложно с физикой) — делаем 8 маленьких
-- параллелепипедов по краю, разделяющих платформу на углы.
-- Для простоты используем тонкие arc-коллайдеры на верхней поверхности.
local function buildSegments(folder: Folder, center: Vector3): { BasePart }
    local segments = {}
    local count = Config.Platform.SegmentCount
    local radius = Config.Platform.Radius
    local height = Config.Platform.Height
    local surfaceY = center.Y + height / 2 + 0.05

    for i = 1, count do
        local angle = (i - 1) / count * math.pi * 2
        local midAngle = angle + math.pi / count
        -- Плоский прямоугольник, ориентированный радиально
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
        seg.CanCollide = false  -- основная платформа несёт коллизии
        seg.Transparency = 1    -- сегменты невидимы в обычном режиме
        seg.Color = Color3.fromRGB(255, 80, 80)
        seg.Material = Enum.Material.Neon
        seg.Parent = folder

        -- Метаданные для EventManager/TastyBite
        local tag = Instance.new("NumberValue")
        tag.Name = "SegmentIndex"
        tag.Value = i
        tag.Parent = seg

        table.insert(segments, seg)
    end

    return segments
end

-- Pulse-дыхание платформы
local function startPulse()
    if state.pulseRunning then return end
    state.pulseRunning = true
    local base = state.base
    if not base then return end

    local originalSize = base.Size
    local pulseSize = originalSize * (1 + Config.Platform.PulseScale)
    local info = TweenInfo.new(
        Config.Platform.PulseDuration,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1,  -- бесконечно
        true, -- reverses
        0
    )

    task.spawn(function()
        while state.pulseRunning and base.Parent do
            local tween = TweenService:Create(base, TweenInfo.new(
                Config.Platform.PulseDuration,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut
            ), { Size = pulseSize })
            tween:Play()
            tween.Completed:Wait()
            PlatformEngine.PulseTick:Fire("expand")
            if not state.pulseRunning or not base.Parent then break end
            tween = TweenService:Create(base, TweenInfo.new(
                Config.Platform.PulseDuration,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.InOut
            ), { Size = originalSize })
            tween:Play()
            tween.Completed:Wait()
            PlatformEngine.PulseTick:Fire("contract")
        end
    end)
end

function PlatformEngine:Start()
    local folder = ensureFolder()
    state.folder = folder

    -- Центр: берём середину мира, но на высоте 8 чтобы упавшие игроки не умирали мгновенно
    local center = Vector3.new(0, 8, 0)
    state.center = center

    state.base = buildBase(folder, center)
    state.segments = buildSegments(folder, center)

    startPulse()

    print(string.format(
        "[JMC][Platform] Платформа построена: radius=%.1f, segments=%d",
        state.radius, #state.segments
    ))
end

function PlatformEngine:GetCenter(): Vector3
    return state.center
end

function PlatformEngine:GetRadius(): number
    return state.radius
end

function PlatformEngine:GetSurfaceY(): number
    return state.center.Y + Config.Platform.Height / 2
end

function PlatformEngine:GetBasePart(): BasePart?
    return state.base
end

function PlatformEngine:GetSegments(): { BasePart }
    return state.segments
end

function PlatformEngine:GetFolder(): Folder?
    return state.folder
end

--- Временно изменить упругость (для TrampolineMode)
function PlatformEngine:SetElasticity(e: number)
    local base = state.base
    if not base then return end
    base.CustomPhysicalProperties = PhysicalProperties.new(
        Config.Platform.Density,
        Config.Platform.Friction,
        e,
        Config.Platform.FrictionWeight,
        Config.Platform.ElasticityWeight
    )
end

function PlatformEngine:ResetElasticity()
    self:SetElasticity(state.originalElasticity)
end

--- Временно изменить трение (напр. для событий)
function PlatformEngine:SetFriction(f: number)
    local base = state.base
    if not base then return end
    base.CustomPhysicalProperties = PhysicalProperties.new(
        Config.Platform.Density,
        f,
        state.originalElasticity,
        Config.Platform.FrictionWeight,
        Config.Platform.ElasticityWeight
    )
end

function PlatformEngine:ResetFriction()
    self:SetFriction(Config.Platform.Friction)
end

--- Временно покрасить платформу (для предупреждения о событиях)
function PlatformEngine:FlashColor(color: Color3, duration: number)
    local base = state.base
    if not base then return end
    local originalColor = base.Color
    local info = TweenInfo.new(0.3, Enum.EasingStyle.Sine)
    local toWarn = TweenService:Create(base, info, { Color = color })
    toWarn:Play()
    task.delay(duration, function()
        if not base.Parent then return end
        local back = TweenService:Create(base, info, { Color = originalColor })
        back:Play()
    end)
end

return PlatformEngine
