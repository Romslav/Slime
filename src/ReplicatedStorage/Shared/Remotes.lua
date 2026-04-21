--!strict
--[[
    Remotes.lua
    Единая фабрика RemoteEvent / RemoteFunction.
    Вызывается как с сервера, так и с клиента — первый вызов создаёт, остальные ждут.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "JMC_Remotes"

-- Список всех удалённых событий/функций, используемых в игре.
-- Имена — source of truth; менять только здесь.
local EVENT_NAMES = {
	-- Сервер → клиент
	"EventStarted", -- имя события, длительность, доп-параметры
	"EventEnded",
	"OverlayFX", -- тип оверлея: "sneeze" | "spicy" | "ice" | "clear"
	"CameraShake", -- амплитуда, длительность
	"MusicCue", -- "intense" | "calm" | "victory"
	"HapticPulse",
	"EventBanner", -- текстовая плашка события
	"EventHint", -- постоянная подсказка действия
	"VoteOpened",
	"VoteClosed",
	"ShopOpen",
	"PurchaseResult", -- успех/неуспех
	"TransformationApplied", -- stage
	"RevengeOffer", -- обидчик + скидка

	-- Клиент → сервер
	"ButtonMash", -- BubbleTrap
	"SpinCycleInput", -- dig/hold actions for SpinCycle
	"VoteCast", -- index
	"RequestShopOpen",
	"RequestPurchase", -- productId
}

local FUNCTION_NAMES = {
	"GetShopCatalog",
	"GetLeaderboard",
	"GetSelfStats",
}

local function getOrCreateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	-- Клиент: ждём, пока сервер создаст
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function ensureInstance(parent: Folder, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
		return inst
	end
	return parent:WaitForChild(name) :: Instance
end

-- На сервере — создаём всё сразу (идемпотентно)
if RunService:IsServer() then
	local folder = getOrCreateFolder()
	for _, name in ipairs(EVENT_NAMES) do
		ensureInstance(folder, "RemoteEvent", name)
	end
	for _, name in ipairs(FUNCTION_NAMES) do
		ensureInstance(folder, "RemoteFunction", name)
	end
end

--- Получить RemoteEvent по имени.
function Remotes.Event(name: string): RemoteEvent
	local folder = getOrCreateFolder()
	local remote = ensureInstance(folder, "RemoteEvent", name)
	return remote :: RemoteEvent
end

--- Получить RemoteFunction по имени.
function Remotes.Func(name: string): RemoteFunction
	local folder = getOrCreateFolder()
	local remote = ensureInstance(folder, "RemoteFunction", name)
	return remote :: RemoteFunction
end

return Remotes
