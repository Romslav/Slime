--!strict
--[[
    CirclePresence.lua
    Следит за тем, кто находится внутри круга платформы.

    - Раз в Config.Rewards.TickInterval проходится по живым игрокам.
    - Для каждого считает sessionTime (суммарно в круге за текущий заход)
      и continuousTime (подряд без выхода; сброс при выходе).
    - Fires сигналы: PlayerEntered / PlayerExited / Tick.
    - Отдаёт публичные геттеры и таблицы времени для других систем.

    Зависимости: PlatformEngine (для центра/радиуса).
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))

local CirclePresence = {}

CirclePresence.PlayerEntered = Signal.new()  -- (player)
CirclePresence.PlayerExited = Signal.new()   -- (player, continuousTime)
CirclePresence.Tick = Signal.new()           -- (dt) — раз в TickInterval

-- Внутреннее состояние
local sessionTime: { [Player]: number } = {}     -- накоплено за текущий заход в сервер
local continuousTime: { [Player]: number } = {}  -- непрерывно в круге
local inside: { [Player]: boolean } = {}
local started = false

local Platform: any = nil

local function getPlatform(): any
    if Platform then return Platform end
    local mod = ServerScriptService:WaitForChild("Modules"):WaitForChild("PlatformEngine")
    Platform = require(mod)
    return Platform
end

local function isInsideCircle(player: Player): boolean
    local hrp = Util.getHRP(player)
    if not hrp then return false end

    local platform = getPlatform()
    local center = platform:GetCenter()
    local radius = platform:GetRadius()
    local surfaceY = platform:GetSurfaceY()

    -- В круге, если горизонтальная дистанция < radius И высота около поверхности
    local horizontal = Vector2.new(hrp.Position.X - center.X, hrp.Position.Z - center.Z)
    if horizontal.Magnitude >= radius then return false end

    -- Если упал под платформу — не засчитываем
    if hrp.Position.Y < surfaceY - 5 then return false end
    -- И если улетел слишком высоко
    if hrp.Position.Y > surfaceY + 40 then return false end

    return true
end

local function cleanupPlayer(player: Player)
    if inside[player] then
        local ct = continuousTime[player] or 0
        CirclePresence.PlayerExited:Fire(player, ct)
    end
    sessionTime[player] = nil
    continuousTime[player] = nil
    inside[player] = nil
end

local function tick(dt: number)
    for _, player in ipairs(Players:GetPlayers()) do
        local humanoid = Util.getHumanoid(player)
        if not humanoid or humanoid.Health <= 0 then
            if inside[player] then
                local ct = continuousTime[player] or 0
                CirclePresence.PlayerExited:Fire(player, ct)
                inside[player] = false
                continuousTime[player] = 0
            end
            continue
        end

        local nowInside = isInsideCircle(player)
        local wasInside = inside[player] == true

        if nowInside then
            sessionTime[player] = (sessionTime[player] or 0) + dt
            continuousTime[player] = (continuousTime[player] or 0) + dt

            if not wasInside then
                inside[player] = true
                CirclePresence.PlayerEntered:Fire(player)
            end
        else
            if wasInside then
                local ct = continuousTime[player] or 0
                CirclePresence.PlayerExited:Fire(player, ct)
                continuousTime[player] = 0
                inside[player] = false
            end
        end
    end

    CirclePresence.Tick:Fire(dt)
end

function CirclePresence:Start()
    if started then return end
    started = true

    Players.PlayerRemoving:Connect(cleanupPlayer)

    task.spawn(function()
        local interval = Config.Rewards.TickInterval
        while task.wait(interval) do
            local ok, err = pcall(tick, interval)
            if not ok then warn("[JMC][CirclePresence] tick error:", err) end
        end
    end)

    print("[JMC][CirclePresence] Мониторинг запущен")
end

--- Сколько игрок провёл в круге за текущий заход на сервер (суммарно).
function CirclePresence:GetSessionTime(player: Player): number
    return sessionTime[player] or 0
end

--- Сколько игрок провёл в круге непрерывно (сбрасывается при выходе).
function CirclePresence:GetContinuousTime(player: Player): number
    return continuousTime[player] or 0
end

--- Находится ли игрок прямо сейчас в круге.
function CirclePresence:IsInside(player: Player): boolean
    return inside[player] == true
end

--- Список игроков, находящихся в круге.
function CirclePresence:GetPlayersInside(): { Player }
    local list = {}
    for player, isIn in pairs(inside) do
        if isIn and player.Parent == Players then
            table.insert(list, player)
        end
    end
    return list
end

--- Кол-во игроков в круге
function CirclePresence:GetCountInside(): number
    local n = 0
    for _, isIn in pairs(inside) do
        if isIn then n = n + 1 end
    end
    return n
end

return CirclePresence
