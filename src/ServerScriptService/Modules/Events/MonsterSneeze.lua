--!strict
--[[
    Событие №5: «Чих Монстра» (Monster Sneeze)
    - 3 секунды жёлтый предупреждающий highlight на платформе.
    - Затем мощный ApplyImpulse от центра во все стороны ко всем игрокам в круге.
    - Большой ParticleEmitter с «соплями/слизью» в центре.
    - Клиенту — зелёный оверлей на экран.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "MonsterSneeze"
E.DisplayName = "АПЧХИ!!!"
E.Color = Color3.fromRGB(180, 255, 120)
E.Overlay = "slime"
E.Duration = Config.Events.MonsterSneeze.Duration or 6

function E.Start(ctx)
	local base = ctx.platform:GetBasePart()
	if not base then
		return
	end

	local center = ctx.platform:GetCenter()
	local surfaceY = ctx.platform:GetSurfaceY()
	local warnTime = Config.Events.MonsterSneeze.WarnTime or 3
	local blastImpulse = Config.Events.MonsterSneeze.BlastImpulse or 220
	local blastUp = Config.Events.MonsterSneeze.BlastUp or 80

	-- Фаза 1: предупреждение — жёлтый SelectionBox + ColorTween
	local highlight = Instance.new("SelectionBox")
	highlight.Adornee = base
	highlight.Color3 = Color3.fromRGB(255, 230, 60)
	highlight.LineThickness = 0.4
	highlight.SurfaceTransparency = 0.6
	highlight.SurfaceColor3 = Color3.fromRGB(255, 240, 120)
	highlight.Parent = base

	local origColor = base.Color
	local blinkEnd = os.clock() + warnTime
	task.spawn(function()
		while os.clock() < blinkEnd do
			local tw = TweenService:Create(highlight, TweenInfo.new(0.2), { SurfaceTransparency = 0.2 })
			tw:Play()
			tw.Completed:Wait()
			tw = TweenService:Create(highlight, TweenInfo.new(0.2), { SurfaceTransparency = 0.8 })
			tw:Play()
			tw.Completed:Wait()
		end
	end)

	-- Клиентам — «накопление» чиха через музыку
	Remotes.Event("MusicCue"):FireAllClients("tension", warnTime)

	task.wait(warnTime)
	if highlight.Parent then
		highlight:Destroy()
	end

	-- Фаза 2: ЧИХ!
	-- Огромный взрыв частиц в центре
	local sneezeAnchor = Instance.new("Part")
	sneezeAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
	sneezeAnchor.Anchored = true
	sneezeAnchor.CanCollide = false
	sneezeAnchor.Transparency = 1
	sneezeAnchor.Position = Vector3.new(center.X, surfaceY + 3, center.Z)
	sneezeAnchor.Parent = workspace

	local attach = Instance.new("Attachment")
	attach.Parent = sneezeAnchor

	-- Основной «поток слизи»
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(1.5, 3)
	pe.Speed = NumberRange.new(60, 100)
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 255, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 100)),
	})
	pe.Size = NumberSequence.new(2, 6)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.LightEmission = 0.4
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.Parent = attach
	pe:Emit(120)

	Debris:AddItem(sneezeAnchor, 4)

	-- Импульс ко всем игрокам в круге — радиально от центра
	for _, p in ipairs(ctx.presence:GetPlayersInside()) do
		local char = p.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local dir = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
				if dir.Magnitude < 0.5 then
					local a = math.random() * math.pi * 2
					dir = Vector3.new(math.cos(a), 0, math.sin(a))
				end
				local push = dir.Unit * blastImpulse + Vector3.new(0, blastUp, 0)
				hrp:ApplyImpulse(push * hrp.AssemblyMass)

				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and ctx.ragdoll then
					ctx.ragdoll:Apply(hum, 1.2)
				end
			end
		end
	end

	-- Клиентам — оверлей зелёной слизи, камерная тряска, хаптик
	Remotes.Event("OverlayFX"):FireAllClients("slime", 2.5)
	Remotes.Event("CameraShake"):FireAllClients(8, 0.6)
	Remotes.Event("HapticPulse"):FireAllClients(1, 0.5)
end

function E.Stop(ctx)
	-- ничего чистить не надо: всё на Debris
end

return E
