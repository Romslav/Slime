--!strict
--[[
    Событие №9: «Гигантская ложка» (Giant Spoon)
    - По радиусу платформы вращается невидимый «черпак» (Part с CanCollide=true).
    - При касании игрока — RagdollService.Apply + ApplyImpulse по касательной.
    - Чтобы визуально показать угрозу — над ложкой BillboardGui «🥄» и Beam-след.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "GiantSpoon"
E.DisplayName = "ЛОЖКА СУДЬБЫ!"
E.Color = Color3.fromRGB(220, 220, 240)
E.Duration = Config.Events.GiantSpoon.Duration

function E.Start(ctx)
    local center = ctx.platform:GetCenter()
    local surfaceY = ctx.platform:GetSurfaceY()
    local radius = Config.Platform.Radius * (Config.Events.GiantSpoon.RadiusScale or 0.75)
    local angularSpeed = Config.Events.GiantSpoon.RotSpeed or 1.3 -- рад/сек
    local spoonLen = Config.Events.GiantSpoon.SpoonLength or 35
    local spoonHeight = Config.Events.GiantSpoon.Height or 6
    local spoonThick = Config.Events.GiantSpoon.Thickness or 2

    -- Невидимая «голова ложки»
    local spoon = Instance.new("Part")
    spoon.Name = "JMC_GiantSpoon"
    spoon.Size = Vector3.new(spoonLen, spoonHeight, spoonThick)
    spoon.Anchored = true
    spoon.CanCollide = false -- hitbox через .Touched; если true — оттолкнёт физически
    spoon.Transparency = 0.75
    spoon.Material = Enum.Material.Neon
    spoon.Color = Color3.fromRGB(240, 240, 255)
    spoon.Parent = Workspace

    -- Визуальный след
    local attach0 = Instance.new("Attachment"); attach0.Parent = spoon
    attach0.Position = Vector3.new(-spoonLen / 2, 0, 0)
    local attach1 = Instance.new("Attachment"); attach1.Parent = spoon
    attach1.Position = Vector3.new(spoonLen / 2, 0, 0)

    local trail = Instance.new("Trail")
    trail.Attachment0 = attach0
    trail.Attachment1 = attach1
    trail.Lifetime = 0.5
    trail.MinLength = 0
    trail.LightEmission = 0.6
    trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 240))
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Parent = spoon

    -- Иконка
    local bb = Instance.new("BillboardGui")
    bb.Adornee = spoon
    bb.Size = UDim2.fromOffset(80, 80)
    bb.StudsOffset = Vector3.new(0, 4, 0)
    bb.AlwaysOnTop = true
    bb.Parent = spoon
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.Text = "🥄"
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextScaled = true
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Parent = bb

    local angle = 0
    local endTick = os.clock() + (E.Duration or 18)
    local hitCooldown: { [Player]: number } = {}

    local conn: RBXScriptConnection? = nil
    conn = RunService.Heartbeat:Connect(function(dt)
        if os.clock() >= endTick or not spoon.Parent then
            if conn then conn:Disconnect() end
            if spoon.Parent then spoon:Destroy() end
            return
        end

        angle = angle + angularSpeed * dt
        local px = center.X + math.cos(angle) * radius
        local pz = center.Z + math.sin(angle) * radius
        local py = surfaceY + spoonHeight / 2 + 0.5

        -- Ложка смотрит по касательной
        local lookAt = Vector3.new(-math.sin(angle), 0, math.cos(angle))
        spoon.CFrame = CFrame.lookAt(Vector3.new(px, py, pz), Vector3.new(px, py, pz) + lookAt)

        -- Ручная проверка «Touched» через расстояние (более предсказуемо, чем .Touched на Anchored)
        for _, p in ipairs(ctx.presence:GetPlayersInside()) do
            if hitCooldown[p] and os.clock() < hitCooldown[p] then continue end
            local char = p.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp or not hrp:IsA("BasePart") then continue end

            -- Переводим позицию игрока в локальные координаты ложки
            local local_ = spoon.CFrame:PointToObjectSpace(hrp.Position)
            if math.abs(local_.X) < spoonLen / 2
                and math.abs(local_.Y) < spoonHeight / 2 + 2
                and math.abs(local_.Z) < spoonThick / 2 + 2 then
                -- УДАР!
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and ctx.ragdoll then
                    ctx.ragdoll:Apply(hum, Config.Events.GiantSpoon.RagdollTime or 2)
                end
                -- Бросок по направлению движения ложки
                local force = lookAt * (Config.Events.GiantSpoon.HitForce or 220)
                            + Vector3.new(0, 100, 0)
                hrp:ApplyImpulse(force * hrp.AssemblyMass)
                hitCooldown[p] = os.clock() + 1.2

                Remotes.Event("HapticPulse"):FireClient(p, 0.8, 0.4)
                Remotes.Event("CameraShake"):FireClient(p, 6, 0.4)
            end
        end
    end)

    task.wait(E.Duration or 18)
    if conn then conn:Disconnect() end
    if spoon.Parent then spoon:Destroy() end
end

function E.Stop(ctx)
    local old = Workspace:FindFirstChild("JMC_GiantSpoon")
    if old then old:Destroy() end
end

return E
