--!strict
--[[
    Util.lua
    Общие хелперы, которые нужны и серверу, и клиенту.
--]]

local Players = game:GetService("Players")

local Util = {}

local RNG = Random.new()

--- Случайный float в [min..max]
function Util.randf(min: number, max: number): number
    return min + (max - min) * RNG:NextNumber()
end

--- Случайный int в [min..max]
function Util.randi(min: number, max: number): number
    return RNG:NextInteger(min, max)
end

--- Случайная точка внутри круга радиуса r на высоте y
function Util.randomPointInCircle(center: Vector3, radius: number, y: number?): Vector3
    local angle = RNG:NextNumber() * math.pi * 2
    local r = math.sqrt(RNG:NextNumber()) * radius
    return Vector3.new(
        center.X + math.cos(angle) * r,
        y or center.Y,
        center.Z + math.sin(angle) * r
    )
end

--- Точка на окружности
function Util.pointOnCircle(center: Vector3, radius: number, angle: number, y: number?): Vector3
    return Vector3.new(
        center.X + math.cos(angle) * radius,
        y or center.Y,
        center.Z + math.sin(angle) * radius
    )
end

--- Weighted pick: массив { {value, weight}, ... }
function Util.weightedPick<T>(options: { { any } }): T
    local total = 0
    for _, o in ipairs(options) do total = total + (o[2] or 1) end
    local pick = RNG:NextNumber() * total
    for _, o in ipairs(options) do
        pick = pick - (o[2] or 1)
        if pick <= 0 then return o[1] end
    end
    return options[#options][1]
end

--- HSV-цвет с «конфетным» профилем: высокая saturation/value.
function Util.candyColor(hueMin: number?, hueMax: number?): Color3
    local h = Util.randf(hueMin or 0.0, hueMax or 1.0)
    return Color3.fromHSV(h, 0.85 + RNG:NextNumber() * 0.15, 0.95)
end

--- Безопасно достать HumanoidRootPart игрока
function Util.getHRP(player: Player): BasePart?
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

--- Безопасно достать Humanoid игрока
function Util.getHumanoid(player: Player): Humanoid?
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

--- Все живые игроки
function Util.livingPlayers(): { Player }
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local h = Util.getHumanoid(p)
        if h and h.Health > 0 then
            table.insert(list, p)
        end
    end
    return list
end

--- Tween-свойства: обёртка над TweenService:Create
function Util.tween(instance: Instance, info: TweenInfo, props: { [string]: any }): Tween
    local TweenService = game:GetService("TweenService")
    local tween = TweenService:Create(instance, info, props)
    tween:Play()
    return tween
end

--- Удалить инстанс через N секунд (безопасно к повторам)
function Util.debrisAdd(inst: Instance, lifetime: number)
    game:GetService("Debris"):AddItem(inst, lifetime)
end

--- Округлить до N знаков
function Util.round(value: number, digits: number?): number
    local m = 10 ^ (digits or 0)
    return math.floor(value * m + 0.5) / m
end

--- Форматировать сек в MM:SS
function Util.formatTime(seconds: number): string
    local s = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--- Протектед wrapper: вызывает fn в защищённом режиме, логирует ошибки
function Util.safeCall<T>(fn: () -> T, label: string?): T?
    local ok, result = pcall(fn)
    if not ok then
        warn(string.format("[JMC][%s] %s", label or "safeCall", tostring(result)))
        return nil
    end
    return result
end

return Util
