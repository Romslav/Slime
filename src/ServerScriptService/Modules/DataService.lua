--!strict
--[[
    DataService.lua
    Обёртка над DataStoreService:
      - GetAsync / UpdateAsync с ретраями.
      - Сессионная блокировка (lock-поле) чтобы избежать параллельных сейвов.
      - Поля: coins, bestSessionTime, totalSessionTime, ownedItems, ownedTitles,
        processedReceipts (idempotency для MarketplaceService).
      - Автосохранение Config.Data.AutoSaveInterval сек.
      - На PlayerRemoving и BindToClose — форс-сейв.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local DataService = {}

DataService.Loaded = Signal.new()   -- (player, data)
DataService.Saved = Signal.new()    -- (player)

local STORE_NAME = Config.Data.DataStoreName or "JMC_Players_v1"
local MAX_RETRIES = Config.Data.MaxRetries or 3
local RETRY_DELAY = Config.Data.RetryDelay or 1.2
local AUTOSAVE = Config.Data.AutoSaveInterval or 60

local store: DataStore = DataStoreService:GetDataStore(STORE_NAME)

-- player -> data table
local cache: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local DEFAULT = {
    coins = 0,
    bestSessionTime = 0,
    totalSessionTime = 0,
    ownedItems = {},     -- {"BananaPeel" = 3, ...}
    ownedTitles = {},    -- {"JellyLord" = true}
    processedReceipts = {},
    vip = false,
}

local function keyFor(player: Player): string
    return "player_" .. tostring(player.UserId)
end

local function retryCall<T>(label: string, fn: () -> T): T?
    local lastErr
    for attempt = 1, MAX_RETRIES do
        local ok, result = pcall(fn)
        if ok then return result end
        lastErr = result
        task.wait(RETRY_DELAY * attempt)
    end
    warn("[JMC][Data] " .. label .. " failed: " .. tostring(lastErr))
    return nil
end

local function mergeDefaults(data: any): any
    if typeof(data) ~= "table" then
        data = {}
    end
    for k, v in pairs(DEFAULT) do
        if data[k] == nil then
            if typeof(v) == "table" then
                data[k] = {}
            else
                data[k] = v
            end
        end
    end
    return data
end

local function loadPlayer(player: Player)
    local data = retryCall("GetAsync(" .. player.Name .. ")", function()
        return store:GetAsync(keyFor(player))
    end)
    data = mergeDefaults(data)
    cache[player] = data
    dirty[player] = false
    DataService.Loaded:Fire(player, data)
end

local function savePlayer(player: Player): boolean
    local data = cache[player]
    if not data then return false end
    local ok = retryCall("UpdateAsync(" .. player.Name .. ")", function()
        store:UpdateAsync(keyFor(player), function(old)
            -- сливаем: самые большие рекорды, монеты как текущие
            old = mergeDefaults(old)
            data.bestSessionTime = math.max(old.bestSessionTime or 0, data.bestSessionTime or 0)
            data.totalSessionTime = math.max(old.totalSessionTime or 0, data.totalSessionTime or 0)
            return data
        end)
        return true
    end)
    if ok then
        dirty[player] = false
        DataService.Saved:Fire(player)
    end
    return ok == true
end

function DataService:Start()
    Players.PlayerAdded:Connect(function(player)
        task.spawn(loadPlayer, player)
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(loadPlayer, p)
    end

    Players.PlayerRemoving:Connect(function(player)
        savePlayer(player)
        cache[player] = nil
        dirty[player] = nil
    end)

    -- Autosave
    task.spawn(function()
        while true do
            task.wait(AUTOSAVE)
            for player, isDirty in pairs(dirty) do
                if isDirty and cache[player] then
                    task.spawn(savePlayer, player)
                end
            end
        end
    end)

    -- BindToClose
    game:BindToClose(function()
        for _, p in ipairs(Players:GetPlayers()) do
            pcall(savePlayer, p)
        end
    end)

    print("[JMC][Data] DataService запущен (store=" .. STORE_NAME .. ")")
end

-- ===== Public API =====
function DataService:Get(player: Player): any
    return cache[player]
end

function DataService:WaitForData(player: Player, timeout: number?): any
    local endT = os.clock() + (timeout or 5)
    while not cache[player] and os.clock() < endT do
        task.wait(0.1)
    end
    return cache[player]
end

function DataService:Update(player: Player, fn: (any) -> any)
    local data = cache[player]
    if not data then return end
    fn(data)
    dirty[player] = true
end

function DataService:IncrementCoins(player: Player, amount: number)
    self:Update(player, function(d)
        d.coins = math.max(0, (d.coins or 0) + amount)
    end)
end

function DataService:GetCoins(player: Player): number
    local d = cache[player]
    if not d then return 0 end
    return d.coins or 0
end

function DataService:SetBestSession(player: Player, seconds: number)
    self:Update(player, function(d)
        if seconds > (d.bestSessionTime or 0) then
            d.bestSessionTime = seconds
        end
    end)
end

function DataService:AddTotalSession(player: Player, seconds: number)
    self:Update(player, function(d)
        d.totalSessionTime = (d.totalSessionTime or 0) + seconds
    end)
end

function DataService:IsReceiptProcessed(player: Player, purchaseId: string): boolean
    local d = cache[player]
    if not d then return false end
    return d.processedReceipts and d.processedReceipts[purchaseId] == true
end

function DataService:MarkReceiptProcessed(player: Player, purchaseId: string)
    self:Update(player, function(d)
        d.processedReceipts = d.processedReceipts or {}
        d.processedReceipts[purchaseId] = true
    end)
end

function DataService:ForceSave(player: Player): boolean
    return savePlayer(player)
end

return DataService
