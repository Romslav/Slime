--!strict
--[[
    Signal.lua
    Лёгкий Signal-класс (аналог RBXScriptSignal) для межмодульной коммуникации.
    Использование:
        local sig = Signal.new()
        local conn = sig:Connect(function(...) end)
        sig:Fire(...)
        conn:Disconnect()
        sig:Destroy()
--]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_signal = signal,
		_fn = fn,
		Connected = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local conns = self._signal._connections
	for i, c in ipairs(conns) do
		if c == self then
			table.remove(conns, i)
			break
		end
	end
end

function Signal.new()
	return setmetatable({
		_connections = {},
	}, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local conn = Connection.new(self, fn)
	table.insert(self._connections, conn)
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	-- итерируем по копии, чтобы Disconnect внутри хэндлера не ломал цикл
	local snapshot = table.clone(self._connections)
	for _, conn in ipairs(snapshot) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for _, conn in ipairs(self._connections) do
		conn.Connected = false
	end
	self._connections = {}
end

return Signal
