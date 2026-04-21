--!strict
--[[
    VoteService.lua
    Каждые Config.Social.VoteInterval секунд открывает голосование:
      - 3 случайных события из EventManager (не повторяя активное)
      - Клиент получает VoteOpened(options, duration)
      - Клиент шлёт VoteCast(optionId)
      - По таймеру закрываем, самое популярное → EventManager:SetNext(name)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))
local Signal = require(Shared:WaitForChild("Signal"))

local VoteService = {}
VoteService.VoteOpened = Signal.new()
VoteService.VoteClosed = Signal.new() -- (winner:string)

local _eventManager = nil
local _running = false

-- Текущее голосование
local activeVote: { options: { string }, votes: { [Player]: number }, endTick: number }? = nil

local function pickOptions(): { string }
	if not _eventManager then
		return {}
	end
	local names = _eventManager:GetEventNames()
	local current = _eventManager:GetCurrent()

	local pool = {}
	for _, n in ipairs(names) do
		if n ~= current then
			table.insert(pool, n)
		end
	end

	local count = math.min(Config.Social.VoteOptionCount or 3, #pool)
	local options = {}
	for i = 1, count do
		if #pool == 0 then
			break
		end
		local idx = math.random(1, #pool)
		table.insert(options, pool[idx])
		table.remove(pool, idx)
	end
	return options
end

local function openVote()
	local options = pickOptions()
	if #options == 0 then
		return
	end

	local duration = Config.Social.VoteDuration or 20
	activeVote = {
		options = options,
		votes = {},
		endTick = os.clock() + duration,
	}

	Remotes.Event("VoteOpened"):FireAllClients({
		options = options,
		duration = duration,
	})
	VoteService.VoteOpened:Fire(options, duration)

	task.wait(duration)

	-- Подсчёт
	local tally: { [number]: number } = {}
	for _, optIndex in pairs(activeVote.votes) do
		tally[optIndex] = (tally[optIndex] or 0) + 1
	end

	local bestIdx = 1
	local bestCount = -1
	for i = 1, #options do
		local c = tally[i] or 0
		if c > bestCount then
			bestCount = c
			bestIdx = i
		end
	end
	local winner = options[bestIdx]

	Remotes.Event("VoteClosed"):FireAllClients({
		winner = winner,
		tally = tally,
	})
	VoteService.VoteClosed:Fire(winner)

	if _eventManager and winner then
		_eventManager:SetNext(winner)
	end

	activeVote = nil
end

function VoteService:Init(eventManager)
	_eventManager = eventManager
end

local function tryRequireSibling(name: string): any?
	local mod = script.Parent:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, result = pcall(require, mod)
	if ok then
		return result
	end
	return nil
end

function VoteService:Start()
	if not _eventManager then
		_eventManager = tryRequireSibling("EventManager")
	end
	if not _eventManager then
		warn("[JMC][Vote] EventManager недоступен — голосования не будет")
		return
	end
	_running = true

	Remotes.Event("VoteCast").OnServerEvent:Connect(function(player, optionIndex)
		if not activeVote then
			return
		end
		if typeof(optionIndex) ~= "number" then
			return
		end
		if optionIndex < 1 or optionIndex > #activeVote.options then
			return
		end
		activeVote.votes[player] = optionIndex
	end)

	task.spawn(function()
		while _running do
			task.wait(Config.Social.VoteInterval or 300)
			if _running then
				pcall(openVote)
			end
		end
	end)

	print("[JMC][Vote] Голосование активно")
end

function VoteService:Stop()
	_running = false
end

function VoteService:IsOpen(): boolean
	return activeVote ~= nil
end

return VoteService
