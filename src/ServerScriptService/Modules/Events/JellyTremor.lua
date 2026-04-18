--!strict
--[[
    Событие №1: «Желейная дрожь» (Jelly Tremor)
    - Платформа «трясётся» каждые 100мс случайным AngularVelocity-толчком.
    - Параллельно клиент делает CameraShake.
    - Трение временно сбрасывается к ещё более скользкому — игроков заносит.
    - Длительность: Config.Events.JellyTremor.Duration.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "JellyTremor"
E.DisplayName = "ЖЕЛЕЙНАЯ ДРОЖЬ!"
E.Color = Color3.fromRGB(255, 180, 120)
E.Overlay = "tremor"
E.Duration = Config.Events.JellyTremor.Duration

function E.Start(ctx)
    local base = ctx.platform:GetBasePart()
    if not base then return end

    -- Сохраним оригинальное CFrame и покачаем вокруг него
    local originCFrame = base.CFrame
    local force = Config.Events.JellyTremor.AngularForce

    ctx.platform:SetFriction(0.03)  -- скользко
    local endTick = os.clock() + (E.Duration or 10)

    -- Визуальная тряска CFrame + применение импульсов к персонажам
    task.spawn(function()
        while os.clock() < endTick do
            local dx = (ctx.random:NextNumber() - 0.5) * 0.6
            local dz = (ctx.random:NextNumber() - 0.5) * 0.6
            local rotX = (ctx.random:NextNumber() - 0.5) * math.rad(force / 4)
            local rotZ = (ctx.random:NextNumber() - 0.5) * math.rad(force / 4)
            base.CFrame = originCFrame * CFrame.new(dx, 0, dz) * CFrame.Angles(rotX, 0, rotZ)

            -- И всем стоящим дать легкий толчок в случайную сторону
            for _, p in ipairs(ctx.presence:GetPlayersInside()) do
                local char = p.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp and hrp:IsA("BasePart") then
                        local angle = ctx.random:NextNumber() * math.pi * 2
                        local push = Vector3.new(math.cos(angle), 0, math.sin(angle)) * force
                        hrp:ApplyImpulse(push * hrp.AssemblyMass * 0.3)
                    end
                end
            end

            -- Клиент: встряска камеры всем
            Remotes.Event("CameraShake"):FireAllClients(Config.Events.JellyTremor.CameraShakeMag, 0.15)
            Remotes.Event("HapticPulse"):FireAllClients(0.4, 0.1)

            task.wait(Config.Events.JellyTremor.TickInterval)
        end
        base.CFrame = originCFrame
    end)

    -- Клиент: ускорить музыку на время события
    Remotes.Event("MusicCue"):FireAllClients("intense", E.Duration)
end

function E.Stop(ctx)
    ctx.platform:ResetFriction()
end

return E
