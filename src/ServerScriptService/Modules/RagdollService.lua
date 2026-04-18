--!strict
--[[
    RagdollService.lua
    Универсальный ragdoll/stun для персонажей.
    - Apply(humanoid, duration): ставит PlatformStand, бросает импульс,
      через duration возвращает обратно.
    - Работает и на R6, и на R15 (через PlatformStand + импульс — проще всего).
    - Возвращает AutoUnstun cancel-токен.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))

local RagdollService = {}

RagdollService.Applied = Signal.new()   -- (humanoid, duration)
RagdollService.Recovered = Signal.new() -- (humanoid)

local active: { [Humanoid]: number } = {} -- humanoid -> expireTick

function RagdollService:Start()
    -- На каждом кадре проверяем expired
    task.spawn(function()
        while task.wait(0.2) do
            local now = os.clock()
            for humanoid, expire in pairs(active) do
                if not humanoid.Parent or humanoid.Health <= 0 then
                    active[humanoid] = nil
                elseif now >= expire then
                    humanoid.PlatformStand = false
                    active[humanoid] = nil
                    RagdollService.Recovered:Fire(humanoid)
                end
            end
        end
    end)
    print("[JMC][Ragdoll] Ragdoll-сервис активен")
end

function RagdollService:Apply(humanoid: Humanoid, duration: number, impulse: Vector3?)
    if not humanoid or humanoid.Health <= 0 then return end
    humanoid.PlatformStand = true

    local char = humanoid.Parent
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") and impulse then
            hrp:ApplyImpulse(impulse * hrp.AssemblyMass)
        end
    end

    local expire = os.clock() + duration
    local current = active[humanoid]
    if not current or current < expire then
        active[humanoid] = expire
    end
    RagdollService.Applied:Fire(humanoid, duration)
end

function RagdollService:IsRagdolled(humanoid: Humanoid): boolean
    return active[humanoid] ~= nil
end

function RagdollService:Release(humanoid: Humanoid)
    if not humanoid then return end
    humanoid.PlatformStand = false
    active[humanoid] = nil
    RagdollService.Recovered:Fire(humanoid)
end

return RagdollService
