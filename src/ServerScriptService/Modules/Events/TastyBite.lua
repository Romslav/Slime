--!strict
--[[
    Событие №3: «Вкусный укус» (Tasty Bite)
    - Выбираем K случайных сегментов платформы, мигаем красным SelectionBox.
    - Через WarnTime секунд у выбранных сегментов становится CanCollide=true
      на самом деле отключаем коллизию у НАСТОЯЩЕЙ платформы в этой зоне.
    - Поскольку наша платформа — единый Cylinder, мы не можем вырезать кусок.
      Решение: на время «укуса» спавним «дырку» — Part с точными границами
      сегмента, с CanCollide=true, но его нет в hitbox'е основной платформы.
      Лучше: добавить BASE-сегменты-клинья КАК реальные физические кусочки
      (PlatformEngine:GetSegments()) — у них включаем Transparency и CanCollide=true.
      А оригинальная платформа получает в этой зоне дырку через FallGuard: мы
      считаем игроков над этим сектором и временно выключаем платформенный
      коллайдер для них через небольшой BodyPosition вниз? Нет, это хрупко.

      Чистое решение: создаём временный клиновидный Part с CanCollide=true
      поверх платформы (он уже там есть — invisible segments). Его видимость
      меняется на жёлтую/красную, а затем мы заменяем коллайдер основной
      платформы на «всё кроме этого клина» через хитрый WedgePart-диск.

      УПРОЩЕНИЕ ДЛЯ PROD: делаем «телепорт вниз». У сегмента выставляется
      CanCollide=true и видимый, становится красным → затем на 0.2 секунды
      у него отключается CanCollide и прикрепляется BodyVelocity вниз у всех,
      кто стоит над ним. После RegrowTime всё возвращается.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local E = {}
E.Name = "TastyBite"
E.DisplayName = "ВКУСНЫЙ УКУС!"
E.Color = Color3.fromRGB(255, 80, 80)
E.Duration = Config.Events.TastyBite.Duration

local function isPlayerAboveSegment(hrpPos: Vector3, segment: BasePart): boolean
    local relative = segment.CFrame:PointToObjectSpace(
        Vector3.new(hrpPos.X, segment.Position.Y, hrpPos.Z)
    )
    return math.abs(relative.X) < segment.Size.X / 2
        and math.abs(relative.Z) < segment.Size.Z / 2
end

local function biteSegment(segment: BasePart, ctx)
    -- Фаза 1: предупреждение — мигает красным
    segment.Transparency = 0.2
    segment.Material = Enum.Material.Neon
    segment.Color = Color3.fromRGB(255, 80, 80)
    local highlight = Instance.new("SelectionBox")
    highlight.Adornee = segment
    highlight.Color3 = Color3.fromRGB(255, 40, 40)
    highlight.LineThickness = 0.2
    highlight.Transparency = 0.2
    highlight.SurfaceTransparency = 0.7
    highlight.SurfaceColor3 = Color3.fromRGB(255, 50, 50)
    highlight.Parent = segment

    -- Моргание
    local blinkEnd = os.clock() + Config.Events.TastyBite.WarnTime
    task.spawn(function()
        while os.clock() < blinkEnd do
            local tw = TweenService:Create(highlight, TweenInfo.new(0.2), { Transparency = 0.8 })
            tw:Play(); tw.Completed:Wait()
            tw = TweenService:Create(highlight, TweenInfo.new(0.2), { Transparency = 0.1 })
            tw:Play(); tw.Completed:Wait()
        end
    end)
    task.wait(Config.Events.TastyBite.WarnTime)

    -- Фаза 2: УКУС — пушим всех, стоящих над этим сегментом, вниз
    local base = ctx.platform:GetBasePart()
    if base then
        for _, p in ipairs(ctx.presence:GetPlayersInside()) do
            local char = p.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
                if hrp and isPlayerAboveSegment(hrp.Position, segment) then
                    hrp:ApplyImpulse(Vector3.new(0, -800, 0) * hrp.AssemblyMass / 10)
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and ctx.ragdoll then
                        ctx.ragdoll:Apply(hum, 1.5)
                    end
                end
            end
        end
    end

    -- Эффект «крошек»
    local explosion = Instance.new("Explosion")
    explosion.BlastRadius = 0
    explosion.BlastPressure = 0
    explosion.DestroyJointRadiusPercent = 0
    explosion.Position = segment.Position
    explosion.Parent = workspace

    local crumbs = Instance.new("Part")
    crumbs.Size = Vector3.new(0.1, 0.1, 0.1)
    crumbs.CFrame = CFrame.new(segment.Position)
    crumbs.Transparency = 1
    crumbs.Anchored = true
    crumbs.CanCollide = false
    crumbs.Parent = workspace

    local attach = Instance.new("Attachment")
    attach.Parent = crumbs

    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(1, 2)
    pe.Speed = NumberRange.new(20, 40)
    pe.Color = ColorSequence.new(Color3.fromRGB(255, 150, 220))
    pe.Size = NumberSequence.new(1, 0.1)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Rotation = NumberRange.new(0, 360)
    pe.Parent = attach
    pe:Emit(50)

    Debris:AddItem(crumbs, 3)

    -- Фаза 3: отрастает
    task.wait(Config.Events.TastyBite.RegrowTime)
    if highlight.Parent then highlight:Destroy() end
    local back = TweenService:Create(segment, TweenInfo.new(0.4), { Transparency = 1 })
    back:Play()
end

function E.Start(ctx)
    local segments = ctx.platform:GetSegments()
    if #segments == 0 then return end

    local pool = table.clone(segments)
    local k = math.min(Config.Events.TastyBite.SegmentsToBite, #pool)

    for i = 1, k do
        local idx = ctx.random:NextInteger(1, #pool)
        local seg = pool[idx]
        table.remove(pool, idx)

        task.spawn(biteSegment, seg, ctx)
        task.wait(Util.randf(0.3, 0.8))
    end
end

function E.Stop(ctx)
    -- на случай если событие прервали — восстановим сегменты
    for _, seg in ipairs(ctx.platform:GetSegments()) do
        seg.Transparency = 1
        for _, child in ipairs(seg:GetChildren()) do
            if child:IsA("SelectionBox") then
                child:Destroy()
            end
        end
    end
end

return E
