--!strict
--[[
    AuraService.lua
    У каждого игрока в HRP живёт Attachment + ParticleEmitter.
    Rate и Size растут пропорционально непрерывному времени в круге.
    Держатель серверного рекорда (bestSessionTime из LeaderboardService)
    получает поверх ауры Beam-молнии на ноги.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local AuraService = {}

AuraService.RecordHolderChanged = Signal.new() -- (player|nil)

-- player -> { attach, emitter, beamParts:{Instance} }
local auras: { [Player]: any } = {}

local _presence = nil
local _leaderboard = nil
local _recordHolder: Player? = nil

local function colorFromTime(t: number): Color3
    -- От розово-желейного к электрически-голубому через розово-фиолетовое
    local h = math.clamp(0.95 - math.min(t / 1800, 1) * 0.4, 0.5, 0.95)
    return Color3.fromHSV(h, 0.7, 1)
end

local function ensureAura(player: Player)
    if auras[player] then return auras[player] end
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsA("BasePart") then return nil end

    local attach = Instance.new("Attachment")
    attach.Name = "JMC_AuraAttach"
    attach.Parent = hrp

    local pe = Instance.new("ParticleEmitter")
    pe.Name = "JMC_Aura"
    local tex = Config.Aura.ParticleTextureId
    if tex and tex ~= 0 then
        pe.Texture = "rbxassetid://" .. tostring(tex)
    else
        pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    end
    pe.Rate = Config.Aura.BaseRate
    pe.Lifetime = NumberRange.new(1.5, 2.5)
    pe.Speed = NumberRange.new(1, 4)
    pe.Size = NumberSequence.new(Config.Aura.BaseSize)
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.LightEmission = 0.8
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Rotation = NumberRange.new(0, 360)
    pe.Parent = attach

    local state = { attach = attach, emitter = pe, beamParts = {} }
    auras[player] = state
    return state
end

local function removeAura(player: Player)
    local state = auras[player]
    if not state then return end
    auras[player] = nil
    if state.attach and state.attach.Parent then state.attach:Destroy() end
    for _, inst in ipairs(state.beamParts) do
        if inst and inst.Parent then inst:Destroy() end
    end
end

local function updateAura(player: Player, t: number)
    local state = ensureAura(player)
    if not state then return end
    local pe: ParticleEmitter = state.emitter

    local rate = math.min(
        Config.Aura.BaseRate + t * Config.Aura.RatePerSecond,
        Config.Aura.MaxRate
    )
    pe.Rate = rate

    local size = math.min(
        Config.Aura.BaseSize + (t / 60) * Config.Aura.SizePerMinute,
        Config.Aura.MaxSize
    )
    pe.Size = NumberSequence.new(size, size * 0.3)

    pe.Color = ColorSequence.new(colorFromTime(t))
end

-- Молнии для держателя рекорда
local function attachRecordBeams(player: Player)
    local state = auras[player]
    if not state then return end
    -- Уже привязаны?
    for _, inst in ipairs(state.beamParts) do
        if typeof(inst) == "Instance" and inst:IsA("Beam") then return end
    end

    local char = player.Character
    if not char then return end

    local leftFoot = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg")
    local rightFoot = char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg")
    if not leftFoot or not rightFoot then return end
    if not (leftFoot:IsA("BasePart") and rightFoot:IsA("BasePart")) then return end

    local aLeft = Instance.new("Attachment"); aLeft.Parent = leftFoot
    local aRight = Instance.new("Attachment"); aRight.Parent = rightFoot
    aLeft.Name = "JMC_RecordBeamA"
    aRight.Name = "JMC_RecordBeamB"
    table.insert(state.beamParts, aLeft)
    table.insert(state.beamParts, aRight)

    local beam = Instance.new("Beam")
    beam.Name = "JMC_RecordBeam"
    beam.Attachment0 = aLeft
    beam.Attachment1 = aRight
    local texId = Config.Aura.RecordBeamTextureId
    if texId and texId ~= 0 then
        beam.Texture = "rbxassetid://" .. tostring(texId)
    end
    beam.Width0 = 0.8
    beam.Width1 = 0.8
    beam.TextureSpeed = 4
    beam.TextureMode = Enum.TextureMode.Stretch
    beam.LightEmission = 1
    beam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 220, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 160, 255)),
    })
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    beam.Parent = aLeft
    table.insert(state.beamParts, beam)
end

local function detachRecordBeams(player: Player)
    local state = auras[player]
    if not state then return end
    local filtered = {}
    for _, inst in ipairs(state.beamParts) do
        if typeof(inst) == "Instance" and (inst.Name == "JMC_RecordBeam"
            or inst.Name == "JMC_RecordBeamA" or inst.Name == "JMC_RecordBeamB") then
            if inst.Parent then inst:Destroy() end
        else
            table.insert(filtered, inst)
        end
    end
    state.beamParts = filtered
end

function AuraService:Init(presence, leaderboard)
    _presence = presence
    _leaderboard = leaderboard
end

local function tryRequireSibling(name: string): any?
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, result = pcall(require, mod)
    if ok then return result end
    return nil
end

function AuraService:Start()
    if not _presence then
        _presence = tryRequireSibling("CirclePresence")
    end
    if not _leaderboard then
        _leaderboard = tryRequireSibling("LeaderboardService")
    end
    if not _presence then
        warn("[JMC][Aura] CirclePresence не найден — ауры отключены")
        return
    end

    _presence.Tick:Connect(function()
        for _, p in ipairs(Players:GetPlayers()) do
            local t = _presence:GetContinuousTime(p)
            if t > 0 then
                updateAura(p, t)
                if _recordHolder == p then
                    attachRecordBeams(p)
                end
            else
                if auras[p] then
                    removeAura(p)
                end
            end
        end
    end)

    _presence.PlayerExited:Connect(function(player)
        removeAura(player)
    end)

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            removeAura(player) -- будет пересоздано по Tick
        end)
    end)
    Players.PlayerRemoving:Connect(function(player)
        removeAura(player)
    end)

    print("[JMC][Aura] Сервис аур активен")
end

function AuraService:SetRecordHolder(player: Player?)
    if _recordHolder == player then return end
    if _recordHolder then
        detachRecordBeams(_recordHolder)
    end
    _recordHolder = player
    if player then
        attachRecordBeams(player)
    end
    AuraService.RecordHolderChanged:Fire(player)
end

function AuraService:GetRecordHolder(): Player?
    return _recordHolder
end

return AuraService
