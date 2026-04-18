--!strict
--[[
    Main.server.lua
    Оркестратор серверной стороны. Требует все модули и инициализирует их
    в строгом порядке.

    Порядок зависимостей:
        World       → лес, лайтинг, атмосфера
        Platform    → сама желейная платформа (зависит от World для Anchor)
        Data        → DataStore (независим, но нужен до Reward)
        Presence    → кто в круге (зависит от Platform)
        Reward      → валюта (зависит от Presence + Data)
        Transform   → стадии (зависит от Presence)
        Aura        → зависит от Presence
        Ragdoll     → независим, но нужен до Events
        ToolFactory → независим, нужен до Shop
        Events      → зависит от Platform + Ragdoll
        Shop        → зависит от ToolFactory + Data
        Vote        → зависит от Events
        Friendship  → зависит от Presence + Reward
        Revenge     → зависит от Presence + Shop
        Leaderboard → зависит от Data
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Прогреть Remotes как можно раньше, чтобы клиенты получили папку
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Modules = ServerScriptService:WaitForChild("Modules")

local function tryStart(name: string, order: number): any?
    local module = Modules:FindFirstChild(name)
    if not module then
        warn(string.format("[JMC][Main] Модуль %s не найден — пропускаю (этап %d)", name, order))
        return nil
    end
    local ok, result = pcall(require, module)
    if not ok then
        warn(string.format("[JMC][Main] Ошибка require(%s): %s", name, tostring(result)))
        return nil
    end
    if type(result) == "table" and type(result.Start) == "function" then
        local okStart, err = pcall(result.Start, result)
        if not okStart then
            warn(string.format("[JMC][Main] %s:Start() упал: %s", name, tostring(err)))
            return nil
        end
    end
    print(string.format("[JMC][Main] ✓ %s инициализирован (этап %d)", name, order))
    return result
end

print("[JMC][Main] =============================================")
print("[JMC][Main] Kingdom of the Jelly Monster — запуск сервера")
print("[JMC][Main] =============================================")

-- Порядок критичен — зависимости снизу-вверх
local World      = tryStart("WorldBuilder",          1)
local Platform   = tryStart("PlatformEngine",        2)
local Data       = tryStart("DataService",           3)
local Presence   = tryStart("CirclePresence",        4)
local Reward     = tryStart("RewardService",         5)
local Transform  = tryStart("TransformationService", 6)
local Aura       = tryStart("AuraService",           7)
local Ragdoll    = tryStart("RagdollService",        8)
local Factory    = tryStart("ToolFactory",           9)
local Events     = tryStart("EventManager",          10)
local Shop       = tryStart("ShopService",           11)
local Vote       = tryStart("VoteService",           12)
local Friendship = tryStart("FriendshipMode",        13)
local Revenge    = tryStart("RevengeService",        14)
local Leaders    = tryStart("LeaderboardService",    15)

print("[JMC][Main] Все доступные системы подняты. Приятной игры!")
