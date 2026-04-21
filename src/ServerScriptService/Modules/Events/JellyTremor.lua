--!strict
--[[
    Событие №1: «Желейная дрожь» (Jelly Tremor)
    - Платформа «трясётся» каждые 100мс случайным AngularVelocity-толчком.
    - Параллельно клиент делает CameraShake.
    - Трение временно сбрасывается к ещё более скользкому — игроков заносит.
    - Длительность: Config.Events.JellyTremor.Duration.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local E = {}
E.Name = "JellyTremor"
E.DisplayName = "ЖЕЛЕЙНАЯ ДРОЖЬ!"
E.Color = Color3.fromRGB(255, 180, 120)
E.Overlay = "tremor"
E.Duration = Config.Events.JellyTremor.Duration

local AIR_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local function shufflePlayers(players: { Player }, random: Random)
	for i = #players, 2, -1 do
		local j = random:NextInteger(1, i)
		players[i], players[j] = players[j], players[i]
	end
end

local function isJumpProtected(humanoid: Humanoid, hrp: BasePart, surfaceY: number): boolean
	if humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	if AIR_STATES[humanoid:GetState()] then
		return true
	end

	return hrp.Position.Y > surfaceY + (Config.Events.JellyTremor.JumpSafeHeight or 2)
end

function E.Start(ctx)
	local base = ctx.platform:GetBasePart()
	if not base then
		return
	end

	local cfg = Config.Events.JellyTremor
	local originCFrame = base.CFrame
	local originPos = originCFrame.Position
	local surfaceY = ctx.platform:GetSurfaceY()
	local prepTime = cfg.PrepTime or 2
	local endTick = os.clock() + (E.Duration or 10)
	local hazardStart = os.clock() + prepTime

	ctx.platform:SetFriction(cfg.SurfaceFriction or 0.005)

	task.delay(cfg.HintDelay or 0.7, function()
		if os.clock() < endTick then
			Remotes.Event("EventBanner"):FireAllClients(
				cfg.PrepBannerText or "ЖЕЛЕЙНАЯ ДРОЖЬ НАЧНЕТСЯ ЧЕРЕЗ 2 СЕКУНДЫ!",
				E.Color
			)
			Remotes.Event("EventHint"):FireAllClients(
				cfg.HintText
					or "ПЛАТФОРМУ СЕЙЧАС НАЧНЕТ СИЛЬНО ТРЯСТИ. ЧТОБЫ УДЕРЖАТЬСЯ, ПОСТОЯННО ПРЫГАЙ!",
				Color3.fromRGB(255, 245, 140)
			)
		end
	end)

	task.delay(prepTime, function()
		if os.clock() < endTick then
			Remotes.Event("MusicCue"):FireAllClients("intense", math.max((E.Duration or 12) - prepTime, 0.1))
		end
	end)

	-- Визуальная дрожь платформы + сильные хаотичные броски по стоящим на ней игрокам.
	task.spawn(function()
		while os.clock() < endTick do
			if os.clock() < hazardStart then
				task.wait(cfg.TickInterval)
				continue
			end

			local quakeAngle = ctx.random:NextNumber() * math.pi * 2
			local quakeDir = Vector3.new(math.cos(quakeAngle), 0, math.sin(quakeAngle))
			local sideDir = Vector3.new(-quakeDir.Z, 0, quakeDir.X)
			local dx = quakeDir.X * ctx.random:NextNumber(0.45, cfg.PlatformShift or 1.35)
			local dz = quakeDir.Z * ctx.random:NextNumber(0.45, cfg.PlatformShift or 1.35)
			local tilt = math.rad(cfg.TiltAngleDeg or 8)
			local rotX = quakeDir.Z * ctx.random:NextNumber(0.35, 1) * tilt
			local rotZ = -quakeDir.X * ctx.random:NextNumber(0.35, 1) * tilt
			base.CFrame = originCFrame * CFrame.new(dx, 0, dz) * CFrame.Angles(rotX, 0, rotZ)

			local victims = ctx.presence:GetPlayersInside()
			shufflePlayers(victims, ctx.random)

			for _, player in ipairs(victims) do
				local char = player.Character
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if humanoid and hrp and hrp:IsA("BasePart") and not isJumpProtected(humanoid, hrp, surfaceY) then
					local offset = Vector3.new(hrp.Position.X - originPos.X, 0, hrp.Position.Z - originPos.Z)
					local edgeBias = offset.Magnitude > 0.5 and offset.Unit or quakeDir
					local chaos = quakeDir * ctx.random:NextNumber(0.8, 1.35)
						+ sideDir * ctx.random:NextNumber(-1.1, 1.1)
						+ edgeBias * ctx.random:NextNumber(0.3, 0.9)
					local pushDir = chaos.Magnitude > 0.05 and chaos.Unit or quakeDir
					local impulse = pushDir
						* ctx.random:NextNumber(cfg.HorizontalImpulseMin or 90, cfg.HorizontalImpulseMax or 145)
					local targetVelocity = pushDir
						* ctx.random:NextNumber(cfg.HorizontalVelocityMin or 42, cfg.HorizontalVelocityMax or 68)

					hrp:ApplyImpulse(impulse * hrp.AssemblyMass)
					hrp.AssemblyLinearVelocity =
						Vector3.new(targetVelocity.X, hrp.AssemblyLinearVelocity.Y, targetVelocity.Z)
				end
			end

			Remotes.Event("CameraShake"):FireAllClients(cfg.CameraShakeMag or 1.25, cfg.TickInterval * 1.4)
			Remotes.Event("HapticPulse"):FireAllClients(0.55, cfg.TickInterval)

			task.wait(cfg.TickInterval)
		end

		Remotes.Event("EventHint"):FireAllClients(nil, nil)
		base.CFrame = originCFrame
	end)
end

function E.Stop(ctx)
	Remotes.Event("EventHint"):FireAllClients(nil, nil)
	ctx.platform:ResetFriction()
end

return E
