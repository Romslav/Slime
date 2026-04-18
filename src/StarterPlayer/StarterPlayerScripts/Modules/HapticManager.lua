--!strict
--[[
    HapticManager.lua (клиент)
    Вибрация геймпада и мобильных устройств по сигналу сервера:
    Remotes.Event("HapticPulse"):FireClient(player, strength, duration)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HapticService = game:GetService("HapticService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local HapticManager = {}

local function pulse(strength: number, duration: number)
    strength = math.clamp(strength, 0, 1)
    duration = math.max(0.05, math.min(duration, 2))

    -- Пробуем все подключённые геймпады
    local userInput = game:GetService("UserInputService")
    for _, gamepad in ipairs(userInput:GetConnectedGamepads()) do
        local enumGamepad = Enum.UserInputType[gamepad.Name] or gamepad
        local ok1 = pcall(function()
            HapticService:SetMotor(enumGamepad, Enum.VibrationMotor.Large, strength)
        end)
        local ok2 = pcall(function()
            HapticService:SetMotor(enumGamepad, Enum.VibrationMotor.Small, strength * 0.7)
        end)
        task.delay(duration, function()
            pcall(function()
                HapticService:SetMotor(enumGamepad, Enum.VibrationMotor.Large, 0)
                HapticService:SetMotor(enumGamepad, Enum.VibrationMotor.Small, 0)
            end)
        end)
    end
end

function HapticManager:Start()
    Remotes.Event("HapticPulse").OnClientEvent:Connect(function(strength, duration)
        pulse(tonumber(strength) or 0.3, tonumber(duration) or 0.2)
    end)
    print("[JMC][Client] HapticManager готов")
end

return HapticManager
