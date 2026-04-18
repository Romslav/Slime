--!strict
--[[
    ClientMain.client.lua
    Точка входа клиента. Инициализирует все клиентские модули по порядку.
    Все модули лежат в StarterPlayerScripts/Modules/.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local modulesFolder = script.Parent:WaitForChild("Modules")

local function tryStart(name: string)
    local mod = modulesFolder:FindFirstChild(name)
    if not mod or not mod:IsA("ModuleScript") then
        warn("[JMC][Client] Отсутствует модуль: " .. name)
        return nil
    end
    local ok, result = pcall(require, mod)
    if not ok then
        warn("[JMC][Client] Ошибка require(" .. name .. "): " .. tostring(result))
        return nil
    end
    if typeof(result) == "table" and type(result.Start) == "function" then
        local ok2, err = pcall(result.Start, result)
        if not ok2 then
            warn("[JMC][Client] Ошибка Start(" .. name .. "): " .. tostring(err))
        end
    end
    return result
end

print("[JMC][Client] Старт клиента для", player.Name)

-- Порядок важен: Camera/Overlay/HUD сначала, затем вспомогательные
tryStart("CameraShake")
tryStart("OverlayEffects")
tryStart("HUD")
tryStart("EventBannerUI")
tryStart("MusicManager")
tryStart("HapticManager")
tryStart("ShopUI")
tryStart("VoteUI")
tryStart("ButtonMash")

print("[JMC][Client] Клиентские модули загружены")
