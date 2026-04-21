--!strict
--[[
    LeaderboardService.lua
    - OrderedDataStore "LongestSlime" по bestSessionTime.
    - Физический лидерборд в мире: 10 SurfaceGui-лейблов на столбе
      недалеко от платформы. Обновляется каждые REFRESH_INTERVAL сек.
    - Также выставляет AuraService:SetRecordHolder(topPlayer).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Signal = require(Shared:WaitForChild("Signal"))

local LeaderboardService = {}
LeaderboardService.TopChanged = Signal.new() -- (top10: {{userId, name, value}})

local ORDERED_NAME = Config.Data.OrderedStoreName or "JMC_LongestSlime_v1"
local REFRESH_INTERVAL = 1
local TOP_N = 10

local orderedStore: OrderedDataStore? = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(ORDERED_NAME)
	end)
	if ok then
		orderedStore = result
	else
		warn(
			"[JMC][Leaderboard] OrderedDataStore недоступен, использую локальный top в памяти: "
				.. tostring(result)
		)
	end
end

local _data = nil
local _presence = nil
local _aura = nil
local _platform = nil

local boardPart: BasePart? = nil
local boardSurfaceGui: SurfaceGui? = nil
local boardList: Frame? = nil

local currentTopHolder: Player? = nil

-- =====================================================================
-- World: строим физический лидерборд
-- =====================================================================
local function buildBoard()
	if not _platform then
		return
	end
	local center = _platform:GetCenter()
	local radius = Config.Platform.Radius

	if boardPart and boardPart.Parent then
		boardPart:Destroy()
	end

	local stand = Instance.new("Part")
	stand.Name = "JMC_Leaderboard"
	stand.Size = Vector3.new(16, 18, 0.5)
	stand.Anchored = true
	stand.CanCollide = false
	stand.Material = Enum.Material.Glass
	stand.Color = Color3.fromRGB(60, 30, 80)
	stand.Transparency = 0.2
	stand.Reflectance = 0.3

	-- Держим борд внутри чистой зоны вокруг платформы, чтобы его не перекрывали деревья.
	-- Ставим на стороне, противоположной воздушной пушке (+Z), и немного выше.
	local boardPos = Vector3.new(center.X, center.Y + 16, center.Z - (radius + 6))
	local lookTarget = Vector3.new(center.X, boardPos.Y, center.Z)
	stand.CFrame = CFrame.lookAt(boardPos, lookTarget)
	stand.Parent = Workspace

	local gui = Instance.new("SurfaceGui")
	gui.Name = "JMC_BoardSurfaceGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(720, 880)
	gui.AlwaysOnTop = false
	gui.Parent = stand

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 86)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Text = "🏆 САМЫЙ ТЕРПЕЛИВЫЙ СЛАЙМ"
	title.Parent = gui

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -24, 1, -98)
	list.Position = UDim2.new(0, 12, 0, 94)
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	boardPart = stand
	boardSurfaceGui = gui
	boardList = list
end

local function renderTop(entries: { any })
	if not boardList then
		return
	end
	for _, child in ipairs(boardList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, entry in ipairs(entries) do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 0.4
		row.BackgroundColor3 = (i == 1) and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(40, 20, 60)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 54)
		row.Font = Enum.Font.FredokaOne
		row.TextScaled = true
		row.TextColor3 = (i == 1) and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		row.Text = string.format(
			"#%d  %s  —  %s",
			i,
			entry.name or "?",
			Util.formatTime and Util.formatTime(entry.value or 0) or tostring(entry.value)
		)
		row.Parent = boardList
	end
end

local function buildLocalEntries(): { any }
	local entries = {}
	if not _data then
		return entries
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local data = _data:Get(player)
		local value = data and data.bestSessionTime or 0
		if value > 0 then
			table.insert(entries, {
				userId = player.UserId,
				name = player.Name,
				value = value,
			})
		end
	end
	table.sort(entries, function(a, b)
		return (a.value or 0) > (b.value or 0)
	end)
	while #entries > TOP_N do
		table.remove(entries)
	end
	return entries
end

-- =====================================================================
-- Refresh loop
-- =====================================================================
local function refreshTop()
	if not orderedStore then
		local entries = buildLocalEntries()
		renderTop(entries)
		LeaderboardService.TopChanged:Fire(entries)
		local topEntry = entries[1]
		local newHolder: Player? = nil
		if topEntry then
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == topEntry.userId then
					newHolder = p
					break
				end
			end
		end
		if newHolder ~= currentTopHolder then
			currentTopHolder = newHolder
			if _aura and _aura.SetRecordHolder then
				_aura:SetRecordHolder(newHolder)
			end
		end
		return
	end

	local pages
	local ok, err = pcall(function()
		pages = orderedStore:GetSortedAsync(false, TOP_N)
	end)
	if not ok or not pages then
		warn("[JMC][Leaderboard] GetSortedAsync failed: " .. tostring(err))
		return
	end

	local page = pages:GetCurrentPage()
	local entries = {}
	for _, item in ipairs(page) do
		local userId = tonumber(item.key:match("(%d+)")) or 0
		local name = "Unknown"
		pcall(function()
			name = Players:GetNameFromUserIdAsync(userId)
		end)
		table.insert(entries, { userId = userId, name = name, value = item.value })
	end

	renderTop(entries)
	LeaderboardService.TopChanged:Fire(entries)

	-- Обновляем держателя рекорда для AuraService
	local topEntry = entries[1]
	local newHolder: Player? = nil
	if topEntry then
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == topEntry.userId then
				newHolder = p
				break
			end
		end
	end
	if newHolder ~= currentTopHolder then
		currentTopHolder = newHolder
		if _aura and _aura.SetRecordHolder then
			_aura:SetRecordHolder(newHolder)
		end
	end
end

local function writeScore(player: Player, seconds: number)
	if not orderedStore then
		return
	end
	pcall(function()
		orderedStore:SetAsync("user_" .. tostring(player.UserId), seconds)
	end)
end

-- =====================================================================
-- Public API
-- =====================================================================
function LeaderboardService:Init(data, presence, aura, platform)
	_data = data
	_presence = presence
	_aura = aura
	_platform = platform
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

function LeaderboardService:Start()
	if not _data then
		_data = tryRequireSibling("DataService")
	end
	if not _presence then
		_presence = tryRequireSibling("CirclePresence")
	end
	if not _aura then
		_aura = tryRequireSibling("AuraService")
	end
	if not _platform then
		_platform = tryRequireSibling("MonsterBodyService")
	end

	if not _platform then
		warn(
			"[JMC][Leaderboard] MonsterBodyService не найден, пропускаю постройку борда"
		)
	else
		buildBoard()
	end

	-- Регулярно обновляем топ
	task.spawn(function()
		task.wait(1)
		while true do
			pcall(refreshTop)
			task.wait(REFRESH_INTERVAL)
		end
	end)

	-- При выходе игрока записываем его best в OrderedStore
	if _data then
		Players.PlayerRemoving:Connect(function(player)
			local d = _data:Get(player)
			if d and d.bestSessionTime and d.bestSessionTime > 0 then
				writeScore(player, d.bestSessionTime)
			end
		end)
	end

	-- Также обновляем каждый раз, когда Presence обновляет continuousTime
	if _presence and _presence.Tick then
		_presence.Tick:Connect(function()
			if not _data then
				return
			end
			for _, p in ipairs(Players:GetPlayers()) do
				local continuous = _presence:GetContinuousTime(p)
				if continuous > 0 then
					_data:SetBestSession(p, continuous)
				end
			end
		end)
	end

	print("[JMC][Leaderboard] Лидерборд активен, top-" .. TOP_N)
end

function LeaderboardService:GetRecordHolder(): Player?
	return currentTopHolder
end

return LeaderboardService
