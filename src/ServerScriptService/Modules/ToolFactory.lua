--!strict
--[[
    ToolFactory.lua
    Серверный конструктор Tool-ов для пранков:
      BananaPeel  — бросает жёлтый Cylinder на пол; на .Touched → PlatformStand + ApplyImpulse к краю.
      FreezeBeam  — Raycast на клик: цель получает прозрачный синий кубик + WalkSpeed=0 на FreezeTime.
      SlimeCannon — выстрел Part-шара с BodyVelocity; на .Touched → Knockback с scaling от sessionTime.
    Tool-ы создаются в рантайме и выдаются через :Give(player, itemId).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local ToolFactory = {}

ToolFactory.PrankFired = Signal.new() -- (attacker, victim, itemId)

-- Будут подключены извне
local _ragdoll = nil
local _presence = nil
local _platform = nil

-- =====================================================================
-- Helpers
-- =====================================================================
local function getCharData(player: Player): (Model?, BasePart?, Humanoid?)
    local char = player.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and not hrp:IsA("BasePart") then hrp = nil end
    return char, hrp, hum
end

local function edgeDirectionFromCenter(pos: Vector3): Vector3
    if not _platform then return Vector3.new(1, 0, 0) end
    local center = _platform:GetCenter()
    local d = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
    if d.Magnitude < 0.1 then
        local a = math.random() * math.pi * 2
        return Vector3.new(math.cos(a), 0, math.sin(a))
    end
    return d.Unit
end

-- =====================================================================
-- BananaPeel
-- =====================================================================
local function buildBanana(): Tool
    local tool = Instance.new("Tool")
    tool.Name = "Банановая кожура"
    tool.RequiresHandle = true
    tool.CanBeDropped = false

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Shape = Enum.PartType.Cylinder
    handle.Size = Vector3.new(0.4, 1.2, 1.2)
    handle.Material = Enum.Material.SmoothPlastic
    handle.Color = Color3.fromRGB(255, 220, 60)
    handle.CanCollide = false
    handle.Parent = tool

    local cfg = Config.Pranks.BananaPeel

    tool.Activated:Connect(function()
        local owner = Players:GetPlayerFromCharacter(tool.Parent)
        if not owner then return end
        local _, hrp = getCharData(owner)
        if not hrp then return end

        -- Спавним скользкую кожуру
        local peel = Instance.new("Part")
        peel.Name = "JMC_BananaPeel"
        peel.Shape = Enum.PartType.Cylinder
        peel.Size = Vector3.new(0.3, 2, 2)
        peel.Material = Enum.Material.SmoothPlastic
        peel.Color = Color3.fromRGB(255, 220, 60)
        peel.CanCollide = false
        peel.Anchored = true
        peel.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.5, 0))
                      * CFrame.Angles(0, 0, math.rad(90))
        peel.Parent = workspace

        local used = false
        peel.Touched:Connect(function(other)
            if used then return end
            local char = other:FindFirstAncestorOfClass("Model")
            if not char or char == owner.Character then return end
            local victim = Players:GetPlayerFromCharacter(char)
            if not victim then return end
            local _, vhrp, vhum = getCharData(victim)
            if not vhrp or not vhum or vhum.Health <= 0 then return end

            used = true
            local dir = edgeDirectionFromCenter(vhrp.Position)
            vhrp:ApplyImpulse(dir * cfg.EdgeImpulse * vhrp.AssemblyMass
                + Vector3.new(0, 60, 0) * vhrp.AssemblyMass)
            if _ragdoll then
                _ragdoll:Apply(vhum, cfg.SlipTime or 3)
            end

            ToolFactory.PrankFired:Fire(owner, victim, "BananaPeel")
            Remotes.Event("CameraShake"):FireClient(victim, 5, 0.3)

            peel:Destroy()
        end)

        Debris:AddItem(peel, cfg.TrapLifetime or 30)

        -- Одноразовый Tool — после применения уничтожаем
        tool:Destroy()
    end)

    return tool
end

-- =====================================================================
-- FreezeBeam
-- =====================================================================
local function buildFreezeBeam(): Tool
    local tool = Instance.new("Tool")
    tool.Name = "Ледяной луч"
    tool.RequiresHandle = true
    tool.CanBeDropped = false

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.6, 0.6, 3)
    handle.Material = Enum.Material.Neon
    handle.Color = Config.Pranks.FreezeBeam.BeamColor
    handle.CanCollide = false
    handle.Parent = tool

    local cfg = Config.Pranks.FreezeBeam

    tool.Activated:Connect(function()
        local owner = Players:GetPlayerFromCharacter(tool.Parent)
        if not owner then return end
        local char, hrp = getCharData(owner)
        if not hrp or not char then return end

        -- Направление — куда смотрит игрок
        local dir = hrp.CFrame.LookVector * cfg.Range
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        local result = workspace:Raycast(hrp.Position, dir, params)

        local endPos
        local victim = nil
        if result then
            endPos = result.Position
            local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
            if hitChar then
                victim = Players:GetPlayerFromCharacter(hitChar)
            end
        else
            endPos = hrp.Position + dir
        end

        -- Визуальный луч: тонкий Part между рукой и целью
        local origin = hrp.Position + hrp.CFrame.LookVector * 2
        local midpoint = (origin + endPos) / 2
        local beam = Instance.new("Part")
        beam.Name = "JMC_FreezeBeam"
        beam.Material = Enum.Material.Neon
        beam.Color = cfg.BeamColor
        beam.Anchored = true
        beam.CanCollide = false
        beam.Size = Vector3.new(cfg.BeamWidth, cfg.BeamWidth, (endPos - origin).Magnitude)
        beam.CFrame = CFrame.lookAt(midpoint, endPos)
        beam.Parent = workspace
        Debris:AddItem(beam, 0.25)

        if victim then
            local _, vhrp, vhum = getCharData(victim)
            if vhrp and vhum and vhum.Health > 0 then
                -- Ледяной саркофаг
                local ice = Instance.new("Part")
                ice.Name = "JMC_IceBlock"
                ice.Size = Vector3.new(4, 6, 4)
                ice.Material = Enum.Material.Ice
                ice.Color = Color3.fromRGB(180, 230, 255)
                ice.Transparency = 0.4
                ice.Reflectance = 0.3
                ice.CanCollide = false
                ice.Anchored = true
                ice.CFrame = vhrp.CFrame
                ice.Parent = workspace

                local weld = Instance.new("WeldConstraint")
                weld.Part0 = ice
                weld.Part1 = vhrp
                weld.Parent = ice

                local origWS = vhum.WalkSpeed
                local origJP = vhum.JumpPower
                vhum.WalkSpeed = 0
                vhum.JumpPower = 0

                ToolFactory.PrankFired:Fire(owner, victim, "FreezeBeam")
                Remotes.Event("EventBanner"):FireClient(victim,
                    "ЗАМОРОЖЕН!", cfg.BeamColor)

                task.delay(cfg.FreezeTime or 5, function()
                    if ice.Parent then ice:Destroy() end
                    if vhum.Parent then
                        vhum.WalkSpeed = origWS
                        vhum.JumpPower = origJP
                    end
                end)
            end
        end
    end)

    return tool
end

-- =====================================================================
-- SlimeCannon
-- =====================================================================
local function buildSlimeCannon(): Tool
    local tool = Instance.new("Tool")
    tool.Name = "Слайм-пушка"
    tool.RequiresHandle = true
    tool.CanBeDropped = false

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.8, 1, 3)
    handle.Material = Enum.Material.SmoothPlastic
    handle.Color = Color3.fromRGB(255, 120, 200)
    handle.CanCollide = false
    handle.Parent = tool

    local cfg = Config.Pranks.SlimeCannon
    local lastShot = 0

    tool.Activated:Connect(function()
        local now = os.clock()
        if now - lastShot < (cfg.Cooldown or 0.6) then return end
        lastShot = now

        local owner = Players:GetPlayerFromCharacter(tool.Parent)
        if not owner then return end
        local _, hrp = getCharData(owner)
        if not hrp then return end

        local sessionTime = 0
        if _presence then
            sessionTime = _presence:GetSessionTime(owner)
        end
        local forceScale = 1 + sessionTime / (cfg.SessionScaling or 600)
        local knockback = (cfg.BaseKnockback or 150) * forceScale

        local projectile = Instance.new("Part")
        projectile.Name = "JMC_SlimeBall"
        projectile.Shape = Enum.PartType.Ball
        projectile.Size = Vector3.new(1.5, 1.5, 1.5)
        projectile.Material = Enum.Material.Neon
        projectile.Color = Color3.fromRGB(255, 90, 200)
        projectile.CanCollide = false
        projectile.Massless = true
        projectile.CFrame = CFrame.new(hrp.Position + hrp.CFrame.LookVector * 3)
        projectile.AssemblyLinearVelocity = hrp.CFrame.LookVector * (cfg.ProjectileSpeed or 80)
        projectile.Parent = workspace

        -- Слайм-след
        local attach0 = Instance.new("Attachment"); attach0.Parent = projectile
        local attach1 = Instance.new("Attachment"); attach1.Parent = projectile
        attach1.Position = Vector3.new(0, 0.5, 0)
        local trail = Instance.new("Trail")
        trail.Attachment0 = attach0
        trail.Attachment1 = attach1
        trail.Lifetime = 0.6
        trail.Color = ColorSequence.new(Color3.fromRGB(255, 120, 220))
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.LightEmission = 0.7
        trail.Parent = projectile

        Debris:AddItem(projectile, 4)

        local consumed = false
        projectile.Touched:Connect(function(other)
            if consumed then return end
            local char = other:FindFirstAncestorOfClass("Model")
            if not char or char == owner.Character then return end
            local victim = Players:GetPlayerFromCharacter(char)
            if not victim then return end
            local _, vhrp, vhum = getCharData(victim)
            if not vhrp or not vhum or vhum.Health <= 0 then return end
            consumed = true

            local dir = (vhrp.Position - hrp.Position)
            if dir.Magnitude < 0.1 then
                dir = hrp.CFrame.LookVector
            end
            vhrp:ApplyImpulse(dir.Unit * knockback * vhrp.AssemblyMass
                + Vector3.new(0, knockback * 0.4, 0) * vhrp.AssemblyMass)

            ToolFactory.PrankFired:Fire(owner, victim, "SlimeCannon")
            Remotes.Event("CameraShake"):FireClient(victim, 4, 0.3)
            projectile:Destroy()
        end)
    end)

    return tool
end

-- =====================================================================
-- Public API
-- =====================================================================
local builders = {
    BananaPeel = buildBanana,
    FreezeBeam = buildFreezeBeam,
    SlimeCannon = buildSlimeCannon,
}

function ToolFactory:Init(ragdoll, presence, platform)
    _ragdoll = ragdoll
    _presence = presence
    _platform = platform
end

local function tryRequireSibling(name: string): any?
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, result = pcall(require, mod)
    if ok then return result end
    return nil
end

function ToolFactory:Start()
    if not _ragdoll then _ragdoll = tryRequireSibling("RagdollService") end
    if not _presence then _presence = tryRequireSibling("CirclePresence") end
    if not _platform then _platform = tryRequireSibling("PlatformEngine") end
    print("[JMC][ToolFactory] Готов к выдаче пранк-инструментов")
end

function ToolFactory:Build(itemId: string): Tool?
    local builder = builders[itemId]
    if not builder then
        warn("[JMC][ToolFactory] Неизвестный пранк:", itemId)
        return nil
    end
    return builder()
end

function ToolFactory:Give(player: Player, itemId: string): boolean
    local tool = self:Build(itemId)
    if not tool then return false end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then
        tool:Destroy()
        return false
    end
    tool.Parent = backpack
    return true
end

function ToolFactory:ListItems(): { string }
    local items = {}
    for name in pairs(builders) do
        table.insert(items, name)
    end
    return items
end

return ToolFactory
