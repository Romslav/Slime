--!strict
--[[
    CameraShake.lua (клиент)
    Perlin-noise тряска камеры по сигналу с сервера.
    Remotes.Event("CameraShake"):FireClient(player, magnitude, duration)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CameraShake = {}

-- Слои тряски: все складываются
-- { magnitude, endTick, startTick, seed }
local shakes: { any } = {}

local function currentOffset(): (CFrame)
    if #shakes == 0 then return CFrame.new() end
    local now = os.clock()
    local x, y, z = 0, 0, 0
    local rotX, rotY, rotZ = 0, 0, 0

    for i = #shakes, 1, -1 do
        local s = shakes[i]
        if now >= s.endTick then
            table.remove(shakes, i)
        else
            local elapsed = now - s.startTick
            local total = s.endTick - s.startTick
            local fade = 1 - (elapsed / total)
            local mag = s.magnitude * fade * 0.1
            local t = elapsed * 10
            -- math.noise — Perlin в Roblox
            x = x + (math.noise(s.seed, t) * mag)
            y = y + (math.noise(s.seed + 11, t) * mag)
            z = z + (math.noise(s.seed + 23, t) * mag * 0.6)
            rotX = rotX + math.noise(s.seed + 31, t) * mag * 0.015
            rotY = rotY + math.noise(s.seed + 43, t) * mag * 0.015
            rotZ = rotZ + math.noise(s.seed + 59, t) * mag * 0.03
        end
    end
    return CFrame.new(x, y, z) * CFrame.Angles(rotX, rotY, rotZ)
end

function CameraShake:Shake(magnitude: number, duration: number)
    table.insert(shakes, {
        magnitude = magnitude,
        startTick = os.clock(),
        endTick = os.clock() + duration,
        seed = math.random() * 1000,
    })
end

function CameraShake:Start()
    Remotes.Event("CameraShake").OnClientEvent:Connect(function(magnitude, duration)
        self:Shake(magnitude or 5, duration or 0.3)
    end)

    RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        if #shakes == 0 then return end
        cam.CFrame = cam.CFrame * currentOffset()
    end)

    print("[JMC][Client] CameraShake готов")
end

return CameraShake
