--!strict
--[[
    Событие №4: «Пузырьковая атака» (Bubble Trap)
    - По платформе дрейфуют прозрачные сферы.
    - При касании игрока пузырь фиксирует его внутри (Weld + VectorForce к краю).
    - Игрок должен нажать пробел Config.Events.BubbleTrap.MashesToBreak раз,
      чтобы лопнуть пузырь до того, как он вынесет его за пределы.
    - Счётчик нажатий приходит через RemoteEvent "ButtonMash" (клиент → сервер).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local E = {}
E.Name = "BubbleTrap"
E.DisplayName = "ПУЗЫРЬКОВАЯ АТАКА!"
E.Color = Color3.fromRGB(180, 220, 255)
E.Duration = Config.Events.BubbleTrap.Duration

-- state: player -> { bubble, mashes, cancel }
local trapped: { [Player]: any } = {}

local mashConn: RBXScriptConnection? = nil

local function releasePlayer(player: Player)
    local data = trapped[player]
    if not data then return end
    trapped[player] = nil
    if data.bubble and data.bubble.Parent then data.bubble:Destroy() end
    if data.cancelTick then data.cancelTick() end
    Remotes.Event("EventBanner"):FireClient(player, "ПУЗЫРЬ ЛОПНУЛ!", Color3.fromRGB(120, 220, 255))
end

local function popBubble(player: Player)
    local data = trapped[player]
    if not data then return end
    -- Эффект лопания
    if data.bubble and data.bubble.Parent then
        local attach = Instance.new("Attachment", data.bubble)
        local pe = Instance.new("ParticleEmitter")
        pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        pe.Rate = 0
        pe.Lifetime = NumberRange.new(0.6, 1)
        pe.Speed = NumberRange.new(10, 20)
        pe.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
        pe.Size = NumberSequence.new(0.2, 0.8)
        pe.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        })
        pe.SpreadAngle = Vector2.new(180, 180)
        pe.Parent = attach
        pe:Emit(30)
    end
    releasePlayer(player)
end

local function trapPlayer(player: Player, bubble: BasePart, ctx)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    -- Weld-ем игрока в пузырь (через AlignPosition — физически корректнее)
    local attachPlayer = Instance.new("Attachment", hrp)
    local attachBubble = Instance.new("Attachment", bubble)
    local align = Instance.new("AlignPosition")
    align.Attachment0 = attachPlayer
    align.Attachment1 = attachBubble
    align.MaxForce = 200000
    align.Responsiveness = 200
    align.RigidityEnabled = false
    align.Parent = hrp

    -- Дрейф пузыря к краю платформы
    local center = ctx.platform:GetCenter()
    local offset = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
    if offset.Magnitude < 0.1 then
        local a = Util.randf(0, math.pi * 2)
        offset = Vector3.new(math.cos(a), 0, math.sin(a))
    end
    local driftDir = offset.Unit

    local driftConn
    driftConn = RunService.Heartbeat:Connect(function(dt)
        if not bubble.Parent or not trapped[player] then
            driftConn:Disconnect()
            return
        end
        bubble.AssemblyLinearVelocity = driftDir * Config.Events.BubbleTrap.DriftSpeed
        + Vector3.new(0, 2, 0) -- чуть приподнимается
    end)

    trapped[player] = {
        bubble = bubble,
        mashes = 0,
        driftConn = driftConn,
        cancelTick = function()
            if driftConn then driftConn:Disconnect() end
            if align.Parent then align:Destroy() end
            if attachPlayer.Parent then attachPlayer:Destroy() end
            if attachBubble.Parent then attachBubble:Destroy() end
        end,
    }

    -- Клиенту шлём UI «Жми SPACE!»
    Remotes.Event("EventBanner"):FireClient(player, "ЖМИ SPACE!", Color3.fromRGB(120, 220, 255))
end

function E.Start(ctx)
    local folder = Instance.new("Folder")
    folder.Name = "JMC_Bubbles"
    folder.Parent = Workspace
    Debris:AddItem(folder, (E.Duration or 25) + 4)

    -- Слушатель нажатий пробела
    mashConn = Remotes.Event("ButtonMash").OnServerEvent:Connect(function(player)
        local data = trapped[player]
        if not data then return end
        data.mashes = data.mashes + 1
        if data.mashes >= Config.Events.BubbleTrap.MashesToBreak then
            popBubble(player)
        end
    end)

    -- Спавним пузыри
    local center = ctx.platform:GetCenter()
    local surfaceY = ctx.platform:GetSurfaceY()
    for i = 1, Config.Events.BubbleTrap.BubbleCount do
        task.spawn(function()
            task.wait(Util.randf(0, 2.5))
            local bubble = Instance.new("Part")
            bubble.Shape = Enum.PartType.Ball
            bubble.Size = Vector3.new(
                Config.Events.BubbleTrap.BubbleSize,
                Config.Events.BubbleTrap.BubbleSize,
                Config.Events.BubbleTrap.BubbleSize
            )
            bubble.Material = Enum.Material.Glass
            bubble.Color = Color3.fromRGB(220, 240, 255)
            bubble.Transparency = 0.5
            bubble.Reflectance = 0.2
            bubble.CanCollide = false
            bubble.Massless = true
            bubble.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0, 0.9, 1, 1)

            local angle = Util.randf(0, math.pi * 2)
            local r = Util.randf(5, Config.Platform.Radius * 0.4)
            bubble.Position = Vector3.new(
                center.X + math.cos(angle) * r,
                surfaceY + Config.Events.BubbleTrap.BubbleSize / 2 + 1,
                center.Z + math.sin(angle) * r
            )
            bubble.Parent = folder

            local consumed = false
            bubble.Touched:Connect(function(other)
                if consumed then return end
                local char = other:FindFirstAncestorOfClass("Model")
                if not char then return end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if not humanoid or humanoid.Health <= 0 then return end
                local player = Players:GetPlayerFromCharacter(char)
                if not player or trapped[player] then return end
                consumed = true
                trapPlayer(player, bubble, ctx)
            end)

            -- Самоуничтожение через 20 сек если никого не зацепит
            Debris:AddItem(bubble, 20)
        end)
    end

    -- Подождём длительность
    task.wait(E.Duration or 25)
end

function E.Stop(ctx)
    if mashConn then mashConn:Disconnect(); mashConn = nil end
    for player, _ in pairs(trapped) do
        releasePlayer(player)
    end
end

return E
