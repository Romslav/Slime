--!strict
--[[
    ShopUI.lua (клиент)
    Рисует магазин в модальном окне по сигналу ShopOpen от сервера.
    По тапу «Купить» шлёт RequestPurchase с выбранным source (coins/robux).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopUI = {}
local player = Players.LocalPlayer

local _gui: ScreenGui? = nil

local function buildGui(): ScreenGui
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "JMC_ShopUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.Parent = pg
	return gui
end

local function makeItemCard(parent: ScrollingFrame, item): Frame
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(40, 20, 55)
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, -20, 0, 120)
	card.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -20, 0, 36)
	name.Position = UDim2.new(0, 10, 0, 6)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = item.Name or item.Id
	name.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -20, 0, 40)
	desc.Position = UDim2.new(0, 10, 0, 44)
	desc.Font = Enum.Font.Gotham
	desc.TextScaled = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = Color3.fromRGB(220, 200, 230)
	desc.TextWrapped = true
	desc.Text = item.Description or ""
	desc.Parent = card

	local buyCoins = Instance.new("TextButton")
	buyCoins.Font = Enum.Font.FredokaOne
	buyCoins.TextScaled = true
	buyCoins.TextColor3 = Color3.new(1, 1, 1)
	buyCoins.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	buyCoins.Size = UDim2.new(0, 140, 0, 40)
	buyCoins.Position = UDim2.new(1, -300, 1, -48)
	buyCoins.Text = string.format("💰 %d", item.PriceCoins or 0)
	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0.3, 0)
	cCorner.Parent = buyCoins
	buyCoins.Parent = card
	buyCoins.Activated:Connect(function()
		Remotes.Event("RequestPurchase"):FireServer(item.Id, "coins")
	end)

	local buyRobux = Instance.new("TextButton")
	buyRobux.Font = Enum.Font.FredokaOne
	buyRobux.TextScaled = true
	buyRobux.TextColor3 = Color3.new(1, 1, 1)
	buyRobux.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
	buyRobux.Size = UDim2.new(0, 140, 0, 40)
	buyRobux.Position = UDim2.new(1, -150, 1, -48)
	buyRobux.Text = (item.PriceRobux and item.PriceRobux > 0) and "💎 Robux" or "—"
	buyRobux.AutoButtonColor = item.PriceRobux and item.PriceRobux > 0
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0.3, 0)
	rCorner.Parent = buyRobux
	buyRobux.Parent = card
	buyRobux.Activated:Connect(function()
		Remotes.Event("RequestPurchase"):FireServer(item.Id, "robux")
	end)

	return card
end

local function render(catalog)
	if _gui then
		_gui:Destroy()
	end
	_gui = buildGui()
	if not _gui then
		return
	end

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = _gui

	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = Color3.fromRGB(60, 30, 80)
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(0.6, 0, 0.75, 0)
	panel.Position = UDim2.new(0.2, 0, 0.12, 0)
	panel.Parent = _gui
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 16)
	pCorner.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.new(0, 0, 0, 6)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "🛒 МАГАЗИН ПАКОСТЕЙ"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.Text = "×"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(200, 50, 90)
	close.Size = UDim2.new(0, 44, 0, 44)
	close.Position = UDim2.new(1, -52, 0, 8)
	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0.5, 0)
	cCorner.Parent = close
	close.Parent = panel
	close.Activated:Connect(function()
		if _gui then
			_gui.Enabled = false
		end
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.new(1, -20, 1, -80)
	scroll.Position = UDim2.new(0, 10, 0, 70)
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = scroll

	for _, item in ipairs(catalog.Items or {}) do
		makeItemCard(scroll, item)
	end

	_gui.Enabled = true
end

function ShopUI:Start()
	Remotes.Event("ShopOpen").OnClientEvent:Connect(function(catalog)
		render(catalog)
	end)

	Remotes.Event("PurchaseResult").OnClientEvent:Connect(function(result)
		-- Короткий flash сверху: успешно/нет
		-- Используем имеющийся HUD-слой? Для простоты: print
		if result.ok then
			print("[Shop] Куплено:", result.itemId)
		else
			print("[Shop] Не удалось:", result.itemId, result.reason)
		end
	end)

	print("[JMC][Client] ShopUI готов")
end

return ShopUI
