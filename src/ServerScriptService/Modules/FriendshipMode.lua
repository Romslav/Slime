--!strict
--[[
    FriendshipMode.lua
    Если Config.Social.FriendshipMinPlayers+ игроков танцуют (выполняют эмоцию)
    в круге одновременно — включается режим Дружбы:
      - всем в круге +Config.Social.FriendshipBonusRate монет/сек;
      - вокруг спавнятся Bonus-шарики (Part с .Touched → +coins).
    Определяем «танец» через активную AnimationTrack на Animator, имя которого
    содержит "dance"/"emote" (Roblox defaults), либо через пометку клиента.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Signal = require(Shared:WaitForChild("Signal"))

local FriendshipMode = {}
FriendshipMode.Activated = Signal.new()   -- (count)
FriendshipMode.Deactivated = Signal.new()

local _presence = nil
local _reward = nil
local _platform = nil
local _active = false

-- character -> true, если сейчас играет «dance»/«emote» анимация
local dancing: { [Model]: boolean } = {}

local function isDanceName(name: string): boolean
    local low = string.lower(name or "")
    return string.find(low, "dance") ~= nil
        or string.find(low, "emote") ~= nil
        or string.find(low, "wave") ~= nil
        or string.find(low, "cheer") ~= nil
end

local function trackCharacter(char: Model)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum or not hum:IsA("Humanoid") then return end
    local animator = hum:WaitForChild("Animator", 5)
    if not animator or not animator:IsA("Animator") then return end

    animator.AnimationPlayed:Connect(function(track: AnimationTrack)
        local animName = track.Animation and track.Animation.Name or track.Name
        if isDanceName(animName) then
            dancing[char] = true
            track.Stopped:Connect(function()
                if dancing[char] then
                    dancing[char] = nil
                end
            end)
        end
    end)
end

local function countDancersInside(): number
    if not _presence then return 0 end
    local n = 0
    for _, p in ipairs(_presence:GetPlayersInside()) do
        local char = p.Character
        if char and dancing[char] then
            n = n + 1
        end
    end
    return n
end

local function spawnBonusPellet()
    if not _platform then return end
    local center = _platform:GetCenter()
    local surfaceY = _platform:GetSurfaceY()
    local angle = math.random() * math.pi * 2
    local r = Util.randf(4, Config.Platform.Radius * 0.7)
    local pellet = Instance.new("Part")
    pellet.Name = "JMC_FriendshipCoin"
    pellet.Shape = Enum.PartType.Ball
    pellet.Size = Vector3.new(1.6, 1.6, 1.6)
    pellet.Material = Enum.Material.Neon
    pellet.Color = Color3.fromRGB(255, 220, 80)
    pellet.CanCollide = false
    pellet.Anchored = true
    pellet.Position = Vector3.new(
        center.X + math.cos(angle) * r,
        surfaceY + 4,
        center.Z + math.sin(angle) * r
    )
    pellet.Parent = workspace

    local bb = Instance.new("BillboardGui")
    bb.Adornee = pellet
    bb.Size = UDim2.fromOffset(40, 40)
    bb.StudsOffset = Vector3.new(0, 1.5, 0)
    bb.AlwaysOnTop = true
    bb.Parent = pellet
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.Text = "💰"
    lbl.Font = Enum.Font.FredokaOne
    lbl.TextScaled = true
    lbl.Parent = bb

    local used = false
    pellet.Touched:Connect(function(other)
        if used then return end
        local char = other:FindFirstAncestorOfClass("Model")
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        used = true
        if _reward and _reward.IncrementCoins then
            _reward:IncrementCoins(player, 10)
        end
        pellet:Destroy()
    end)

    -- Плавающая анимация через bobbing
    task.spawn(function()
        local origY = pellet.Position.Y
        local start = os.clock()
        while pellet.Parent do
            local dy = math.sin((os.clock() - start) * 3) * 0.4
            pellet.Position = Vector3.new(pellet.Position.X, origY + dy, pellet.Position.Z)
            task.wait(0.05)
        end
    end)

    Debris:AddItem(pellet, 20)
end

function FriendshipMode:Init(presence, reward, platform)
    _presence = presence
    _reward = reward
    _platform = platform
end

local function tryRequireSibling(name: string): any?
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, result = pcall(require, mod)
    if ok then return result end
    return nil
end

function FriendshipMode:Start()
    if not _presence then _presence = tryRequireSibling("CirclePresence") end
    if not _reward then _reward = tryRequireSibling("RewardService") end
    if not _platform then _platform = tryRequireSibling("PlatformEngine") end

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(trackCharacter)
        if player.Character then
            task.spawn(trackCharacter, player.Character)
        end
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then task.spawn(trackCharacter, p.Character) end
        p.CharacterAdded:Connect(trackCharacter)
    end

    task.spawn(function()
        while true do
            local dancers = countDancersInside()
            local need = Config.Social.FriendshipMinPlayers or 3
            if dancers >= need and not _active then
                _active = true
                FriendshipMode.Activated:Fire(dancers)
            elseif dancers < need and _active then
                _active = false
                FriendshipMode.Deactivated:Fire()
            end

            if _active then
                -- бонусные монеты каждому в круге
                if _reward and _reward.IncrementCoins and _presence then
                    local bonusRate = Config.Social.FriendshipBonusRate or 2
                    for _, p in ipairs(_presence:GetPlayersInside()) do
                        _reward:IncrementCoins(p, bonusRate)
                    end
                end
                -- шанс спавна шарика
                if math.random() < 0.4 then
                    spawnBonusPellet()
                end
            end
            task.wait(1)
        end
    end)

    print("[JMC][Friendship] Режим дружбы следит за танцами")
end

function FriendshipMode:IsActive(): boolean
    return _active
end

return FriendshipMode
