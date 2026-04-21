--!strict
--[[
    RewardService.lua
    Начисляет валюту игрокам, находящимся в круге, и показывает таймер над головой.

    - При каждом Tick: игрокам в круге +coinsPerSecond.
    - Если у игрока ≥5 друзей в круге → множитель +25%.
    - BillboardGui над Head'ом показывает текущее непрерывное время в круге.

    Зависимости: CirclePresence, DataService (для начисления валюты).
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Signal = require(Shared:WaitForChild("Signal"))

local RewardService = {}

RewardService.CoinsGranted = Signal.new() -- (player, amount, totalCoins)

local Presence: any = nil
local Data: any = nil
local started = false
local dataLoadFailed = false

-- Кэш списков друзей, чтобы не спамить API
local friendsCache: { [Player]: { ids: { [number]: boolean }, t: number } } = {}
local billboards: { [Player]: { gui: BillboardGui, coinsLabel: TextLabel, timerLabel: TextLabel } } = {}

local function getPresence()
	if Presence then
		return Presence
	end
	Presence = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CirclePresence"))
	return Presence
end

local function getData()
	if Data then
		return Data
	end
	if dataLoadFailed then
		return nil
	end
	local mod = ServerScriptService:WaitForChild("Modules"):FindFirstChild("DataService")
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			Data = result
		else
			dataLoadFailed = true
			warn(
				"[JMC][RewardService] DataService недоступен, работаю на локальном кеше: "
					.. tostring(result)
			)
		end
	else
		dataLoadFailed = true
	end
	return Data
end

local function getFriendIds(player: Player): { [number]: boolean }
	local cache = friendsCache[player]
	if cache and (os.clock() - cache.t) < Config.Rewards.FriendCacheTTL then
		return cache.ids
	end

	local ids = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	if ok and pages then
		local success = true
		while success do
			for _, friend in ipairs(pages:GetCurrentPage()) do
				ids[friend.Id] = true
			end
			if pages.IsFinished then
				break
			end
			success = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
		end
	end
	friendsCache[player] = { ids = ids, t = os.clock() }
	return ids
end

local function countFriendsInside(player: Player): number
	local friendIds = getFriendIds(player)
	local n = 0
	for _, other in ipairs(getPresence():GetPlayersInside()) do
		if other ~= player and friendIds[other.UserId] then
			n = n + 1
		end
	end
	return n
end

local function buildBillboard(player: Player)
	local char = player.Character or player.CharacterAdded:Wait()
	local head = char:WaitForChild("Head", 5)
	if not head then
		return
	end

	if billboards[player] then
		billboards[player].gui:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "JMC_Timer"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(180, 60)
	gui.StudsOffset = Vector3.new(0, Config.Rewards.BillboardHeight, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = head

	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = Color3.fromRGB(30, 10, 50)
	bg.BackgroundTransparency = 0.3
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 120, 220)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = bg

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, 0, 0.55, 0)
	timerLabel.Position = UDim2.fromScale(0, 0)
	timerLabel.Font = Enum.Font.LuckiestGuy
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLabel.TextStrokeColor3 = Color3.fromRGB(80, 0, 120)
	timerLabel.TextStrokeTransparency = 0.1
	timerLabel.TextScaled = true
	timerLabel.Text = "00:00"
	timerLabel.Parent = bg

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Coins"
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Size = UDim2.new(1, 0, 0.45, 0)
	coinsLabel.Position = UDim2.fromScale(0, 0.55)
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
	coinsLabel.TextStrokeTransparency = 0.3
	coinsLabel.TextScaled = true
	coinsLabel.Text = "💰 0"
	coinsLabel.Parent = bg

	billboards[player] = { gui = gui, coinsLabel = coinsLabel, timerLabel = timerLabel }
end

local function updateBillboard(player: Player, continuous: number, coins: number)
	local b = billboards[player]
	if not b or not b.gui.Parent then
		buildBillboard(player)
		b = billboards[player]
		if not b then
			return
		end
	end
	b.timerLabel.Text = Util.formatTime(continuous)
	b.coinsLabel.Text = string.format("💰 %d", coins)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		buildBillboard(player)
	end)
	if player.Character then
		buildBillboard(player)
	end
end

local function onPlayerRemoving(player: Player)
	if billboards[player] then
		billboards[player].gui:Destroy()
		billboards[player] = nil
	end
	friendsCache[player] = nil
end

local function onTick(dt: number)
	local presence = getPresence()
	local data = getData()

	for _, player in ipairs(presence:GetPlayersInside()) do
		local base = Config.Rewards.CoinsPerSecond * dt
		local friendCount = countFriendsInside(player)
		local mult = (friendCount >= Config.Rewards.FriendThreshold) and Config.Rewards.FriendMultiplier or 1
		local amount = base * mult

		local total = 0
		if data and data.IncrementCoins then
			total = data:IncrementCoins(player, amount)
		else
			-- Если DataService ещё не готов — считаем локально
			total = (RewardService._localCoins and RewardService._localCoins[player] or 0) + amount
			RewardService._localCoins = RewardService._localCoins or {}
			RewardService._localCoins[player] = total
		end

		RewardService.CoinsGranted:Fire(player, amount, total)
		updateBillboard(player, presence:GetContinuousTime(player), math.floor(total))
	end

	-- Для игроков вне круга — просто обновляем кадр с 0 таймером (чтобы показать последнее значение?)
	-- Лучше оставить последние значения, чтобы было видно «сколько ты простоял в прошлый раз».
end

function RewardService:Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	getPresence().Tick:Connect(onTick)
	getPresence().PlayerExited:Connect(function(player: Player, _continuous: number)
		updateBillboard(player, 0, math.floor(RewardService:GetCoins(player)))
	end)

	print("[JMC][RewardService] Начисление валюты активно")
end

function RewardService:GetCoins(player: Player): number
	local data = getData()
	if data and data.GetCoins then
		return data:GetCoins(player)
	end
	local lc = RewardService._localCoins
	return (lc and lc[player]) or 0
end

function RewardService:IncrementCoins(player: Player, amount: number): number
	local data = getData()
	if data and data.IncrementCoins then
		local total = data:IncrementCoins(player, amount)
		if total ~= nil then
			RewardService._localCoins[player] = total
			return total
		end
	end

	local current = RewardService:GetCoins(player)
	local total = math.max(0, current + amount)
	RewardService._localCoins[player] = total
	return total
end

function RewardService:SpendCoins(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local data = getData()
	if data and data.SpendCoins then
		local ok = data:SpendCoins(player, amount)
		if ok then
			RewardService._localCoins[player] = data:GetCoins(player)
		end
		return ok
	end

	local balance = self:GetCoins(player)
	if balance < amount then
		return false
	end
	RewardService._localCoins[player] = balance - amount
	return true
end

function RewardService:SetVIP(player: Player, value: boolean)
	local data = getData()
	if data and data.SetVIP then
		data:SetVIP(player, value)
	end
end

RewardService._localCoins = {}

return RewardService
