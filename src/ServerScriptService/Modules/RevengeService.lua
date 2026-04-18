--!strict
--[[
    RevengeService.lua
    Отслеживает «кто кого выкинул из круга»:
      - слушаем CirclePresence.PlayerExited;
      - если за Config.Social.RevengeDetectionWindow сек до выхода на игрока
        был применён чей-то пранк (ToolFactory.PrankFired) или эффект события
        (RagdollService.Applied от другого игрока) — записываем обидчика;
      - клиенту отправляем RevengeOffer(offenderUserId, offenderName, discount, expireSec);
      - ShopService может спросить GetRevengeDiscount(victim, offender, item) → скидка.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local RevengeService = {}
RevengeService.RevengeOffered = Signal.new()  -- (victim, offender)

local _presence = nil
local _toolFactory = nil

-- victim -> { offender, firedAt, expire }
local lastHit: { [Player]: any } = {}

-- Активное предложение мести: victim -> { offender, expire }
local activeOffers: { [Player]: any } = {}

local DETECT_WIN = 2
local REVENGE_WIN = 30

local function noteHit(attacker: Player, victim: Player)
    if not attacker or not victim or attacker == victim then return end
    lastHit[victim] = {
        offender = attacker,
        firedAt = os.clock(),
    }
end

function RevengeService:Init(presence, toolFactory)
    _presence = presence
    _toolFactory = toolFactory
    DETECT_WIN = Config.Social.RevengeDetectionWindow or 2
    REVENGE_WIN = Config.Social.RevengeWindow or 30
end

local function tryRequireSibling(name: string): any?
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, result = pcall(require, mod)
    if ok then return result end
    return nil
end

function RevengeService:Start()
    if not _presence then _presence = tryRequireSibling("CirclePresence") end
    if not _toolFactory then _toolFactory = tryRequireSibling("ToolFactory") end

    if _toolFactory and _toolFactory.PrankFired then
        _toolFactory.PrankFired:Connect(function(attacker, victim, itemId)
            noteHit(attacker, victim)
        end)
    end

    if _presence and _presence.PlayerExited then
        _presence.PlayerExited:Connect(function(victim)
            local hit = lastHit[victim]
            if not hit then return end
            if os.clock() - hit.firedAt > DETECT_WIN then
                lastHit[victim] = nil
                return
            end
            local offender = hit.offender
            if not offender or not offender.Parent then return end

            activeOffers[victim] = {
                offender = offender,
                expire = os.clock() + REVENGE_WIN,
            }

            Remotes.Event("RevengeOffer"):FireClient(victim, {
                offenderUserId = offender.UserId,
                offenderName = offender.DisplayName or offender.Name,
                discount = Config.Social.RevengeDiscount or 0.5,
                durationSec = REVENGE_WIN,
            })
            RevengeService.RevengeOffered:Fire(victim, offender)
            lastHit[victim] = nil
        end)
    end

    -- Чистим просроченные
    task.spawn(function()
        while true do
            task.wait(2)
            local now = os.clock()
            for victim, data in pairs(activeOffers) do
                if now >= data.expire then
                    activeOffers[victim] = nil
                end
            end
            for victim, data in pairs(lastHit) do
                if now - data.firedAt > DETECT_WIN * 2 then
                    lastHit[victim] = nil
                end
            end
        end
    end)

    print("[JMC][Revenge] Сервис мести активен")
end

-- Публичный API: вернуть актуальную скидку для покупки victim → offender
function RevengeService:GetDiscount(victim: Player, offenderUserId: number): number
    local offer = activeOffers[victim]
    if not offer then return 0 end
    if os.clock() >= offer.expire then
        activeOffers[victim] = nil
        return 0
    end
    if offer.offender and offer.offender.UserId == offenderUserId then
        return Config.Social.RevengeDiscount or 0.5
    end
    return 0
end

function RevengeService:HasActiveOffer(victim: Player): boolean
    local offer = activeOffers[victim]
    if not offer then return false end
    if os.clock() >= offer.expire then
        activeOffers[victim] = nil
        return false
    end
    return true
end

function RevengeService:ConsumeOffer(victim: Player)
    activeOffers[victim] = nil
end

-- Ручная регистрация (для событий типа GiantSpoon где нет прямого pranker-а
-- можно помечать «виновником» само событие — пока не используется)
function RevengeService:NoteHit(attacker: Player, victim: Player)
    noteHit(attacker, victim)
end

return RevengeService
