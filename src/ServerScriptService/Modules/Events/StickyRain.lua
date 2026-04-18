--!strict
--[[
    Событие №2: «Липкий дождь» (Sticky Rain)
    - Сверху над платформой с случайным интервалом падают розовые сферы.
    - При контакте с игроком на него навешивается ParticleEmitter «слизи»
      и он становится «липким» на Config.Events.StickyRain.StickTime секунд.
    - Все другие живые игроки в радиусе PullRadius притягиваются к нему через
      AlignPosition (сильно, но с ограниченной силой, чтобы не выкидывало
      за край нереалистично быстро).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local E = {}
E.Name = "StickyRain"
E.DisplayName = "ЛИПКИЙ ДОЖДЬ!"
E.Color = Color3.fromRGB(255, 120, 200)
E.Duration = Config.Events.StickyRain.Duration

-- Персонажи с активной «липкостью» и их контроллеры
-- character -> { parts = {}, connections = {}, expire = number }
local stickyActive: { [Model]: any } = {}

local function makeDrop(center: Vector3, y: number, folder: Folder): BasePart
    local drop = Instance.new("Part")
    drop.Shape = Enum.PartType.Ball
    drop.Size = Vector3.new(
        Config.Events.StickyRain.DropRadius * 2,
        Config.Events.StickyRain.DropRadius * 2,
        Config.Events.StickyRain.DropRadius * 2
    )
    drop.Material = Enum.Material.Neon
    drop.Color = Color3.fromRGB(255, 90, 200)
    drop.CanCollide = false
    drop.Transparency = 0.15

    local angle = Util.randf(0, math.pi * 2)
    local r = Util.randf(0, Config.Platform.Radius * 0.85)
    drop.Position = Vector3.new(center.X + math.cos(angle) * r, y, center.Z + math.sin(angle) * r)
    drop.AssemblyLinearVelocity = Vector3.new(0, -25, 0)
    drop.Parent = folder
    return drop
end

local function makeStickyEmitter(part: BasePart): ParticleEmitter
    local attach = Instance.new("Attachment")
    attach.Name = "StickyAttach"
    attach.Parent = part

    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    pe.Rate = 40
    pe.Lifetime = NumberRange.new(1, 2)
    pe.Speed = NumberRange.new(1, 3)
    pe.Color = ColorSequence.new(Color3.fromRGB(255, 80, 200))
    pe.Size = NumberSequence.new(0.5, 1.2)
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.LightEmission = 0.8
    pe.Rotation = NumberRange.new(0, 360)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Parent = attach
    return pe
end

local function attachStickyPuller(targetChar: Model, ctx): any
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not targetHRP then return nil end

    local emitter = makeStickyEmitter(targetHRP)
    local expire = os.clock() + Config.Events.StickyRain.StickTime

    local victims: { Attachment } = {}
    local loopConn
    loopConn = game:GetService("RunService").Heartbeat:Connect(function()
        if os.clock() >= expire or not targetHRP.Parent then
            loopConn:Disconnect()
            if emitter.Parent then
                emitter.Enabled = false
                Debris:AddItem(emitter, 2)
            end
            -- Убираем AlignPosition-хелперы у всех, кого тянули
            for _, ap in ipairs(victims) do
                if ap.Parent then ap:Destroy() end
            end
            stickyActive[targetChar] = nil
            return
        end

        for _, p in ipairs(ctx.presence:GetPlayersInside()) do
            local char = p.Character
            if char and char ~= targetChar then
                local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
                if hrp and (hrp.Position - targetHRP.Position).Magnitude
                    < Config.Events.StickyRain.PullRadius then
                    -- Прямое применение силы в сторону «липкого»
                    local dir = (targetHRP.Position - hrp.Position)
                    if dir.Magnitude > 0.1 then
                        local force = dir.Unit * 60
                        hrp:ApplyImpulse(force * hrp.AssemblyMass * 0.15)
                    end
                end
            end
        end
    end)

    stickyActive[targetChar] = { emitter = emitter, conn = loopConn, expire = expire }
end

function E.Start(ctx)
    local center = ctx.platform:GetCenter()
    local surfaceY = ctx.platform:GetSurfaceY()
    local spawnY = surfaceY + 80

    local folder = Instance.new("Folder")
    folder.Name = "JMC_StickyDrops"
    folder.Parent = Workspace
    Debris:AddItem(folder, (E.Duration or 20) + 6)

    local endTick = os.clock() + (E.Duration or 20)

    task.spawn(function()
        local spawned = 0
        while os.clock() < endTick and spawned < Config.Events.StickyRain.DropCount * 3 do
            local drop = makeDrop(center, spawnY, folder)
            spawned = spawned + 1

            -- Авто-уборка через 10 сек
            Debris:AddItem(drop, 10)

            -- При касании игрока — сделать его липким
            local consumed = false
            drop.Touched:Connect(function(other)
                if consumed then return end
                local char = other:FindFirstAncestorOfClass("Model")
                if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health <= 0 then return end
                if stickyActive[char] then return end
                consumed = true
                drop:Destroy()
                attachStickyPuller(char, ctx)
            end)

            task.wait(Util.randf(0.3, 0.8))
        end
    end)
end

function E.Stop(ctx)
    -- Чистим остатки
    for char, data in pairs(stickyActive) do
        if data.conn then data.conn:Disconnect() end
        if data.emitter and data.emitter.Parent then
            data.emitter.Enabled = false
        end
        stickyActive[char] = nil
    end
end

return E
