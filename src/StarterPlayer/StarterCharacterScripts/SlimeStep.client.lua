--!strict
--[[
    SlimeStep.client.lua
    На каждый шаг персонажа проигрывает «Squish»-звук.
    Запускается автоматически при спавне персонажа.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local player = Players.LocalPlayer
local char = script.Parent
if not char:IsA("Model") then
	return
end

local hum = char:WaitForChild("Humanoid", 5)
if not hum or not hum:IsA("Humanoid") then
	return
end

local hrp = char:WaitForChild("HumanoidRootPart", 5)
if not hrp or not hrp:IsA("BasePart") then
	return
end

-- Сознаём звук Squish (если есть ID в Config)
local squishId = (Config.Audio and Config.Audio.Sfx and Config.Audio.Sfx.Squish) or 0

local sound: Sound? = nil
if squishId ~= 0 then
	sound = Instance.new("Sound")
	sound.Name = "JMC_SquishStep"
	sound.SoundId = "rbxassetid://" .. tostring(squishId)
	sound.Volume = 0.45
	sound.Parent = hrp
end

-- Подключаемся к Running — срабатывает, когда скорость меняется
local STEP_INTERVAL_MIN = 0.28
local lastStep = 0

hum.Running:Connect(function(speed)
	-- Если бежит — запускаем периодическую проверку
	if speed < 0.5 then
		return
	end
end)

-- Простая периодическая проверка: если движется — раз в ~0.3 сек шумит
task.spawn(function()
	while hum and hum.Parent do
		task.wait(STEP_INTERVAL_MIN)
		if not hum or hum.Health <= 0 then
			break
		end
		local vel = hrp.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if horizontalSpeed > 4 and sound and sound.SoundId ~= "" then
			sound.PlaybackSpeed = 0.9 + math.random() * 0.3
			sound:Play()
		end
	end
end)
