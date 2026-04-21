--!strict
--[[
    EventManager.lua
    Плагин-система событий. Каждое событие — ModuleScript в ./Events/
    с контрактом:
        {
            Name        : string,
            DisplayName : string,
            Color       : Color3?,
            Overlay     : string?,   -- идентификатор для клиентского оверлея
            Duration    : number?,   -- если не указано, событие само вернёт из start()
            Start       : (ctx) -> (),
            Stop        : (ctx) -> ()?,
        }
    ctx = { platform, presence, reward, ragdoll, config, random }

    Менеджер:
        - Автозагружает все файлы из Events/ при Start().
        - Раз в IntervalMin..IntervalMax секунд выбирает случайное событие
          (anti-repeat window из Config).
        - Шлёт клиенту RemoteEvent'ы: EventStarted, EventBanner, EventEnded.
        - Поддерживает ручной запуск через :Run(name) и голосование
          (:SetNext(name)) и принудительную отладку через Config.Debug.
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local EventManager = {}

EventManager.EventStarted = Signal.new() -- (name)
EventManager.EventEnded = Signal.new() -- (name)

local started = false
local events: { [string]: any } = {}
local eventOrder: { string } = {}
local recentNames: { string } = {}
local queuedNext: string? = nil
local currentEvent: string? = nil
local Modules: Folder

local ModulesMap: {
	platform: any?,
	presence: any?,
	reward: any?,
	ragdoll: any?,
	random: Random,
} = {
	platform = nil,
	presence = nil,
	reward = nil,
	ragdoll = nil,
	random = Random.new(),
}

local function requireModule(name: string): any?
	local mod = Modules:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[JMC][Events] require(" .. name .. ") failed:", result)
		return nil
	end
	return result
end

local function getContext(): any
	if not ModulesMap.platform then
		ModulesMap.platform = requireModule("MonsterBodyService")
	end
	if not ModulesMap.presence then
		ModulesMap.presence = requireModule("CirclePresence")
	end
	if not ModulesMap.reward then
		ModulesMap.reward = requireModule("RewardService")
	end
	if not ModulesMap.ragdoll then
		ModulesMap.ragdoll = requireModule("RagdollService")
	end

	return {
		platform = ModulesMap.platform,
		presence = ModulesMap.presence,
		reward = ModulesMap.reward,
		ragdoll = ModulesMap.ragdoll,
		config = Config,
		random = ModulesMap.random,
	}
end

local function loadEvents()
	local eventsFolder = Modules:FindFirstChild("Events")
	if not eventsFolder then
		warn("[JMC][Events] Папка Events не найдена")
		return
	end

	for _, mod in ipairs(eventsFolder:GetChildren()) do
		if mod:IsA("ModuleScript") then
			local ok, definition = pcall(require, mod)
			if ok and type(definition) == "table" and definition.Name then
				if events[definition.Name] then
					warn("[JMC][Events] Дублирующееся имя события:", definition.Name)
				else
					events[definition.Name] = definition
					table.insert(eventOrder, definition.Name)
				end
			else
				warn("[JMC][Events] Ошибка загрузки события:", mod.Name, tostring(definition))
			end
		end
	end

	if Config.Debug.LogEvents then
		print(
			string.format(
				"[JMC][Events] Загружено событий: %d (%s)",
				#eventOrder,
				table.concat(eventOrder, ", ")
			)
		)
	end
end

local function isRecent(name: string): boolean
	for _, n in ipairs(recentNames) do
		if n == name then
			return true
		end
	end
	return false
end

local function pushRecent(name: string)
	table.insert(recentNames, name)
	while #recentNames > Config.Events.AntiRepeatWindow do
		table.remove(recentNames, 1)
	end
end

local function pickNext(): string?
	if queuedNext and events[queuedNext] then
		local name = queuedNext
		queuedNext = nil
		return name
	end
	if Config.Debug.ForceEventName and events[Config.Debug.ForceEventName] then
		return Config.Debug.ForceEventName
	end
	if #eventOrder == 0 then
		return nil
	end

	-- Сначала пробуем выбрать из «свежих» (не в recent)
	local candidates: { string } = {}
	for _, n in ipairs(eventOrder) do
		if not isRecent(n) then
			table.insert(candidates, n)
		end
	end
	if #candidates == 0 then
		candidates = table.clone(eventOrder)
	end
	return candidates[ModulesMap.random:NextInteger(1, #candidates)]
end

local function runEvent(name: string)
	local def = events[name]
	if not def then
		warn("[JMC][Events] Неизвестное событие:", name)
		return
	end

	currentEvent = name
	pushRecent(name)

	local ctx = getContext()
	local duration = def.Duration or 10

	-- Трансляция клиентам (баннер + FX)
	local payload = {
		name = def.Name,
		displayName = def.DisplayName or def.Name,
		color = def.Color,
		overlay = def.Overlay,
		duration = duration,
	}
	Remotes.Event("EventStarted"):FireAllClients(payload)
	Remotes.Event("EventBanner"):FireAllClients(payload.displayName, payload.color)

	if Config.Debug.LogEvents then
		print(string.format("[JMC][Events] ▶ START %s (%.1f сек)", name, duration))
	end
	EventManager.EventStarted:Fire(name)

	-- Вызов Start с защитой
	local startOk, startErr = pcall(function()
		return def.Start(ctx)
	end)
	if not startOk then
		warn("[JMC][Events] " .. name .. ":Start() упал: " .. tostring(startErr))
	end

	if def.Duration then
		task.wait(def.Duration)
	end

	if type(def.Stop) == "function" then
		local stopOk, stopErr = pcall(def.Stop, ctx)
		if not stopOk then
			warn("[JMC][Events] " .. name .. ":Stop():", stopErr)
		end
	end

	Remotes.Event("EventEnded"):FireAllClients(name)
	if Config.Debug.LogEvents then
		print(string.format("[JMC][Events] ◀ END %s", name))
	end
	EventManager.EventEnded:Fire(name)
	currentEvent = nil
end

local function mainLoop()
	while true do
		local wait = Util.randf(Config.Events.IntervalMin, Config.Events.IntervalMax)
		if Config.Debug.Enabled then
			wait = math.min(wait, 15)
		end
		task.wait(wait)

		local name = pickNext()
		if name then
			runEvent(name)
		end
	end
end

function EventManager:Start()
	if started then
		return
	end
	started = true
	Modules = ServerScriptService:WaitForChild("Modules")

	loadEvents()
	task.spawn(mainLoop)
	print("[JMC][Events] EventManager запущен")
end

--- Запустить событие вручную (для дебага / чата). Не ломает расписание.
function EventManager:Run(name: string)
	if not events[name] then
		warn("[JMC][Events] Run: событие не найдено:", name)
		return
	end
	task.spawn(runEvent, name)
end

--- Записать событие как следующее в очереди (использует VoteService).
function EventManager:SetNext(name: string)
	if not events[name] then
		warn("[JMC][Events] SetNext: событие не найдено:", name)
		return
	end
	queuedNext = name
end

function EventManager:GetEventNames(): { string }
	return table.clone(eventOrder)
end

function EventManager:GetCurrent(): string?
	return currentEvent
end

return EventManager
