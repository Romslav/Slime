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
    ForestTreeCount = 90,           -- сколько деревьев расставить вокруг
    ForestRadiusMin = 80,           -- минимальное расстояние от центра
    ForestRadiusMax = 260,          -- максимальное расстояние
    TreeTrunkHeightMin = 8,
    TreeTrunkHeightMax = 22,
    TreeTrunkRadiusMin = 0.8,
    TreeTrunkRadiusMax = 2.2,
    TreeCanopyRadiusMin = 4,
    TreeCanopyRadiusMax = 10,
    TreeCanopyHueRange = { 0.25, 0.55 }, -- салатовый .. розовый в HSV

    -- Атмосфера / туман
    AtmosphereDensity = 0.42,
    AtmosphereColor = Color3.fromRGB(180, 80, 200),
    AtmosphereDecay = Color3.fromRGB(255, 100, 170),
    AtmosphereGlare = 0.2,
    AtmosphereHaze = 2.5,

    -- Sky (null = использовать процедурное небо; для текстур — Asset IDs)
    SkyboxAssetIds = {
        Up = 0, Down = 0, Lf = 0, Rt = 0, Ft = 0, Bk = 0,
    },

    -- Цветовая коррекция
    ColorCorrection = {
        Saturation = 0.2,
        Contrast   = 0.1,
        Brightness = 0.0,
        TintColor  = Color3.fromRGB(255, 240, 255),
    },

    -- Bloom
    Bloom = {
        Intensity = 0.85,
        Size      = 24,
        Threshold = 0.92,
    },

    -- Глобальная гравитация (для события Trampoline временно меняется)
    DefaultGravity = 196.2,
}

-- =====================================================================
-- Платформа (Wobble Engine)
-- =====================================================================
Config.Platform = {
    Radius     = 40,         -- радиус круга (studs)
    Height     = 4,          -- толщина «желе»
    Color      = Color3.fromRGB(255, 120, 200),
    Material   = Enum.Material.Glass,
    Transparency = 0.35,
    Reflectance  = 0.2,

    -- Pulse-дыхание
    PulseDuration = 3.0,     -- сек на половину цикла
    PulseScale    = 0.025,   -- ±2.5%

    -- Физика поверхности
    Friction    = 0.1,
    Elasticity  = 0.2,
    Density     = 0.7,
    FrictionWeight   = 10,   -- чтобы материал персонажа не переопределял
    ElasticityWeight = 10,

    -- Сегменты для «Tasty Bite»
    SegmentCount = 8,
}

-- =====================================================================
-- Награды и прогресс
-- =====================================================================
Config.Rewards = {
    TickInterval        = 1.0,    -- как часто тикает таймер (сек)
    CoinsPerSecond      = 1,      -- базовая валюта за секунду в круге
    FriendMultiplier    = 1.25,   -- +25% если ≥N друзей в круге
    FriendThreshold     = 5,      -- N друзей для бонуса
    FriendCacheTTL      = 300,    -- сек на кэш списка друзей
    BillboardHeight     = 3.2,    -- высота таймера над головой
}

-- =====================================================================
-- Трансформации
-- =====================================================================
Config.Transformations = {
    Stage1Time = 300,    -- 5 минут: "Желейный блеск"
    Stage2Time = 900,    -- 15 минут: "Цыплёнок-Слайм"
    Stage3Time = 1800,   -- 30 минут: "Диско-Монстр"

    Stage2 = {
        ChickMeshId    = 0,  -- TODO: upload custom mesh, paste ID
        ChickTextureId = 0,
        PiPiSoundId    = 0,  -- TODO: upload "PI-PI!" sound
    },
    Stage3 = {
        PointLightBrightness = 3,
        PointLightRange      = 14,
        HSVCycleSpeed        = 0.2, -- долей в секунду
    },
}

-- =====================================================================
-- Ауры
-- =====================================================================
Config.Aura = {
    ParticleTextureId = 0,   -- TODO: upload particle texture
    BaseRate          = 0.5,
    RatePerSecond     = 0.1, -- частота растёт на 0.1 в секунду сессии
    MaxRate           = 80,
    BaseSize          = 1.0,
    SizePerMinute     = 0.1, -- аура физически растёт
    MaxSize           = 6.0,
    RecordBeamTextureId = 0, -- TODO: upload lightning texture
}

-- =====================================================================
-- События
-- =====================================================================
Config.Events = {
    IntervalMin = 90,
    IntervalMax = 120,
    AntiRepeatWindow = 2,   -- не повторять последние N событий

    JellyTremor = {
        Duration       = 10,
        TickInterval   = 0.1,
        AngularForce   = 25,
        CameraShakeMag = 0.8,
    },

    StickyRain = {
        Duration    = 20,
        DropCount   = 18,
        DropRadius  = 2.2,
        StickTime   = 8,      -- как долго жертва остаётся липкой
        PullRadius  = 14,
        PullForce   = 15000,
    },

    TastyBite = {
        Duration       = 15,
        SegmentsToBite = 3,
        WarnTime       = 3,
        RegrowTime     = 10,
    },

    BubbleTrap = {
        Duration         = 25,
        BubbleCount      = 8,
        BubbleSize       = 7,
        DriftSpeed       = 8,
        MashesToBreak    = 14,
    },

    MonsterSneeze = {
        WarnTime      = 3,
        BlastImpulse  = 220,
        BlastUp       = 80,
    },

    TrampolineMode = {
        Duration   = 15,
        Gravity    = 30,
        Elasticity = 1.0,
    },

    SpinCycle = {
        Duration   = 18,
        AngularVel = 2.5,  -- рад/сек
        RadialPull = 9,    -- на единицу расстояния от центра
    },

    MagnetMayhem = {
        Duration = 20,
        Force    = 7500,
    },

    GiantSpoon = {
        Duration    = 16,
        SpoonLength = 35,
        RotSpeed    = 1.4,
        RagdollTime = 2,
    },

    SpicyFloor = {
        Duration  = 12,
        BounceInterval = 0.5,
        BounceImpulse  = 80,
    },
}

-- =====================================================================
-- Магазин Пакостей
-- =====================================================================
Config.Shop = {
    -- Developer Product IDs (TODO: опубликовать и подставить реальные)
    Products = {
        BananaPeel  = 0,
        FreezeBeam  = 0,
        SlimeCannon = 0,
        BigCoins    = 0,
        VIPBoost    = 0,
    },
    -- GamePass IDs
    GamePasses = {
        VIP = 0,
    },
    -- Внутренняя валюта (покупается за Robux или начисляется)
    PrankPrices = {
        BananaPeel  = 50,
        FreezeBeam  = 120,
        SlimeCannon = 200,
    },
}

-- =====================================================================
-- Пранки (механика)
-- =====================================================================
Config.Pranks = {
    BananaPeel = {
        SlipTime        = 3,
        EdgeImpulse     = 180,
        TrapLifetime    = 30,
    },
    FreezeBeam = {
        Range        = 80,
        FreezeTime   = 5,
        BeamWidth    = 0.4,
        BeamColor    = Color3.fromRGB(120, 220, 255),
    },
    SlimeCannon = {
        ProjectileSpeed = 80,
        BaseKnockback   = 150,
        SessionScaling  = 600,   -- force *= 1 + sessionTime/600
        Cooldown        = 0.6,
    },
}

-- =====================================================================
-- Соц-триггеры
-- =====================================================================
Config.Social = {
    VoteInterval     = 300,  -- 5 мин
    VoteDuration     = 20,
    VoteOptionCount  = 3,

    FriendshipMinPlayers = 3,
    FriendshipBonusRate  = 2,  -- монет/сек доп. всем в круге
    FriendshipDanceAnimationIds = {
        -- Roblox стандартные эмоции (ID из AvatarEditorService)
        -- TODO: либо animationId, либо проверяем активную эмоцию Humanoid
    },

    RevengeDiscount = 0.5,    -- 50% на пранк обидчика
    RevengeWindow   = 30,     -- сек на отмщение
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
        Ambient = 0,       -- спокойный фоновый саундтрек
        Intense = 0,       -- ускоренный для событий
    },
    Sfx = {
        Squish     = 0,
        Splat      = 0,
        Bubble     = 0,
        Sneeze     = 0,
        Firework   = 0,
        PurchaseOk = 0,
        EventStart = 0,
    },
}

Config.Overlay = {
    -- Asset IDs для декалей оверлея (TODO)
    SlimeDrops = 0,     -- зелёные капли для «Чиха»
    SpicyFlame = 0,     -- красные края для «Spicy Floor»
    IceEdge    = 0,     -- синяя вуаль при заморозке
}

-- =====================================================================
-- Debug
-- =====================================================================
Config.Debug = {
    Enabled = false,
    LogEvents = true,
    ForceEventName = nil,   -- строкой "JellyTremor" и т.д. для теста
    OwnerUserIds = {        -- userIds, которым доступны чат-команды вроде /event
        -- TODO: добавить свой userId
    },
}

return Config
