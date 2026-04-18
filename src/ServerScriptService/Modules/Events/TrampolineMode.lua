--!strict
--[[
    Событие №6: «Режим батута» (Trampoline Mode)
    - Workspace.Gravity снижается до Config.Events.TrampolineMode.Gravity (низкая).
    - Платформа получает высокий Elasticity — прыгучая поверхность.
    - Клиент запускает «парящую» музыку.
    - По окончании всё возвращается.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "TrampolineMode"
E.DisplayName = "БАТУТНЫЙ РЕЖИМ!"
E.Color = Color3.fromRGB(255, 200, 255)
E.Overlay = "float"
E.Duration = Config.Events.TrampolineMode.Duration

local originalGravity: number? = nil

function E.Start(ctx)
    -- 1) гравитация
    originalGravity = Workspace.Gravity
    Workspace.Gravity = Config.Events.TrampolineMode.Gravity or 40

    -- 2) упругость платформы
    ctx.platform:SetElasticity(Config.Events.TrampolineMode.Elasticity or 1.0)

    -- 3) клиент — парящая музыка + HUD
    Remotes.Event("MusicCue"):FireAllClients("float", E.Duration)
    Remotes.Event("OverlayFX"):FireAllClients("float", E.Duration)

    -- 4) мягкий «прыжковый» импульс всем, кто в круге — чтобы сразу начали парить
    for _, p in ipairs(ctx.presence:GetPlayersInside()) do
        local char = p.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then
                hrp:ApplyImpulse(Vector3.new(0, 120, 0) * hrp.AssemblyMass)
            end
        end
    end

    task.wait(E.Duration or 15)
end

function E.Stop(ctx)
    if originalGravity then
        Workspace.Gravity = originalGravity
        originalGravity = nil
    end
    ctx.platform:ResetElasticity()
end

return E
