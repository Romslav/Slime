--!strict
--[[
    MusicManager.lua (клиент)
    Проигрывает фоновый саундтрек. На MusicCue с сервера меняет:
      ambient  → нормальная скорость (1.0), спокойный трек
      intense  → PlaybackSpeed=1.2
      tension  → PlaybackSpeed=0.9 (мрачнее)
      float    → PlaybackSpeed=0.85, мягкий fade
    Плавно (Tween) возвращает в ambient после duration.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MusicManager = {}

local sound: Sound? = nil

local MODES = {
    ambient = { speed = 1.0, volume = 0.5 },
    intense = { speed = 1.2, volume = 0.65 },
    tension = { speed = 0.88, volume = 0.55 },
    float   = { speed = 0.85, volume = 0.45 },
}

local function ensureSound()
    if sound and sound.Parent then return end
    local s = Instance.new("Sound")
    s.Name = "JMC_Music"
    local id = Config.Audio and Config.Audio.Music and Config.Audio.Music.Ambient or 0
    if id and id ~= 0 then
        s.SoundId = "rbxassetid://" .. tostring(id)
    end
    s.Volume = 0.5
    s.Looped = true
    s.Parent = SoundService
    s:Play()
    sound = s
end

local function setMode(mode: string, duration: number?)
    ensureSound()
    if not sound then return end
    local m = MODES[mode] or MODES.ambient
    local tw = TweenService:Create(sound, TweenInfo.new(1, Enum.EasingStyle.Sine),
        { PlaybackSpeed = m.speed, Volume = m.volume })
    tw:Play()

    if duration and duration > 0 and mode ~= "ambient" then
        task.delay(duration, function()
            if sound then
                local back = TweenService:Create(sound, TweenInfo.new(1.2),
                    { PlaybackSpeed = MODES.ambient.speed, Volume = MODES.ambient.volume })
                back:Play()
            end
        end)
    end
end

function MusicManager:Start()
    ensureSound()

    Remotes.Event("MusicCue").OnClientEvent:Connect(function(mode, duration)
        setMode(tostring(mode or "ambient"), duration)
    end)

    print("[JMC][Client] MusicManager готов")
end

return MusicManager
