--!strict
--[[
    JellyMicroJolt.client.lua (v3.0.1)
    Клиентская «желейная нестабильность»:
      - Микро-толчки (синусоидальный drift) — тело всегда слегка покачивается
      - Инерционный дрифт — при движении/остановке добавляем импульс, чтобы
        Humanoid не мог мгновенно погасить скорость (Friction 0.02 одна Humanoid
        не убеждает — он сам тормозит через внутренний контроллер)

    Работает только на клиенте — владельце физики собственного HRP.
--]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local joltCfg = Config.Monster.MicroJolt
local driftCfg = Config.Monster.Drift

if not joltCfg.Enabled and not (driftCfg and driftCfg.Enabled) then
	return
end

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

-- Проверка, что персонаж стоит на платформе-монстре (OuterShell), а не на земле
local function onMonsterShell(): boolean
	local floor = humanoid.FloorMaterial
	-- Glass — материал OuterShell. На нём применяется желейная физика.
	return floor == Enum.Material.Glass
end

local function isJoltable(): boolean
	if not hrp.Parent then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end
	if humanoid.Sit then
		return false
	end
	return true
end

-- Накопленный «остаточный» импульс дрифта
local residualVel = Vector3.zero

local connection
connection = RunService.RenderStepped:Connect(function(dt)
	if not isJoltable() then
		return
	end
	if not onMonsterShell() then
		residualVel = Vector3.zero
		return
	end

	local mass = hrp.AssemblyMass
	local t = tick()

	-- 1. Микро-толчки (синус) — всегда активны на шелле
	if joltCfg.Enabled then
		local drift = Vector3.new(
			math.sin(t * joltCfg.SpeedX) * joltCfg.IntensityX,
			0,
			math.cos(t * joltCfg.SpeedZ) * joltCfg.IntensityZ
		)
		hrp:ApplyImpulse(drift * mass * joltCfg.ImpulseScale)
	end

	-- 2. Дрифт-инерция: запоминаем горизонтальную скорость, плавно гасим её,
	-- добавляем остаток обратно как импульс → Humanoid не может мгновенно
	-- остановиться, проскальзывает.
	if driftCfg and driftCfg.Enabled then
		local vel = hrp.AssemblyLinearVelocity
		local horiz = Vector3.new(vel.X, 0, vel.Z)
		-- Усиливаем текущую горизонтальную инерцию
		residualVel = residualVel * driftCfg.DriftDecay + horiz * (1 - driftCfg.DriftDecay)
		if residualVel.Magnitude > 0.1 then
			local push = residualVel * (driftCfg.InertiaBoost - 1.0) * dt
			hrp:ApplyImpulse(push * mass)
		end
	end
end)

humanoid.Died:Connect(function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end)
