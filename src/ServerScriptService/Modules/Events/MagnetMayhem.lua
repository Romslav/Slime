--!strict
--[[
    Событие №8: «Магнитный хаос» (Magnet Mayhem)
    - Игроков в круге делим на две команды: "+" и "−".
    - Над головой — BillboardGui со знаком.
    - Одноимённые отталкиваются, разноимённые притягиваются.
    - Реализовано через ApplyImpulse в Heartbeat-цикле (мягко, кэпим по дистанции).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "MagnetMayhem"
E.DisplayName = "МАГНИТНЫЙ ХАОС!"
E.Color = Color3.fromRGB(120, 160, 255)
E.Duration = Config.Events.MagnetMayhem.Duration

local function makeSignBillboard(char: Model, sign: string, color: Color3): BillboardGui?
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "JMC_MagnetSign"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(80, 80)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = head

	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = color
	bg.BackgroundTransparency = 0.2
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = bg
	bg.Parent = bb

	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.Text = sign
	txt.TextColor3 = Color3.new(1, 1, 1)
	txt.Font = Enum.Font.FredokaOne
	txt.TextScaled = true
	txt.Parent = bg

	return bb
end

function E.Start(ctx)
	local baseForce = Config.Events.MagnetMayhem.Force or 7500
	-- В одной константе хранится ньютон-подобный коэф.; ниже он нормируется на dt и массу
	local attractForce = baseForce / 150 -- ≈50 при 7500
	local repelForce = baseForce / 180 -- чуть слабее, чтобы не разбрасывало мгновенно
	local maxDist = Config.Events.MagnetMayhem.MaxRange or 60

	local players = ctx.presence:GetPlayersInside()
	if #players < 2 then
		-- Одиночка — событие бессмысленно, но пусть отработает короткий визуал
		Remotes.Event("EventBanner")
			:FireAllClients("Нужен соперник! Зови друга.", Color3.fromRGB(180, 200, 255))
		task.wait(3)
		return
	end

	-- Случайно назначаем + и -
	local signs: { [Player]: number } = {}
	local bbs: { BillboardGui } = {}
	for i, p in ipairs(players) do
		local s = (i % 2 == 0) and 1 or -1
		signs[p] = s
		if p.Character then
			local bb = makeSignBillboard(
				p.Character,
				s > 0 and "+" or "−",
				s > 0 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(90, 140, 255)
			)
			if bb then
				table.insert(bbs, bb)
			end
		end
	end

	Remotes.Event("OverlayFX"):FireAllClients("magnet", E.Duration)

	local endTick = os.clock() + (E.Duration or 15)
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt)
		if os.clock() >= endTick then
			if conn then
				conn:Disconnect()
			end
			return
		end

		local playerList = ctx.presence:GetPlayersInside()
		-- Попарно применяем силы
		for i = 1, #playerList do
			local a = playerList[i]
			local sA = signs[a]
			if not sA then
				continue
			end
			local charA = a.Character
			if not charA then
				continue
			end
			local hrpA = charA:FindFirstChild("HumanoidRootPart")
			if not hrpA or not hrpA:IsA("BasePart") then
				continue
			end

			for j = i + 1, #playerList do
				local b = playerList[j]
				local sB = signs[b]
				if not sB then
					continue
				end
				local charB = b.Character
				if not charB then
					continue
				end
				local hrpB = charB:FindFirstChild("HumanoidRootPart")
				if not hrpB or not hrpB:IsA("BasePart") then
					continue
				end

				local delta = hrpB.Position - hrpA.Position
				local dist = delta.Magnitude
				if dist < 0.5 or dist > maxDist then
					continue
				end
				local dir = delta.Unit

				-- same sign → отталкивание, opp sign → притяжение
				local magnitude
				if sA == sB then
					magnitude = -repelForce
				else
					magnitude = attractForce
				end
				-- Затухание с расстоянием
				local falloff = math.clamp(1 - dist / maxDist, 0.1, 1)
				local imp = dir * magnitude * falloff * dt * 30
				hrpA:ApplyImpulse(imp * hrpA.AssemblyMass)
				hrpB:ApplyImpulse(-imp * hrpB.AssemblyMass)
			end
		end
	end)

	task.wait(E.Duration or 15)
	if conn then
		conn:Disconnect()
	end

	for _, bb in ipairs(bbs) do
		if bb.Parent then
			bb:Destroy()
		end
	end
end

function E.Stop(ctx)
	-- Подчистим любые висящие бейджи
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		local char = p.Character
		if char then
			local head = char:FindFirstChild("Head")
			if head then
				local bb = head:FindFirstChild("JMC_MagnetSign")
				if bb then
					bb:Destroy()
				end
			end
		end
	end
end

return E
