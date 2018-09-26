local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('water_pump_service')

local WaterPumpService = class()

function WaterPumpService:initialize()
	self._water_pump_buckets = {}	-- contains all the water pumps, grouped into buckets by elevation
	self._water_pumps = {}	-- contains all the water pumps with references to their elevation
	self._min_elevation = nil	-- instead of always sorting a list, use elevation as a key and process from min to max
	self._max_elevation = nil
	self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
		self:_on_tick()
	end)
end

function WaterPumpService:destroy()
	if self._on_tick_listener then
		self._on_tick_listener:destroy()
		self._on_tick_listener = nil
	end
end

function WaterPumpService:register_water_pump(water_pump, elevation)
	local id = water_pump:get_entity_id()
	
	-- adjust min and max elevation as necessary	
	if self._min_elevation then
		self._min_elevation = math.min(self._min_elevation, elevation)
	else
		self._min_elevation = elevation
	end

	if self._max_elevation then
		self._max_elevation = math.max(self._max_elevation, elevation)
	else
		self._max_elevation = elevation
	end
		
	-- keep a list of pumps by their id so we can find their elevation to remove them from their bucket later
	self._water_pumps[id] = elevation
		
	-- if we don't already have a bucket for this elevation, add one
	local bucket = self._water_pump_buckets[elevation]
	if not bucket then
		self._water_pump_buckets[elevation] = {}
	end
	self._water_pump_buckets[elevation][id] = water_pump
end

function WaterPumpService:unregister_water_pump(water_pump)
	local id = water_pump and water_pump:get_entity_id()
	if not id then
		return
	end

	local elevation = self._water_pumps[id]
	if elevation then
		self._water_pumps[id] = nil
		local bucket = self._water_pump_buckets[elevation]
		bucket[id] = nil
		if next(bucket) == nil then
			self._water_pump_buckets[elevation] = nil
		end
	end
end

function WaterPumpService:_on_tick()
	if not (self._min_elevation and self._max_elevation) then
		return
	end
	
	local new_min, new_max

	for elevation = self._max_elevation, self._min_elevation, -1 do
		local bucket = self._water_pump_buckets[elevation]
		if bucket and next(bucket) then
			if not new_max then
				new_max = elevation
			end
			new_min = elevation

			for _, water_pump in pairs(bucket) do
				water_pump:_on_tick_water_pump()
			end
		end
	end
	
	self._min_elevation = new_min
	self._max_elevation = new_max
end

return WaterPumpService
