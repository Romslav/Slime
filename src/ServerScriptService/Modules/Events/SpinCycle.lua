--!strict
--[[
	Событие №7: «Центрифуга» (Spin Cycle)
	- В начале есть короткое окно, чтобы нажать E и зарыться в платформу.
	- Пока игрок зарыт, он обязан держать Space; если отпустить дольше чем на
	  1.5 сек, его вырывает наружу.
	- Незащищённых игроков всё сильнее уносит к краю, а потом катапультирует
	  далеко за карту с вращением.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "SpinCycle"
E.DisplayName = "ЦЕНТРИФУГА!"
E.Color = Color3.fromRGB(180, 140, 255)
E.Overlay = "spin"
E.Duration = Config.Events.SpinCycle.Duration

type PlayerState = {
	buried: boolean,
	burying: boolean,
	launched: boolean,
	failed: boolean,
	holding: boolean,
	exposure: number,
	buriedCFrame: CFrame?,
	holdReleasedAt: number?,
	autoRotate: boolean?,
	seed: number,
}

local function getCharacterParts(char: Model): (Humanoid?, BasePart?)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return humanoid, nil
	end
	return humanoid, hrp
end

local function setCharacterAnchored(char: Model, anchored: boolean)
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = anchored
		end
	end
end

local function getYawCFrame(position: Vector3, lookVector: Vector3): CFrame
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flatLook.Unit)
end

local function getState(states: { [Player]: PlayerState }, player: Player, random: Random): PlayerState
	local state = states[player]
	if state then
		return state
	end

	state = {
		buried = false,
		burying = false,
		launched = false,
		failed = false,
		holding = false,
		exposure = 0,
		buriedCFrame = nil,
		holdReleasedAt = nil,
		autoRotate = nil,
		seed = random:NextNumber(-1000, 1000),
	}
	states[player] = state
	return state
end

local function releaseBurial(state: PlayerState, char: Model, humanoid: Humanoid?, hrp: BasePart?, surfaceY: number)
	if humanoid and state.autoRotate ~= nil then
		humanoid.AutoRotate = state.autoRotate
	end

	if char.Parent then
		setCharacterAnchored(char, false)
	end

	if hrp then
		local emergePos = Vector3.new(hrp.Position.X, surfaceY + 1.8, hrp.Position.Z)
		char:PivotTo(getYawCFrame(emergePos, hrp.CFrame.LookVector))
	end

	state.buried = false
	state.burying = false
	state.buriedCFrame = nil
	state.holdReleasedAt = nil
end

local function launchPlayer(
	ctx: any,
	player: Player,
	state: PlayerState,
	char: Model,
	humanoid: Humanoid?,
	hrp: BasePart,
	center: Vector3
)
	if state.launched then
		return
	end

	state.launched = true
	state.buried = false
	state.burying = false
	state.buriedCFrame = nil

	if humanoid and state.autoRotate ~= nil then
		humanoid.AutoRotate = state.autoRotate
	end
	setCharacterAnchored(char, false)

	local cfg = Config.Events.SpinCycle
	local rel = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
	local outward = rel.Magnitude > 0.1 and rel.Unit or Vector3.new(0, 0, 1)
	local tangent = Vector3.new(-outward.Z, 0, outward.X)
	local launchVelocity = outward * cfg.LaunchOut
		+ tangent * ctx.random:NextNumber(45, 95)
		+ Vector3.new(0, cfg.LaunchUp, 0)

	if humanoid and ctx.ragdoll then
		ctx.ragdoll:Apply(humanoid, cfg.LaunchRagdollTime or 2.4, launchVelocity)
	else
		hrp:ApplyImpulse(launchVelocity * hrp.AssemblyMass)
	end

	hrp.AssemblyLinearVelocity = launchVelocity
	hrp.AssemblyAngularVelocity = Vector3.new(
		ctx.random:NextNumber(-cfg.LaunchSpin, cfg.LaunchSpin),
		ctx.random:NextNumber(-cfg.LaunchSpin, cfg.LaunchSpin),
		ctx.random:NextNumber(-cfg.LaunchSpin, cfg.LaunchSpin)
	)

	Remotes.Event("CameraShake"):FireClient(player, 8, 0.45)
	Remotes.Event("HapticPulse"):FireClient(player, 0.9, 0.35)
end

local function beginBurial(ctx: any, player: Player, state: PlayerState, startTick: number, surfaceY: number)
	if os.clock() > startTick + (Config.Events.SpinCycle.DigWindow or 3) then
		return
	end
	if state.launched or state.buried or state.burying then
		return
	end
	if not ctx.presence:IsInside(player) then
		return
	end

	local char = player.Character
	if not char then
		return
	end

	local humanoid, hrp = getCharacterParts(char)
	if not humanoid or not hrp then
		return
	end

	state.burying = true
	state.autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	setCharacterAnchored(char, true)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local startCF = hrp.CFrame
	local targetPos = Vector3.new(hrp.Position.X, surfaceY - Config.Events.SpinCycle.BuryDepth, hrp.Position.Z)
	local targetCF = getYawCFrame(targetPos, startCF.LookVector)
	local steps = 7
	local buryDuration = Config.Events.SpinCycle.BuryDuration or 0.45

	task.spawn(function()
		for i = 1, steps do
			if not char.Parent or state.launched then
				return
			end
			local alpha = i / steps
			local pos = startCF.Position:Lerp(targetCF.Position, alpha)
			char:PivotTo(getYawCFrame(pos, startCF.LookVector))
			task.wait(buryDuration / steps)
		end

		if not char.Parent or state.launched then
			return
		end

		state.burying = false
		state.buried = true
		state.failed = false
		state.buriedCFrame = targetCF
		state.holdReleasedAt = state.holding and nil or os.clock()

		Remotes.Event("EventBanner")
			:FireClient(player, "ЗАРЫЛСЯ! ДЕРЖИ SPACE!", Color3.fromRGB(180, 255, 170))
	end)
end

function E.Start(ctx)
	local base = ctx.platform:GetBasePart()
	if not base then
		return
	end

	local cfg = Config.Events.SpinCycle
	local center = ctx.platform:GetCenter()
	local radius = ctx.platform:GetRadius()
	local surfaceY = ctx.platform:GetSurfaceY()
	local origCFrame = base.CFrame
	local startTick = os.clock()
	local endTick = startTick + (E.Duration or 18)
	local prepTime = cfg.PrepTime or 3
	local hazardStart = startTick + prepTime
	local accumAngle = 0
	local states: { [Player]: PlayerState } = {}
	local finished = false
	local conn: RBXScriptConnection? = nil

	Remotes.Event("EventBanner")
		:FireAllClients(
			cfg.PrepBannerText or "ЦЕНТРИФУГА НАЧНЕТСЯ ЧЕРЕЗ 3 СЕКУНДЫ!",
			E.Color
		)

	task.delay(cfg.HintDelayE or 0.35, function()
		if os.clock() < endTick then
			Remotes.Event("EventHint"):FireAllClients(
				cfg.HintTextE or "НАЖМИ E: ЗАРОЙСЯ В ТЕЛО МОНСТРА",
				Color3.fromRGB(255, 240, 140)
			)
		end
	end)

	task.delay(prepTime, function()
		if os.clock() < endTick then
			local spinDuration = math.max((E.Duration or 18) - prepTime, 0.1)
			Remotes.Event("OverlayFX"):FireAllClients("spin", spinDuration)
			Remotes.Event("MusicCue"):FireAllClients("intense", spinDuration)
			Remotes.Event("EventHint"):FireAllClients(
				cfg.HintTextSpace or "ДЕРЖИ SPACE, ЧТОБЫ УДЕРЖАТЬСЯ!",
				Color3.fromRGB(255, 210, 150)
			)
		end
	end)

	local inputConn = Remotes.Event("SpinCycleInput").OnServerEvent:Connect(function(player: Player, action: string)
		local state = getState(states, player, ctx.random)
		if action == "dig" then
			beginBurial(ctx, player, state, startTick, surfaceY)
		elseif action == "hold_start" then
			state.holding = true
			state.holdReleasedAt = nil
		elseif action == "hold_end" then
			state.holding = false
			if state.buried then
				state.holdReleasedAt = os.clock()
			end
		end
	end)

	local function cleanup()
		if finished then
			return
		end
		finished = true

		if conn then
			conn:Disconnect()
			conn = nil
		end
		inputConn:Disconnect()
		Remotes.Event("EventHint"):FireAllClients(nil, nil)
		base.CFrame = origCFrame

		for player, state in pairs(states) do
			local char = player.Character
			if not char then
				continue
			end

			local humanoid, hrp = getCharacterParts(char)
			if state.buried or state.burying then
				releaseBurial(state, char, humanoid, hrp, surfaceY)
			elseif humanoid and state.autoRotate ~= nil then
				humanoid.AutoRotate = state.autoRotate
			end
		end
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if now >= endTick then
			cleanup()
			return
		end

		if now < hazardStart then
			return
		end

		local spinAlpha = math.clamp((now - hazardStart) / math.max(endTick - hazardStart, 0.1), 0.2, 1)
		accumAngle += (cfg.AngularVel or 3.6) * spinAlpha * dt
		base.CFrame = origCFrame * CFrame.Angles(0, accumAngle, 0)

		Remotes.Event("CameraShake"):FireAllClients(3 + spinAlpha * 1.5, 0.2)

		for player, state in pairs(states) do
			local char = player.Character
			if char then
				local humanoid, hrp = getCharacterParts(char)
				if hrp and state.buriedCFrame and (state.buried or state.burying) then
					char:PivotTo(state.buriedCFrame)
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end

				if state.buried and humanoid and hrp and not state.holding then
					local releasedAt = state.holdReleasedAt or now
					if now - releasedAt >= (cfg.HoldGrace or 1.5) then
						releaseBurial(state, char, humanoid, hrp, surfaceY)
						state.failed = true
						state.exposure = math.max(state.exposure, 1.2)
						Remotes.Event("EventBanner"):FireClient(
							player,
							"SPACE СОРВАЛО! ТЕПЕРЬ ТЕБЯ УНЕСЕТ!",
							Color3.fromRGB(255, 170, 120)
						)
					end
				end
			end
		end

		for _, player in ipairs(ctx.presence:GetPlayersInside()) do
			local state = getState(states, player, ctx.random)
			if state.launched or state.buried or state.burying then
				continue
			end

			local char = player.Character
			if not char then
				continue
			end

			local humanoid, hrp = getCharacterParts(char)
			if not humanoid or not hrp then
				continue
			end

			local rel = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
			local dist = rel.Magnitude
			if dist < 0.05 then
				continue
			end

			state.exposure += dt

			local radial = rel.Unit
			local tangent = Vector3.new(-radial.Z, 0, radial.X)
			local distAlpha = math.clamp(dist / radius, 0, 1)
			local chaosPhase = now * 5.5 + state.seed
			local chaosDir = (tangent * math.sin(chaosPhase) + radial * math.cos(chaosPhase * 1.3)).Unit
			local forceScale = 1 + math.min(state.exposure * 0.65, 2.2)
			local outwardForce = radial * (cfg.RadialPull or 13) * (0.35 + distAlpha * 1.8)
			local tangentForce = tangent * (cfg.TangentialPull or 18) * (0.45 + distAlpha * 1.1)
			local chaosForce = chaosDir * (cfg.ChaosPull or 9) * (0.4 + distAlpha)
			local total = (outwardForce + tangentForce + chaosForce) * forceScale

			hrp:ApplyImpulse(total * hrp.AssemblyMass * dt)

			local targetHorizontal = (radial * (24 + distAlpha * 38 * forceScale))
				+ (tangent * (18 + distAlpha * 30 * forceScale))
				+ (chaosDir * (8 + distAlpha * 16))
			hrp.AssemblyLinearVelocity =
				Vector3.new(targetHorizontal.X, hrp.AssemblyLinearVelocity.Y, targetHorizontal.Z)

			if distAlpha >= (cfg.EdgeThreshold or 0.86) then
				launchPlayer(ctx, player, state, char, humanoid, hrp, center)
			end
		end
	end)
end

function E.Stop(ctx)
	local base = ctx.platform:GetBasePart()
	if base then
		-- Базовая очистка выполняется в Start.
	end
end

return E
