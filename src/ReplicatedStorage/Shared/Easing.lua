--!strict
--[[
    Easing.lua
    Набор easing-функций (нормированные t ∈ [0..1] → [0..1]).
    Используем для ручной интерполяции там, где TweenService неудобен
    (напр. Camera Shake, pulse-эффекты на UI).
--]]

local Easing = {}

function Easing.linear(t: number): number
	return t
end

function Easing.quadIn(t: number): number
	return t * t
end

function Easing.quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

function Easing.quadInOut(t: number): number
	if t < 0.5 then
		return 2 * t * t
	else
		return 1 - (-2 * t + 2) ^ 2 / 2
	end
end

function Easing.cubicIn(t: number): number
	return t ^ 3
end

function Easing.cubicOut(t: number): number
	return 1 - (1 - t) ^ 3
end

function Easing.sineIn(t: number): number
	return 1 - math.cos((t * math.pi) / 2)
end

function Easing.sineOut(t: number): number
	return math.sin((t * math.pi) / 2)
end

function Easing.sineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

function Easing.backOut(t: number, overshoot: number?): number
	local s = overshoot or 1.70158
	t = t - 1
	return t * t * ((s + 1) * t + s) + 1
end

function Easing.elasticOut(t: number): number
	if t == 0 or t == 1 then
		return t
	end
	local p = 0.3
	local s = p / 4
	return 2 ^ (-10 * t) * math.sin((t - s) * (2 * math.pi) / p) + 1
end

function Easing.bounceOut(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t = t - 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end

--- Линейная интерполяция
function Easing.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Интерполяция Vector3
function Easing.lerpVector(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

return Easing
