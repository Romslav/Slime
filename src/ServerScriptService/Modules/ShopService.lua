--!strict
--[[
    ShopService.lua
    Магазин Пакостей:
      - Обрабатывает MarketplaceService.ProcessReceipt идемпотентно
        (через DataService: отмечаем обработанные receipt'ы)
      - GamePasses (VIP) проверяем UserOwnsGamePassAsync
      - Также поддерживает покупку за внутреннюю валюту (coins)
      - Remote API:
          GetShopCatalog (RemoteFunction) — возвращает каталог и цены
          RequestShopOpen (RemoteEvent)   — клиент просит открыть магазин
          RequestPurchase (RemoteEvent)   — клиент просит купить за coins
          PurchaseResult (RemoteEvent)    — ответ: succeeded|failed|reason
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local ShopService = {}

ShopService.PurchaseGranted = Signal.new() -- (player, itemId, source:"robux"|"coins")

local _toolFactory = nil
local _reward = nil -- для GetCoins/SpendCoins
local _data = nil -- для идемпотентности receipts

-- productId -> itemId
local productToItem: { [number]: string } = {}

local function buildCatalog()
	return {
		Items = {
			{
				Id = "BananaPeel",
				Name = "Банановая кожура",
				Description = "Скользкая ловушка, отправляет в полёт к краю платформы.",
				PriceCoins = Config.Shop.PrankPrices.BananaPeel,
				PriceRobux = Config.Shop.Products.BananaPeel,
			},
			{
				Id = "FreezeBeam",
				Name = "Ледяной луч",
				Description = "Замораживает жертву на 5 сек, оглушение!",
				PriceCoins = Config.Shop.PrankPrices.FreezeBeam,
				PriceRobux = Config.Shop.Products.FreezeBeam,
			},
			{
				Id = "SlimeCannon",
				Name = "Слайм-пушка",
				Description = "Стреляет слайм-ядром. Сила растёт с сессией в круге!",
				PriceCoins = Config.Shop.PrankPrices.SlimeCannon,
				PriceRobux = Config.Shop.Products.SlimeCannon,
			},
		},
		GamePasses = {
			{ Id = "VIP", Name = "VIP (+25% монет)", PassId = Config.Shop.GamePasses.VIP },
		},
	}
end

local function grantItem(player: Player, itemId: string, source: string): boolean
	if not _toolFactory then
		warn("[JMC][Shop] ToolFactory не проинициализирован")
		return false
	end
	local ok = _toolFactory:Give(player, itemId)
	if ok then
		ShopService.PurchaseGranted:Fire(player, itemId, source)
		Remotes.Event("PurchaseResult"):FireClient(player, {
			ok = true,
			itemId = itemId,
			source = source,
		})
	else
		Remotes.Event("PurchaseResult"):FireClient(player, {
			ok = false,
			itemId = itemId,
			source = source,
			reason = "grant_failed",
		})
	end
	return ok
end

-- =====================================================================
-- Purchase за Robux (Developer Products)
-- =====================================================================
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local itemId = productToItem[receipt.ProductId]
	if not itemId then
		warn("[JMC][Shop] Unknown ProductId:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Идемпотентность: через DataService
	if _data then
		local alreadyProcessed = false
		pcall(function()
			alreadyProcessed = _data:IsReceiptProcessed(player, receipt.PurchaseId)
		end)
		if alreadyProcessed then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local ok = grantItem(player, itemId, "robux")
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Отмечаем как обработанное
	if _data then
		pcall(function()
			_data:MarkReceiptProcessed(player, receipt.PurchaseId)
		end)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- =====================================================================
-- Purchase за coins (внутренняя валюта)
-- =====================================================================
local function tryBuyWithCoins(player: Player, itemId: string): (boolean, string?)
	if not _reward then
		return false, "reward_service_missing"
	end
	local price = Config.Shop.PrankPrices[itemId]
	if not price then
		return false, "unknown_item"
	end

	local balance = _reward:GetCoins(player)
	if balance < price then
		return false, "insufficient_coins"
	end

	-- Списание
	local spent = false
	if _reward.SpendCoins then
		spent = _reward:SpendCoins(player, price)
	elseif _reward.IncrementCoins then
		_reward:IncrementCoins(player, -price)
		spent = true
	end
	if not spent then
		return false, "spend_failed"
	end

	local granted = grantItem(player, itemId, "coins")
	if not granted then
		-- Возвращаем монеты
		if _reward.IncrementCoins then
			_reward:IncrementCoins(player, price)
		end
		return false, "grant_failed"
	end
	return true, nil
end

-- =====================================================================
-- Init / Start
-- =====================================================================
function ShopService:Init(toolFactory, reward, data)
	_toolFactory = toolFactory
	_reward = reward
	_data = data

	-- Собираем карту productId → itemId
	for name, pid in pairs(Config.Shop.Products) do
		if typeof(pid) == "number" and pid > 0 then
			productToItem[pid] = name
		end
	end
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

function ShopService:Start()
	if not _toolFactory then
		_toolFactory = tryRequireSibling("ToolFactory")
	end
	if not _reward then
		_reward = tryRequireSibling("RewardService")
	end
	if not _data then
		_data = tryRequireSibling("DataService")
	end

	-- Обновим карту productId → itemId (если Init не был вызван)
	if next(productToItem) == nil then
		for name, pid in pairs(Config.Shop.Products) do
			if typeof(pid) == "number" and pid > 0 then
				productToItem[pid] = name
			end
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt

	-- Клиент открывает магазин
	Remotes.Event("RequestShopOpen").OnServerEvent:Connect(function(player)
		Remotes.Event("ShopOpen"):FireClient(player, buildCatalog())
	end)

	-- Клиент тыкает «Купить»
	Remotes.Event("RequestPurchase").OnServerEvent:Connect(function(player, itemId, source)
		if typeof(itemId) ~= "string" then
			return
		end
		source = source or "coins"
		if source == "robux" then
			local pid = Config.Shop.Products[itemId]
			if pid and pid > 0 then
				MarketplaceService:PromptProductPurchase(player, pid)
			else
				Remotes.Event("PurchaseResult"):FireClient(player, {
					ok = false,
					itemId = itemId,
					reason = "product_not_published",
				})
			end
		else
			local ok, reason = tryBuyWithCoins(player, itemId)
			if not ok then
				Remotes.Event("PurchaseResult"):FireClient(player, {
					ok = false,
					itemId = itemId,
					source = "coins",
					reason = reason,
				})
			end
		end
	end)

	-- RemoteFunction каталога
	Remotes.Func("GetShopCatalog").OnServerInvoke = function(_player)
		return buildCatalog()
	end

	-- GamePass (VIP)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local vipId = Config.Shop.GamePasses.VIP
			if vipId and vipId > 0 then
				local ok, owns =
					pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, vipId)
				if ok and owns and _reward and _reward.SetVIP then
					_reward:SetVIP(player, true)
				end
			end
		end)
	end)

	print("[JMC][Shop] Магазин Пакостей запущен")
end

function ShopService:GetCatalog()
	return buildCatalog()
end

return ShopService
