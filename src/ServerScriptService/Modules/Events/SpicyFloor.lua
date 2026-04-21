--!strict
--[[
    Событие №10: «Острый пол» (Spicy Floor)
    - Поверхность платформы «пылает». Материал → Neon, цвет → красный, ParticleEmitter огня.
    - Каждые Config.Events.SpicyFloor.TickInterval секунд:
        - всем в круге даётся вертикальный ApplyImpulse (как будто подпрыгивают от жара);
        - лёгкий ragdoll пульс (опционально).
    - Клиенту — красные края экрана (vignette) + хаптик.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "SpicyFloor"
E.DisplayName = "ОСТРЫЙ ПОЛ!"
E.Color = Color3.fromRGB(255, 80, 40)
E.Overlay = "spicy"
E.Duration = Config.Events.SpicyFloor.Duration

function E.Start(ctx)
	local base = ctx.platform:GetBasePart()
	if not base then
		return
	end

	-- Сохраняем исходный вид
	local origMaterial = base.Material
	local origColor = base.Color
	local origReflect = base.Reflectance

	base.Material = Enum.Material.Neon
	base.Color = Color3.fromRGB(255, 90, 50)
	base.Reflectance = 0

	-- Огненные частицы
	local attach = Instance.new("Attachment")
	attach.Name = "JMC_SpicyAttach"
	attach.Position = Vector3.new(0, base.Size.Y / 2, 0)
	attach.Parent = base

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "JMC_SpicyFire"
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Rate = 200
	pe.Lifetime = NumberRange.new(0.6, 1.4)
	pe.Speed = NumberRange.new(6, 14)
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 20, 0)),
	})
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.LightEmission = 0.9
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.Acceleration = Vector3.new(0, 6, 0)
	pe.EmissionDirection = Enum.NormalId.Top
	-- Распределяем по верхней поверхности цилиндра
	pe.Shape = Enum.ParticleEmitterShape.Cylinder
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	pe.Parent = attach

	Remotes.Event("OverlayFX"):FireAllClients("spicy", E.Duration)
	Remotes.Event("MusicCue"):FireAllClients("intense", E.Duration)

	local tickInterval = Config.Events.SpicyFloor.BounceInterval or 0.5
	local verticalImpulse = Config.Events.SpicyFloor.BounceImpulse or 80
	local sideImpulse = verticalImpulse * 0.25 -- маленький случайный сдвиг в сторону
	local endTick = os.clock() + (E.Duration or 15)

	while os.clock() < endTick do
		for _, p in ipairs(ctx.presence:GetPlayersInside()) do
			local char = p.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local a = math.random() * math.pi * 2
					local imp = Vector3.new(math.cos(a) * sideImpulse, verticalImpulse, math.sin(a) * sideImpulse)
					hrp:ApplyImpulse(imp * hrp.AssemblyMass)
				end
			end
		end
		Remotes.Event("HapticPulse"):FireAllClients(0.3, tickInterval * 0.6)
		task.wait(tickInterval)
	end

	-- Откат вида
	if pe.Parent then
		pe:Destroy()
	end
	if attach.Parent then
		attach:Destroy()
	end
	base.Material = origMaterial
	base.Color = origColor
	base.Reflectance = origReflect
end

function E.Stop(ctx)
	local base = ctx.platform:GetBasePart()
	if base then
		local attach = base:FindFirstChild("JMC_SpicyAttach")
		if attach then
			attach:Destroy()
		end
	end
end

return E
