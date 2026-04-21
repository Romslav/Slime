--!strict
--[[
    Config.lua
    Единый источник тюнинг-значений. Весь баланс, цены, интервалы — здесь.
    Правим баланс без правок логики.
--]]

local Config = {}

-- =====================================================================
-- Мир и окружение
-- =====================================================================
Config.World = {
	-- Неоновый лес
	ForestTreeCount = 90, -- сколько деревьев расставить вокруг
	ForestRadiusMin = 80, -- минимальное расстояние от центра
	ForestRadiusMax = 260, -- максимальное расстояние
	TreeTrunkHeightMin = 8,
	TreeTrunkHeightMax = 22,
	TreeTrunkRadiusMin = 0.8,
	TreeTrunkRadiusMax = 2.2,
	TreeCanopyRadiusMin = 4,
	TreeCanopyRadiusMax = 10,
	TreeCanopyHueRange = { 0.25, 0.55 }, -- салатовый .. розовый в HSV

	-- Атмосфера / туман: дневной мягкий розово-фиолетовый градиент
	AtmosphereDensity = 0.22,
	AtmosphereColor = Color3.fromRGB(255, 216, 235),
	AtmosphereDecay = Color3.fromRGB(196, 170, 235),
	AtmosphereGlare = 0.12,
	AtmosphereHaze = 1.15,

	-- Материалы деревьев (v3.0)
	TreeTrunkMaterial = Enum.Material.SmoothPlastic,
	TreeCanopyMaterial = Enum.Material.Glass,

	-- Пыльца вокруг монстра (v3.0)
	Pollen = {
		Rate = 40,
		Lifetime = NumberRange.new(6, 12),
		SpeedMin = 0.4,
		SpeedMax = 1.6,
		LightEmission = 0.25,
	},

	-- Sky (null = использовать процедурное небо; для текстур — Asset IDs)
	SkyboxAssetIds = {
		Up = 0,
		Down = 0,
		Lf = 0,
		Rt = 0,
		Ft = 0,
		Bk = 0,
	},

	-- Цветовая коррекция
	ColorCorrection = {
		Saturation = 0.08,
		Contrast = 0.04,
		Brightness = 0.04,
		TintColor = Color3.fromRGB(255, 236, 248),
	},

	-- Bloom
	Bloom = {
		Intensity = 0.3,
		Size = 18,
		Threshold = 0.97,
	},

	-- Глобальная гравитация (для события Trampoline временно меняется)
	DefaultGravity = 196.2,
}

-- =====================================================================
-- Платформа (Wobble Engine)
-- =====================================================================
Config.Platform = {
	-- v3.0: платформа = внешняя оболочка монстра (OuterShell)
	Radius = 70, -- радиус круга (studs), диаметр 140
	Height = 10, -- толщина «желе»
	Color = Color3.fromRGB(186, 104, 255),
	Material = Enum.Material.Glass,
	Transparency = 0.55,
	Reflectance = 0.08,

	-- Pulse-дыхание
	PulseDuration = 3.0, -- сек на половину цикла
	PulseScale = 0.025, -- ±2.5%

	-- Физика поверхности (v3.0 — «вязкая нестабильность»)
	Friction = 0.02, -- почти нулевое, как на льду → «эффект дрифта»
	Elasticity = 0.95, -- платформа очень прыгучая
	Density = 0.5,
	FrictionWeight = 100, -- игнорирует трение обуви игрока
	ElasticityWeight = 100, -- и упругость платформы доминирует над материалом обуви

	-- Сегменты для «Tasty Bite»
	SegmentCount = 8,
}

-- =====================================================================
-- Монстр (The Beast) — трёхслойное тело, глаза, щупальца (v3.0)
-- =====================================================================
Config.Monster = {
	-- OuterShell теперь = Config.Platform (см. выше). Секция ниже оставлена
	-- для обратной совместимости и возможной визуальной тонкой настройки.
	InnerFlesh = {
		DiameterOffset = 8, -- diameter = Platform.Radius*2 - offset
		HeightOffset = 2, -- height   = Platform.Height - offset
		Transparency = 0.85,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(138, 43, 226),
	},
	Core = {
		-- Размер чуть меньше Platform.Height (10), стоит в центре платформы
		Size = 9,
		VerticalOffset = 0,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 255),
		PulseMin = 0.38, -- заметно, но уже не выжигает сцену днём
		PulseMax = 0.58,
		PulsePeriod = 2.2,
		LightRange = 42,
		LightBrightness = 2.6,
	},
	Eyes = {
		Count = 12,
		Radius = 72, -- радиус размещения глаз вокруг центра
		Height = 6, -- высота над поверхностью
		EyeballSize = 6,
		PupilSize = 2.2,
		LookRange = 200, -- радиус обнаружения игроков
		LookUpdateHz = 10, -- частота обновления слежения
		BlinkMinInterval = 2.5,
		BlinkMaxInterval = 7.0,
		BlinkDuration = 0.15,
		WanderSpeed = 0.4,
	},
	Tentacles = {
		Count = 10,
		Segments = 6,
		SegmentLength = 5,
		SegmentThickness = 2.4,
		-- Снаружи шеллы, чтобы были хорошо видны на фоне неба/леса
		PlacementRadius = 75, -- Platform.Radius (70) + 5
		WaveSpeed = 1.6,
		WaveAmplitude = 0.35,
		Color = Color3.fromRGB(160, 60, 230),
	},
	MicroJolt = {
		Enabled = true,
		-- Усилены, чтобы ощущаться поверх Humanoid-контроллера
		IntensityX = 1.4,
		IntensityZ = 1.4,
		SpeedX = 1.5,
		SpeedZ = 1.8,
		ImpulseScale = 0.25,
	},

	-- «Вязкая нестабильность»: клиент обнуляет Humanoid.PlatformStand не использует,
	-- но снижает контроль остановки через WalkSpeed коэффициент и добавляет
	-- «дрифт-импульс» пропорционально текущей скорости.
	Drift = {
		Enabled = true,
		DriftDecay = 0.92, -- коэффициент затухания «собственной» скорости
		InertiaBoost = 1.4, -- множитель импульса при движении
	},
}

-- =====================================================================
-- Награды и прогресс
-- =====================================================================
Config.Rewards = {
	TickInterval = 1.0, -- как часто тикает таймер (сек)
	CoinsPerSecond = 1, -- базовая валюта за секунду в круге
	FriendMultiplier = 1.25, -- +25% если ≥N друзей в круге
	FriendThreshold = 5, -- N друзей для бонуса
	FriendCacheTTL = 300, -- сек на кэш списка друзей
	BillboardHeight = 3.2, -- высота таймера над головой
}

-- =====================================================================
-- Трансформации
-- =====================================================================
Config.Transformations = {
	Stage1Time = 300, -- 5 минут: "Желейный блеск"
	Stage2Time = 900, -- 15 минут: "Цыплёнок-Слайм"
	Stage3Time = 1800, -- 30 минут: "Диско-Монстр"

	Stage2 = {
		ChickMeshId = 0, -- TODO: upload custom mesh, paste ID
		ChickTextureId = 0,
		PiPiSoundId = 0, -- TODO: upload "PI-PI!" sound
	},
	Stage3 = {
		PointLightBrightness = 3,
		PointLightRange = 14,
		HSVCycleSpeed = 0.2, -- долей в секунду
	},
}

-- =====================================================================
-- Ауры
-- =====================================================================
Config.Aura = {
	ParticleTextureId = 0, -- TODO: upload particle texture
	BaseRate = 0.5,
	RatePerSecond = 0.1, -- частота растёт на 0.1 в секунду сессии
	MaxRate = 80,
	BaseSize = 1.0,
	SizePerMinute = 0.1, -- аура физически растёт
	MaxSize = 6.0,
	RecordBeamTextureId = 0, -- TODO: upload lightning texture
}

-- =====================================================================
-- События
-- =====================================================================
Config.Events = {
	IntervalMin = 90,
	IntervalMax = 120,
	AntiRepeatWindow = 2, -- не повторять последние N событий

	JellyTremor = {
		Duration = 12,
		PrepTime = 2.0,
		TickInterval = 0.1,
		AngularForce = 40,
		PlatformShift = 1.35,
		TiltAngleDeg = 8,
		HorizontalImpulseMin = 90,
		HorizontalImpulseMax = 145,
		HorizontalVelocityMin = 42,
		HorizontalVelocityMax = 68,
		SurfaceFriction = 0.005,
		JumpSafeHeight = 2.6,
		HintDelay = 0.1,
		PrepBannerText = "ЖЕЛЕЙНАЯ ДРОЖЬ НАЧНЕТСЯ ЧЕРЕЗ 2 СЕКУНДЫ!",
		HintText = "ПЛАТФОРМУ СЕЙЧАС НАЧНЕТ СИЛЬНО ТРЯСТИ. ЧТОБЫ УДЕРЖАТЬСЯ, ПОСТОЯННО ПРЫГАЙ!",
		CameraShakeMag = 1.25,
	},

	StickyRain = {
		Duration = 20,
		DropCount = 18,
		DropRadius = 2.2,
		StickTime = 8, -- как долго жертва остаётся липкой
		PullRadius = 14,
		PullForce = 15000,
	},

	TastyBite = {
		Duration = 15,
		SegmentsToBite = 3,
		WarnTime = 3,
		RegrowTime = 5,
	},

	BubbleTrap = {
		Duration = 25,
		BubbleCount = 18,
		BubbleSize = 7,
		DriftSpeed = 12,
		RoamAngularSpeedMin = 0.7,
		RoamAngularSpeedMax = 1.7,
		RadialWave = 10,
		HoverHeight = 5,
		CatchRadius = 6.5,
		MashesToBreak = 14,
	},

	MonsterSneeze = {
		WarnTime = 3,
		BlastImpulse = 220,
		BlastUp = 80,
	},

	SpinCycle = {
		Duration = 18,
		PrepTime = 3.0, -- предупреждение до начала вращения
		AngularVel = 3.6, -- рад/сек
		RadialPull = 13, -- базовое наружное унесение
		TangentialPull = 18, -- закручивание по касательной
		ChaosPull = 9, -- боковой хаос, чтобы уносило непредсказуемо
		DigWindow = 3.0, -- окно в начале события, чтобы успеть зарыться
		BuryDepth = 3.6, -- насколько глубоко персонаж уходит в тело монстра
		BuryDuration = 0.45,
		HoldGrace = 1.5, -- сколько можно не держать Space до срыва
		EdgeThreshold = 0.86, -- доля радиуса платформы, после которой катапультирует
		LaunchUp = 155,
		LaunchOut = 175,
		LaunchSpin = 28,
		LaunchRagdollTime = 2.4,
		HintDelayE = 0.15,
		HintDelaySpace = 0.1,
		PrepBannerText = "ЦЕНТРИФУГА НАЧНЕТСЯ ЧЕРЕЗ 3 СЕКУНДЫ!",
		HintTextE = "НАЖМИ E: ЗАРОЙСЯ В ТЕЛО МОНСТРА",
		HintTextSpace = "ДЕРЖИ SPACE, ЧТОБЫ УДЕРЖАТЬСЯ!",
	},

	MagnetMayhem = {
		Duration = 20,
		Force = 7500,
	},

	GiantSpoon = {
		Duration = 16,
		SpoonLength = 35,
		RotSpeed = 1.4,
		RagdollTime = 2,
	},

	SpicyFloor = {
		Duration = 12,
		BounceInterval = 0.5,
		BounceImpulse = 80,
	},
}

-- =====================================================================
-- Магазин Пакостей
-- =====================================================================
Config.Shop = {
	-- Developer Product IDs (TODO: опубликовать и подставить реальные)
	Products = {
		BananaPeel = 0,
		FreezeBeam = 0,
		SlimeCannon = 0,
		BigCoins = 0,
		VIPBoost = 0,
	},
	-- GamePass IDs
	GamePasses = {
		VIP = 0,
	},
	-- Внутренняя валюта (покупается за Robux или начисляется)
	PrankPrices = {
		BananaPeel = 50,
		FreezeBeam = 120,
		SlimeCannon = 200,
	},
}

-- =====================================================================
-- Пранки (механика)
-- =====================================================================
Config.Pranks = {
	BananaPeel = {
		SlipTime = 3,
		EdgeImpulse = 180,
		TrapLifetime = 30,
	},
	FreezeBeam = {
		Range = 80,
		FreezeTime = 5,
		BeamWidth = 0.4,
		BeamColor = Color3.fromRGB(120, 220, 255),
	},
	SlimeCannon = {
		ProjectileSpeed = 80,
		BaseKnockback = 150,
		SessionScaling = 600, -- force *= 1 + sessionTime/600
		Cooldown = 0.6,
	},
}

-- =====================================================================
-- Соц-триггеры
-- =====================================================================
Config.Social = {
	VoteInterval = 300, -- 5 мин
	VoteDuration = 20,
	VoteOptionCount = 3,

	FriendshipMinPlayers = 3,
	FriendshipBonusRate = 2, -- монет/сек доп. всем в круге
	FriendshipDanceAnimationIds = {
		-- Roblox стандартные эмоции (ID из AvatarEditorService)
		-- TODO: либо animationId, либо проверяем активную эмоцию Humanoid
	},

	RevengeDiscount = 0.5, -- 50% на пранк обидчика
	RevengeWindow = 30, -- сек на отмщение
	RevengeDetectionWindow = 2, -- последний контакт в течение 2 сек = обидчик
}

-- =====================================================================
-- Лидерборд / данные
-- =====================================================================
Config.Data = {
	DataStoreName = "JMC_Players_v1",
	SessionStoreName = "JMC_Session_v1",
	OrderedStoreName = "JMC_LongestSlime_v1",
	AutoSaveInterval = 60,
	MaxRetries = 3,
	RetryDelay = 1.2,
}

-- =====================================================================
-- Juice / Audio
-- =====================================================================
Config.Audio = {
	-- TODO: все ID — подставить после загрузки в Roblox
	Music = {
		Ambient = 0, -- спокойный фоновый саундтрек
		Intense = 0, -- ускоренный для событий
	},
	Sfx = {
		Squish = 0,
		Splat = 0,
		Bubble = 0,
		Sneeze = 0,
		Firework = 0,
		PurchaseOk = 0,
		EventStart = 0,
	},
}

Config.Overlay = {
	-- Asset IDs для декалей оверлея (TODO)
	SlimeDrops = 0, -- зелёные капли для «Чиха»
	SpicyFlame = 0, -- красные края для «Spicy Floor»
	IceEdge = 0, -- синяя вуаль при заморозке
}

-- =====================================================================
-- Воздушная пушка (возврат на платформу снизу)
-- =====================================================================
Config.AirCannon = {
	-- Расположение: сбоку от платформы (ось Z, не X — чтобы не перекрывать билборд)
	SideDistance = 22, -- studs за радиусом платформы
	-- Визуал
	BodyHeight = 10,
	BodyRadius = 6,
	NozzleHeight = 2.5,
	NozzleRadius = 7,
	RingCount = 4,
	BodyColor = Color3.fromRGB(110, 225, 255),
	NozzleColor = Color3.fromRGB(80, 200, 255),
	-- Зона поимки: только рядом с пушкой, а не под всей платформой
	TriggerRadius = 18, -- небольшой горизонтальный радиус вокруг самой пушки
	CatchDepth = 18, -- на сколько studs ниже нижней грани платформы расположена зона
	-- Физика запуска (70° от горизонта)
	LaunchAngle = 70, -- градусов от горизонтали
	LaunchSpeed = 115, -- полная скорость запуска (studs/s)
	Cooldown = 2.5,
}

-- =====================================================================
-- Debug
-- =====================================================================
Config.Debug = {
	Enabled = false,
	LogEvents = true,
	ForceEventName = nil, -- строкой "JellyTremor" и т.д. для теста
	OwnerUserIds = { -- userIds, которым доступны чат-команды вроде /event
		-- TODO: добавить свой userId
	},
}

return Config
