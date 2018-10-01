local log = radiant.log.create_logger('wilderness_signal_service')

local WildernessSignalService = class()

-- this signal service will be have significantly differently than the water signal service
-- for water signals, there's already a constant tick happening from the hydrology service
-- so we can just listen to that and distribute our signal processing over time.
-- for wilderness, we primarily care about static entities being added/removed, and this
-- happens at irregular intervals; luckily, there's a trace we can "listen" to for that,
-- but this means we won't be able to distribute the checks at all and have to do them all every time.

function WildernessSignalService:initialize()
	self._world_entity_trace = radiant.terrain.trace_world_entities('wilderness signal', on_entity_added, on_entity_removed)
end

function WildernessSignalService:destroy()
	if self._world_entity_trace then
		self._world_entity_trace:destroy()
		self._world_entity_trace = nil
	end
end

function WaterSignalService:register_wilderness_signal(wilderness_signal)
	local id = wilderness_signal:get_entity_id()
	
	-- if it's urgent, don't bother with the buckets
	if is_urgent then
		self._wilderness_signals[id] = wilderness_signal
	else
		-- check to see if this wilderness signal is already registered; if so, exit
		if self._wilderness_signals_in_buckets[id] then
			return
		end
		
		-- keep a list of signals by their id so we can find their bucket to remove them later
		self._wilderness_signals_in_buckets[id] = self._current_bucket_index
		
		-- if we don't already have a bucket, add one
		local bucket = self._wilderness_signal_buckets[self._current_bucket_index]
		if not bucket then
			self._wilderness_signal_buckets[self._current_bucket_index] = {}
		end
		self._wilderness_signal_buckets[self._current_bucket_index][id] = wilderness_signal

		-- increment our current bucket index, wrapping around when we reach our max (keeping it 1-indexed)
		self._current_bucket_index = (self._current_bucket_index % self._max_buckets) + 1
	end
end

function WaterSignalService:unregister_wilderness_signal(wilderness_signal)
	local id = wilderness_signal and wilderness_signal:get_entity_id()
	if not id then
		return
	end

	-- first try to remove it from the urgent table
	self._urgent_wilderness_signals[id] = nil

	-- then check to see if it's in a bucket and remove it from that bucket
	local bucket_index = self._wilderness_signals_in_buckets[id]
	if bucket_index then
		self._wilderness_signals_in_buckets[id] = nil
		local bucket = self._wilderness_signal_buckets[bucket_index]
		bucket[id] = nil
		if next(bucket) == nil then
			self._wilderness_signal_buckets[bucket_index] = nil
		end
	end
end

function WaterSignalService:_on_tick()
	-- first process urgent signals
	for _, wilderness_signal in pairs(self._urgent_wilderness_signals) do
		wilderness_signal:_on_tick_wilderness_signal()
	end

	-- then process the signals for the current tick index
	local bucket = self._wilderness_signal_buckets[self._current_tick_index]
	if bucket and next(bucket) then
		for _, wilderness_signal in pairs(bucket) do
			wilderness_signal:_on_tick_wilderness_signal()
		end
	end
	log:spam('current water tick index: %s', self._current_tick_index)
	self._current_tick_index = (self._current_tick_index % self._max_buckets) + 1
end

return WaterSignalService
