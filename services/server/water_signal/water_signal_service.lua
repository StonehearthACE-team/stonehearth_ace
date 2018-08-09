local log = radiant.log.create_logger('water_signal_service')

local WaterSignalService = class()

function WaterSignalService:initialize()
	self._water_signal_buckets = {}	-- contains all the low-priority water signals
	self._urgent_water_signals = {} -- contains all the urgent water signals
	self._water_signals_in_buckets = {}	-- contains all the water signals with references to their buckets
	self._current_bucket_index = 1
	self._max_buckets = 20	-- hydrology service ticks happen ~10/second, so our normal checks will happen once every two seconds
	self._current_tick_index = 1
	self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
		self:_on_tick()
	end)
end

function WaterSignalService:destroy()
	if self._on_tick_listener then
		self._on_tick_listener:destroy()
		self._on_tick_listener = nil
	end
end

function WaterSignalService:register_water_signal(water_signal, is_urgent)
	local id = water_signal:get_entity_id()
	
	-- if it's urgent, don't bother with the buckets
	if is_urgent then
		self._urgent_water_signals[id] = water_signal
	else
		-- check to see if this water signal is already registered; if so, exit
		if self._water_signals_in_buckets[id] then
			return
		end
		
		-- keep a list of signals by their id so we can find their bucket to remove them later
		self._water_signals_in_buckets[id] = self._current_bucket_index
		
		-- if we don't already have a bucket, add one
		local bucket = self._water_signal_buckets[self._current_bucket_index]
		if not bucket then
			self._water_signal_buckets[self._current_bucket_index] = {}
		end
		self._water_signal_buckets[self._current_bucket_index][id] = water_signal

		-- increment our current bucket index, wrapping around when we reach our max (keeping it 1-indexed)
		self._current_bucket_index = (self._current_bucket_index % self._max_buckets) + 1
	end
end

function WaterSignalService:unregister_water_signal(water_signal)
	local id = water_signal and water_signal:get_entity_id()
	if not id then
		return
	end

	-- first try to remove it from the urgent table
	self._urgent_water_signals[id] = nil

	-- then check to see if it's in a bucket and remove it from that bucket
	local bucket_index = self._water_signals_in_buckets[id]
	if bucket_index then
		self._water_signals_in_buckets[id] = nil
		local bucket = self._water_signal_buckets[bucket_index]
		bucket[id] = nil
		if next(bucket) == nil then
			self._water_signal_buckets[bucket_index] = nil
		end
	end
end

function WaterSignalService:_on_tick()
	-- first process urgent signals
	for _, water_signal in pairs(self._urgent_water_signals) do
		water_signal:_on_tick_water_signal()
	end

	-- then process the signals for the current tick index
	local bucket = self._water_signal_buckets[self._current_tick_index]
	if bucket and next(bucket) then
		for _, water_signal in pairs(bucket) do
			water_signal:_on_tick_water_signal()
		end
	end
	log:spam('current water tick index: %s', self._current_tick_index)
	self._current_tick_index = (self._current_tick_index % self._max_buckets) + 1
end

return WaterSignalService
