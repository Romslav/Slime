--!strict
--[[
    Событие №7: «Центрифуга» (Spin Cycle)
    - Платформа Anchored, поэтому мы имитируем вращение:
      каждый tick применяем к игрокам силу, перпендикулярную радиусу,
      с модулем ∝ расстоянию от центра (как на карусели).
    - Дополнительно — центробежная составляющая наружу.
    - Визуально платформа медленно поворачивает CFrame.
    - Клиенту — CameraShake + vignette.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "SpinCycle"
E.DisplayName = "ЦЕНТРИФУГА!"
E.Color = Color3.fromRGB(180, 140, 255)
E.Overlay = "spin"
E.Duration = Config.Events.SpinCycle.Duration

function E.Start(ctx)
    local base = ctx.platform:GetBasePart()
    if not base then return end

    local center = ctx.platform:GetCenter()
    local angularSpeed = Config.Events.SpinCycle.AngularVel or 2.5 -- рад/сек
    local radialPull = Config.Events.SpinCycle.RadialPull or 9   -- сила/стад
    -- Тангенс/радиус считаются от базовой силы, радиальная — наружу

    Remotes.Event("OverlayFX"):FireAllClients("spin", E.Duration)
    Remotes.Event("MusicCue"):FireAllClients("intense", E.Duration)

    local origCFrame = base.CFrame
    local accumAngle = 0
    local endTick = os.clock() + (E.Duration or 12)

    local conn: RBXScriptConnection? = nil
    conn = RunService.Heartbeat:Connect(function(dt)
        if os.clock() >= endTick then
            if conn then conn:Disconnect() end
            base.CFrame = origCFrame
            return
        end

        -- Визуальное вращение платформы вокруг Y
        accumAngle = accumAngle + angularSpeed * dt
        base.CFrame = origCFrame * CFrame.Angles(0, accumAngle, 0)

        Remotes.Event("CameraShake"):FireAllClients(3, 0.2)

        -- Силы на игроков
        for _, p in ipairs(ctx.presence:GetPlayersInside()) do
            local char = p.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp and hrp:IsA("BasePart") then
                    local rel = Vector3.new(
                        hrp.Position.X - center.X,
                        0,
                        hrp.Position.Z - center.Z
                    )
                    local dist = rel.Magnitude
                    if dist > 0.1 then
                        local radial = rel.Unit
                        -- Тангенс — перпендикулярно к радиусу (вращение против часовой)
                        local tangent = Vector3.new(-radial.Z, 0, radial.X)
                        -- сила растёт от центра к краю ∝ расстоянию (как карусель)
                        local force = tangent * (radialPull * 9) * dist
                                    + radial * radialPull * dist * 0.4
                        hrp:ApplyImpulse(force * hrp.AssemblyMass * dt)
                    end
                end
            end
        end
    end)

    task.wait(E.Duration or 12)
    if conn then conn:Disconnect() end
    base.CFrame = origCFrame
end

function E.Stop(ctx)
    local base = ctx.platform:GetBasePart()
    -- Основная очистка в самом Start; на всякий случай вернём CFrame, если кто-то схватил ссылку
    if base then
        -- ничего дополнительно — origCFrame живёт в замыкании Start
    end
end

return E
