--!strict
--[[
	Событие №4: «Пузырьковая атака» (Bubble Trap)
	- По платформе активно летают пузыри.
	- При касании/близком подлёте пузырь захватывает игрока.
	- Игрок должен быстро нажимать Space, чтобы лопнуть пузырь,
	  пока тот тащит его к краю платформы.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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

type BubbleState = {
	bubble: BasePart,
	angle: number,
	baseRadius: number,
	angularSpeed: number,
	radialPhase: number,
	radialSpeed: number,
	heightPhase: number,
	caught: boolean,
}

local trapped: { [Player]: any } = {}
local bubbleStates: { BubbleState } = {}
local mashConn: RBXScriptConnection? = nil
local bubbleConn: RBXScriptConnection? = nil
local bubbleFolder: Folder? = nil

local function removeBubbleState(bubble: BasePart)
	for i = #bubbleStates, 1, -1 do
		if bubbleStates[i].bubble == bubble then
			table.remove(bubbleStates, i)
			return
		end
	end
end

local function releasePlayer(player: Player)
	local data = trapped[player]
	if not data then
		return
	end

	trapped[player] = nil
	if data.cancelTick then
		data.cancelTick()
	end
	if data.bubble and data.bubble.Parent then
		data.bubble:Destroy()
	end

	Remotes.Event("EventBanner"):FireClient(player, "ПУЗЫРЬ ЛОПНУЛ!", Color3.fromRGB(120, 220, 255))
end

local function popBubble(player: Player)
	local data = trapped[player]
	if not data then
		return
	end

	local bubble = data.bubble
	if bubble and bubble.Parent then
		local burstAnchor = Instance.new("Part")
		burstAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
		burstAnchor.CFrame = bubble.CFrame
		burstAnchor.Transparency = 1
		burstAnchor.Anchored = true
		burstAnchor.CanCollide = false
		burstAnchor.Parent = Workspace

		local attach = Instance.new("Attachment")
		attach.Parent = burstAnchor

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

		task.delay(1, function()
			if burstAnchor.Parent then
				burstAnchor:Destroy()
			end
		end)
	end

	releasePlayer(player)
end

local function trapPlayer(player: Player, bubble: BasePart, ctx)
	local char = player.Character
	if not char then
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	removeBubbleState(bubble)
	bubble.Anchored = true

	local attachPlayer = Instance.new("Attachment")
	attachPlayer.Parent = hrp
	local attachBubble = Instance.new("Attachment")
	attachBubble.Parent = bubble

	local align = Instance.new("AlignPosition")
	align.Attachment0 = attachPlayer
	align.Attachment1 = attachBubble
	align.MaxForce = 450000
	align.Responsiveness = 120
	align.RigidityEnabled = false
	align.Parent = hrp

	local center = ctx.platform:GetCenter()
	local radius = ctx.platform:GetRadius()
	local offset = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
	if offset.Magnitude < 0.1 then
		local a = Util.randf(0, math.pi * 2)
		offset = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local driftDir = offset.Unit
	local driftDistance = math.max(radius + Config.Events.BubbleTrap.BubbleSize * 0.8, offset.Magnitude + 8)
	local verticalPhase = Util.randf(0, math.pi * 2)
	local driftConn: RBXScriptConnection? = nil

	driftConn = RunService.Heartbeat:Connect(function(dt)
		if not bubble.Parent or not trapped[player] then
			if driftConn then
				driftConn:Disconnect()
			end
			return
		end

		verticalPhase += dt * 3
		local nextPos = bubble.Position + driftDir * Config.Events.BubbleTrap.DriftSpeed * dt
		local flat = Vector3.new(nextPos.X - center.X, 0, nextPos.Z - center.Z)
		if flat.Magnitude > driftDistance then
			driftDistance = flat.Magnitude
		end

		local clamped = flat.Magnitude > 0.1 and flat.Unit * math.min(flat.Magnitude, driftDistance)
			or driftDir * driftDistance
		bubble.CFrame = CFrame.new(
			center.X + clamped.X,
			ctx.platform:GetSurfaceY() + Config.Events.BubbleTrap.HoverHeight + math.sin(verticalPhase) * 1.2,
			center.Z + clamped.Z
		)
	end)

	trapped[player] = {
		bubble = bubble,
		mashes = 0,
		cancelTick = function()
			if driftConn then
				driftConn:Disconnect()
				driftConn = nil
			end
			if align.Parent then
				align:Destroy()
			end
			if attachPlayer.Parent then
				attachPlayer:Destroy()
			end
			if attachBubble.Parent then
				attachBubble:Destroy()
			end
		end,
	}

	Remotes.Event("EventBanner"):FireClient(player, "ЖМИ SPACE!", Color3.fromRGB(120, 220, 255))
end

local function createBubble(center: Vector3, surfaceY: number): BubbleState
	local cfg = Config.Events.BubbleTrap

	local bubble = Instance.new("Part")
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(cfg.BubbleSize, cfg.BubbleSize, cfg.BubbleSize)
	bubble.Material = Enum.Material.Glass
	bubble.Color = Color3.fromRGB(220, 240, 255)
	bubble.Transparency = 0.45
	bubble.Reflectance = 0.12
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.Anchored = true
	bubble.CastShadow = false
	bubble.Parent = bubbleFolder

	local light = Instance.new("PointLight")
	light.Brightness = 0.7
	light.Range = cfg.BubbleSize * 2.2
	light.Color = bubble.Color
	light.Parent = bubble

	local angle = Util.randf(0, math.pi * 2)
	local baseRadius = Util.randf(8, Config.Platform.Radius * 0.82)
	local heightPhase = Util.randf(0, math.pi * 2)
	bubble.CFrame = CFrame.new(
		center.X + math.cos(angle) * baseRadius,
		surfaceY + cfg.HoverHeight + math.sin(heightPhase) * 1.2,
		center.Z + math.sin(angle) * baseRadius
	)

	return {
		bubble = bubble,
		angle = angle,
		baseRadius = baseRadius,
		angularSpeed = Util.randf(cfg.RoamAngularSpeedMin, cfg.RoamAngularSpeedMax),
		radialPhase = Util.randf(0, math.pi * 2),
		radialSpeed = Util.randf(0.7, 1.6),
		heightPhase = heightPhase,
		caught = false,
	}
end

function E.Start(ctx)
	local cfg = Config.Events.BubbleTrap
	local center = ctx.platform:GetCenter()
	local surfaceY = ctx.platform:GetSurfaceY()

	bubbleFolder = Instance.new("Folder")
	bubbleFolder.Name = "JMC_Bubbles"
	bubbleFolder.Parent = Workspace
	bubbleStates = {}

	mashConn = Remotes.Event("ButtonMash").OnServerEvent:Connect(function(player)
		local data = trapped[player]
		if not data then
			return
		end
		data.mashes += 1
		if data.mashes >= cfg.MashesToBreak then
			popBubble(player)
		end
	end)

	for _ = 1, cfg.BubbleCount do
		table.insert(bubbleStates, createBubble(center, surfaceY))
	end

	bubbleConn = RunService.Heartbeat:Connect(function(dt)
		local playersInside = ctx.presence:GetPlayersInside()

		for i = #bubbleStates, 1, -1 do
			local state = bubbleStates[i]
			local bubble = state.bubble
			if not bubble.Parent then
				table.remove(bubbleStates, i)
				continue
			end

			state.angle += state.angularSpeed * dt
			state.radialPhase += state.radialSpeed * dt
			state.heightPhase += dt * 2.4

			local radius = state.baseRadius + math.sin(state.radialPhase) * cfg.RadialWave
			radius = math.clamp(radius, 6, Config.Platform.Radius * 0.9)

			local pos = Vector3.new(
				center.X + math.cos(state.angle) * radius,
				surfaceY + cfg.HoverHeight + math.sin(state.heightPhase) * 1.3,
				center.Z + math.sin(state.angle) * radius
			)
			bubble.CFrame = CFrame.new(pos)

			for _, player in ipairs(playersInside) do
				if trapped[player] then
					continue
				end
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
					if (hrp.Position - pos).Magnitude <= cfg.CatchRadius then
						state.caught = true
						table.remove(bubbleStates, i)
						trapPlayer(player, bubble, ctx)
						break
					end
				end
			end
		end
	end)
end

function E.Stop(ctx)
	if mashConn then
		mashConn:Disconnect()
		mashConn = nil
	end
	if bubbleConn then
		bubbleConn:Disconnect()
		bubbleConn = nil
	end

	for player, _ in pairs(trapped) do
		releasePlayer(player)
	end

	table.clear(bubbleStates)

	if bubbleFolder and bubbleFolder.Parent then
		bubbleFolder:Destroy()
	end
	bubbleFolder = nil
end

return E
