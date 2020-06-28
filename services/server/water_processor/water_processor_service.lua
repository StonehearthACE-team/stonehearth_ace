--[[
   This service was created specifically to handle water pumps,
   but since it doesn't specifically reference the water_pump component
   it can be used for processing any type of entity, that needs to do something 
   on the hydrology tick and should be processed in order of elevation
]]

local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('water_processor_service')

local WaterProcessorService = class()

function WaterProcessorService:initialize()
	self._water_processor_buckets = {}	-- contains all the water processors, grouped into buckets by elevation
	self._water_processors = {}	-- contains all the water processors with references to their elevation
	self._min_elevation = nil	-- instead of always sorting a list, use elevation as a key and process from min to max
	self._max_elevation = nil
	self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
		self:_on_tick()
	end)
end

function WaterProcessorService:destroy()
	if self._on_tick_listener then
		self._on_tick_listener:destroy()
		self._on_tick_listener = nil
	end
end

function WaterProcessorService:register_water_processor(entity_id, water_processor, elevation)
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
		
	-- keep a list of processors by their id so we can find their elevation to remove them from their bucket later
	self._water_processors[entity_id] = elevation
		
	-- if we don't already have a bucket for this elevation, add one
	local bucket = self._water_processor_buckets[elevation]
	if not bucket then
		self._water_processor_buckets[elevation] = {}
	end
	self._water_processor_buckets[elevation][entity_id] = water_processor
end

function WaterProcessorService:unregister_water_processor(entity_id, water_processor)
	if not water_processor or not entity_id then
		return
	end

	local elevation = self._water_processors[entity_id]
	if elevation then
		self._water_processors[entity_id] = nil
		local bucket = self._water_processor_buckets[elevation]
		bucket[entity_id] = nil
		if next(bucket) == nil then
			self._water_processor_buckets[elevation] = nil
		end
	end
end

function WaterProcessorService:_on_tick()
	if not (self._min_elevation and self._max_elevation) then
		return
	end
	
   local new_min, new_max
   local all_water_processors = {}

	for elevation = self._max_elevation, self._min_elevation, -1 do
		local bucket = self._water_processor_buckets[elevation]
		if bucket and next(bucket) then
			if not new_max then
				new_max = elevation
			end
			new_min = elevation

			for _, water_processor in pairs(bucket) do
            water_processor:on_tick_water_processor()
            table.insert(all_water_processors, water_processor)
			end
		end
   end
   
   for _, water_processor in ipairs(all_water_processors) do
      water_processor:reset_processed_this_tick()
   end
	
	self._min_elevation = new_min
	self._max_elevation = new_max
end

return WaterProcessorService
