--!strict
--[[
    TransformationService.lua
    Три стадии трансформации игрока от непрерывного времени в круге:
      Stage 1 (300 сек): «Желейный блеск» — Neon + Transparency=0.3 + pulse
      Stage 2 (900 сек): «Цыплёнок-Слайм» — клюв на голове (Cone+Sphere) + «ПИ-ПИ» на прыжок
      Stage 3 (1800 сек): «Диско-Монстр» — PointLight с HSV-циклом + Neon + Reflectance
    Сбрасывается при выходе из круга.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local TransformationService = {}

TransformationService.StageChanged = Signal.new() -- (player, stage:number, stageName:string)

-- Храним состояние трансформации на игрока
-- player -> { stage:number, attachments:{Instance}, jumpConn:RBXScriptConnection? }
local applied: { [Player]: any } = {}

-- Кэш ссылок
local _presence = nil

local STAGE_NAMES = {
	[1] = "Желейный блеск",
	[2] = "Цыплёнок-Слайм",
	[3] = "Диско-Монстр",
}

local function saveOriginalLook(char: Model): {
	[BasePart]: { Transparency: number, Material: Enum.Material, Reflectance: number, Color: Color3 },
}
	local snapshot = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			snapshot[d] = {
				Transparency = d.Transparency,
				Material = d.Material,
				Reflectance = d.Reflectance,
				Color = d.Color,
			}
		end
	end
	return snapshot
end

local function restoreLook(snapshot)
	for part, orig in pairs(snapshot) do
		if part.Parent then
			part.Transparency = orig.Transparency
			part.Material = orig.Material
			part.Reflectance = orig.Reflectance
			part.Color = orig.Color
		end
	end
end

-- ======================= STAGE 1: Jelly Glow =======================
local function applyStage1(player: Player, state)
	local char = player.Character
	if not char then
		return
	end

	state.snapshot = saveOriginalLook(char)

	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.Neon
			d.Transparency = 0.3
			d.Reflectance = 0.15
		end
	end

	-- Лёгкий pulse через tween.Size (через Attachment+Highlight — проще)
	local hl = Instance.new("Highlight")
	hl.Name = "JMC_JellyGlow"
	hl.FillColor = Color3.fromRGB(255, 180, 220)
	hl.FillTransparency = 0.7
	hl.OutlineColor = Color3.fromRGB(255, 120, 200)
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = char
	table.insert(state.instances, hl)

	-- Пульс FillTransparency
	task.spawn(function()
		while hl.Parent and applied[player] and applied[player].stage >= 1 do
			local up = TweenService:Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { FillTransparency = 0.4 })
			up:Play()
			up.Completed:Wait()
			if not hl.Parent then
				break
			end
			local dn = TweenService:Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { FillTransparency = 0.85 })
			dn:Play()
			dn.Completed:Wait()
		end
	end)
end

-- ======================= STAGE 2: Chick-Slime =======================
local function applyStage2(player: Player, state)
	local char = player.Character
	if not char then
		return
	end
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	-- Клюв: Cone-часть (WedgePart)
	local beak = Instance.new("Part")
	beak.Name = "JMC_ChickBeak"
	beak.Shape = Enum.PartType.Wedge
	beak.Size = Vector3.new(0.5, 0.6, 0.8)
	beak.Material = Enum.Material.SmoothPlastic
	beak.Color = Color3.fromRGB(255, 180, 40)
	beak.CanCollide = false
	beak.Massless = true
	beak.CFrame = head.CFrame * CFrame.new(0, -0.1, -head.Size.Z / 2 - 0.2) * CFrame.Angles(0, math.rad(180), 0)
	local weldBeak = Instance.new("WeldConstraint")
	weldBeak.Part0 = head
	weldBeak.Part1 = beak
	weldBeak.Parent = beak
	beak.Parent = char
	table.insert(state.instances, beak)

	-- Два глазика
	for _, sign in ipairs({ -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Name = "JMC_ChickEye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.25, 0.25, 0.25)
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(10, 10, 10)
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(sign * 0.35, 0.25, -head.Size.Z / 2 - 0.05)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
		eye.Parent = char
		table.insert(state.instances, eye)
	end

	-- Звук "PI-PI!" на прыжок
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		local snd = Instance.new("Sound")
		snd.Name = "JMC_ChickPiPi"
		local pipiId = Config.Transformations.Stage2.PiPiSoundId
		if pipiId and pipiId ~= 0 then
			snd.SoundId = "rbxassetid://" .. tostring(pipiId)
		end
		snd.Volume = 1
		snd.Parent = head
		table.insert(state.instances, snd)

		state.jumpConn = hum.Jumping:Connect(function(active)
			if active and snd.SoundId ~= "" then
				snd.PlaybackSpeed = 0.9 + math.random() * 0.3
				snd:Play()
			end
		end)
	end
end

-- ======================= STAGE 3: Disco =======================
local function applyStage3(player: Player, state)
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local cfg = Config.Transformations.Stage3

	local light = Instance.new("PointLight")
	light.Name = "JMC_DiscoLight"
	light.Brightness = cfg.PointLightBrightness or 3
	light.Range = cfg.PointLightRange or 14
	light.Color = Color3.new(1, 1, 1)
	light.Parent = hrp
	table.insert(state.instances, light)

	-- Neon + Reflectance на все части
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.Neon
			d.Reflectance = 0.5
		end
	end

	local hueSpeed = cfg.HSVCycleSpeed or 0.2
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not light.Parent or not applied[player] then
			conn:Disconnect()
			return
		end
		local h = (os.clock() * hueSpeed) % 1
		local c = Color3.fromHSV(h, 1, 1)
		light.Color = c
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.Color = c
			end
		end
	end)
	table.insert(state.instances, {
		Disconnect = function()
			if conn then
				conn:Disconnect()
			end
		end,
	})
end

local function computeStage(timeSec: number): number
	if timeSec >= Config.Transformations.Stage3Time then
		return 3
	end
	if timeSec >= Config.Transformations.Stage2Time then
		return 2
	end
	if timeSec >= Config.Transformations.Stage1Time then
		return 1
	end
	return 0
end

local function clearTransformation(player: Player)
	local state = applied[player]
	if not state then
		return
	end
	applied[player] = nil

	if state.jumpConn then
		state.jumpConn:Disconnect()
	end
	for _, inst in ipairs(state.instances) do
		if typeof(inst) == "Instance" and inst.Parent then
			inst:Destroy()
		elseif typeof(inst) == "table" and inst.Disconnect then
			inst:Disconnect()
		end
	end
	if state.snapshot then
		restoreLook(state.snapshot)
	end
end

local function setStage(player: Player, newStage: number)
	local current = applied[player] and applied[player].stage or 0
	if current == newStage then
		return
	end

	clearTransformation(player)
	if newStage <= 0 then
		TransformationService.StageChanged:Fire(player, 0, nil)
		Remotes.Event("TransformationApplied"):FireClient(player, 0, nil)
		return
	end

	local state = { stage = newStage, instances = {}, snapshot = nil, jumpConn = nil }
	applied[player] = state

	if newStage >= 1 then
		applyStage1(player, state)
	end
	if newStage >= 2 then
		applyStage2(player, state)
	end
	if newStage >= 3 then
		applyStage3(player, state)
	end

	TransformationService.StageChanged:Fire(player, newStage, STAGE_NAMES[newStage])
	Remotes.Event("TransformationApplied"):FireClient(player, newStage, STAGE_NAMES[newStage])
	Remotes.Event("EventBanner")
		:FireClient(
			player,
			"ТРАНСФОРМАЦИЯ: " .. STAGE_NAMES[newStage] .. "!",
			Color3.fromRGB(255, 180, 220)
		)
end

function TransformationService:Init(presence)
	_presence = presence
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

function TransformationService:Start()
	if not _presence then
		_presence = tryRequireSibling("CirclePresence")
	end
	if not _presence then
		warn("[JMC][Transform] CirclePresence не найден — трансформации отключены")
		return
	end

	_presence.Tick:Connect(function()
		for _, p in ipairs(Players:GetPlayers()) do
			local t = _presence:GetContinuousTime(p)
			local stage = computeStage(t)
			local currentStage = applied[p] and applied[p].stage or 0
			if stage ~= currentStage then
				setStage(p, stage)
			end
		end
	end)

	_presence.PlayerExited:Connect(function(player)
		clearTransformation(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearTransformation(player)
	end)

	print("[JMC][Transform] Сервис трансформаций активен")
end

function TransformationService:GetStage(player: Player): number
	return applied[player] and applied[player].stage or 0
end

function TransformationService:ForceStage(player: Player, stage: number)
	setStage(player, math.clamp(stage, 0, 3))
end

return TransformationService
