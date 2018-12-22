--[[
   individual water signals get registered with this service and have their regions cached here
   whenever a water or waterfall component is changed, it alerts the service
   on every hydrology tick, all water and waterfall entities that changed are evaluated:
      - all signals that cached a reference to them, and all signals whose regions intersect with them, get signalled
      - signal caching is updated
   whenever a water signal's region (or location) changes, update the cache and signal it
]]

local log = radiant.log.create_logger('water_signal_service')

local WaterSignalService = class()

local CHUNK_SIZE = 50   -- this should be a reasonably large number because lakes can take up a lot of chunks

function WaterSignalService:initialize()
   if self._sv.signals then
      self._sv.signals = nil
      self.__saved_variables:mark_changed()
   end
   self._signals = {}
   self._signals_by_chunk = {}
   self._water_chunks = {}
   self._waterfall_chunks = {}
   self._changed_waters = {}
   self._changed_pathing = {}
   self._changed_waterfalls = {}
   self._next_tick_callbacks = {}
   self._current_tick = 0
   self:set_update_frequency(radiant.util.get_config('water_signal_update_frequency', 1))
   
   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      self._game_loaded_listener = nil
      self:_create_tick_listener()
   end)
   self._world_generated_listener = radiant.events.listen_once(stonehearth.game_creation, 'stonehearth:world_generation_complete', function()
      self._world_generated_listener = nil
      self:_create_tick_listener()
   end)
end

function WaterSignalService:destroy()
	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
   end
   if self._world_generated_listener then
		self._world_generated_listener:destroy()
		self._world_generated_listener = nil
   end
end

function WaterSignalService:_create_tick_listener()
   if not self._tick_listener then
      self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
         self:_on_tick()
      end)
   end
end

function WaterSignalService:set_update_frequency(frequency)
   self._update_frequency = math.max(1, math.min(10, frequency))
   self._update_tick_mod = self._update_frequency * 10
   self._update_pathing_tick = self._update_tick_mod / 2
end

function WaterSignalService:register_water_signal(water_signal)
   local id = water_signal:get_id()
   if not id then
      return
   end
   
   local check_all_waters = false

   local signal = self._signals[id]
   if not signal then
      signal = {
         id = id,
         entity_id = water_signal:get_entity_id(),
         signal = water_signal,
         waters = {},
         waterfalls = {}
      }
      self._signals[id] = signal

      check_all_waters = true
   end
   self:_update_signal_region(signal)
   self:_update_signal_monitor_types(signal)
end

function WaterSignalService:_update_signal_region(signal)
   local region = signal.signal:get_world_signal_region()
   if region or (region == nil) ~= (signal.region == nil) then
      signal.region = region
      
      if signal.chunks then
         for chunk_id, _ in pairs(signal.chunks) do
            local chunk = self._signals_by_chunk[chunk_id]
            if chunk then
               chunk[signal.id] = nil
            end
         end
      end
      
      signal.chunks = self:_get_chunks(region)
      for chunk_id, _ in pairs(signal.chunks) do
         local chunk = self._signals_by_chunk[chunk_id]
         if not chunk then
            chunk = {}
            self._signals_by_chunk[chunk_id] = chunk
         end
         chunk[signal.id] = true
      end
   end
end

function WaterSignalService:_update_signal_monitor_types(signal)
   signal.monitors_water = signal.signal:monitors_water()
   signal.monitors_waterfall = signal.signal:monitors_waterfall()
end

function WaterSignalService:unregister_water_signal(water_signal)
	local id = water_signal and water_signal:get_id()
	if not id then
		return
	end

   self._signals[id] = nil
end

-- if the water component was modified, make sure it gets processed on the next tick
function WaterSignalService:water_component_modified(entity)
   self._changed_waters[entity:get_id()] = entity:get_component('stonehearth:water')
end

function WaterSignalService:water_component_pathing_modified(entity)
   self._changed_pathing[entity] = entity:get_component('stonehearth:water')
end

function WaterSignalService:waterfall_component_modified(entity)
   self._changed_waterfalls[entity:get_id()] = entity:get_component('stonehearth:waterfall')
end

function WaterSignalService:add_next_tick_callback(cb, args)
   table.insert(self._next_tick_callbacks, {cb = cb, args = args})
end

function WaterSignalService:_on_tick()
   --log:debug('water signal tick with %s changed waters, %s changed waterfalls, %s signals',
   --      radiant.size(self._changed_waters), radiant.size(self._changed_waterfalls), radiant.size(self._signals))

   self._current_tick = (self._current_tick + 1) % self._update_tick_mod
   if self._current_tick == self._update_pathing_tick then  -- do it on the opposite tick compared to the regular water signal updates (tick 0)
      -- this isn't really the best place for this, but it's the simplest place for it
      if next(self._changed_pathing) then
         for entity, water in pairs(self._changed_pathing) do
            if entity:is_valid() then
               water:update_pathable_region()
            end
         end
         self._changed_pathing = {}
      end
   end
   
   if self._current_tick % self._update_frequency > 0 then
      return
   end

   local signals_to_signal = {}
   local next_tick_callbacks
   if next(self._next_tick_callbacks) then
      next_tick_callbacks = self._next_tick_callbacks
      self._next_tick_callbacks = {}
   end

   if next(self._changed_waters) then
      for water_id, water in pairs(self._changed_waters) do
         local old_chunks = self._water_chunks[water_id]
         
         local location = water:get_location()
         if location then
            local water_region = water:get_region():get():translated(location)
            local chunks = self:_get_chunks(water_region)
            local checked = {}
            self._water_chunks[water_id] = chunks

            for chunk_id, _ in pairs(chunks) do
               for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
                  if not checked[id] then
                     checked[id] = true
                     local signal = self._signals[id]
                     if not signal.waters[water_id] and signal.region and signal.monitors_water and water_region:intersects_region(signal.region) then
                        signals_to_signal[id] = signal
                        signal.waters[water_id] = true
                     end
                  end
               end
            end
         else
            self._water_chunks[water_id] = nil
         end

         local new_chunks = self._water_chunks[water_id] or {}
         for chunk_id, _ in pairs(old_chunks or {}) do
            if not new_chunks[chunk_id] then
               for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
                  local signal = self._signals[id]
                  if signal.waters[water_id] ~= nil then
                     signals_to_signal[id] = signal
                  end
               end
            end
         end
      end
      self._changed_waters = {}
   end

   if next(self._changed_waterfalls) then
      for waterfall_id, waterfall in pairs(self._changed_waterfalls) do
         local old_chunks = self._waterfall_chunks[waterfall_id]
         
         local location = waterfall:get_location()
         if location then
            local waterfall_region = waterfall:get_region():get():translated(location)
            local chunks = self:_get_chunks(waterfall_region)
            local checked = {}
            self._waterfall_chunks[waterfall_id] = chunks

            for chunk_id, _ in pairs(chunks) do
               for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
                  if not checked[id] then
                     checked[id] = true
                     local signal = self._signals[id]
                     if not signal.waterfalls[waterfall_id] and signal.region and signal.monitors_waterfall and waterfall_region:intersects_region(signal.region) then
                        signals_to_signal[id] = signal
                        signal.waterfalls[waterfall_id] = true
                     end
                  end
               end
            end
         else
            self._waterfall_chunks[waterfall_id] = nil
         end

         local new_chunks = self._waterfall_chunks[waterfall_id] or {}
         for chunk_id, _ in pairs(old_chunks or {}) do
            if not new_chunks[chunk_id] then
               for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
                  local signal = self._signals[id]
                  if signal.waterfalls[waterfall_id] ~= nil then
                     signals_to_signal[id] = signal
                  end
               end
            end
         end
      end
      self._changed_waterfalls = {}
   end

   for _, signal in pairs(signals_to_signal) do
      local entity = signal.entity or radiant.entities.get_entity(signal.entity_id)
      log:debug('getting signal entity from id %s: %s', signal.entity_id, entity or 'NIL')
      if entity and entity:is_valid() then
         signal.entity = entity
         signal.signal:_on_tick_water_signal(signal.waters, signal.waterfalls)
      end

      for water_id, intersects in pairs(signal.waters) do
         if intersects then
            signal.waters[water_id] = false
         else
            signal.waters[water_id] = nil
         end
      end
      for waterfall_id, intersects in pairs(signal.waterfalls) do
         if intersects then
            signal.waterfalls[waterfall_id] = false
         else
            signal.waterfalls[waterfall_id] = nil
         end
      end
   end

   if next_tick_callbacks then
      for _, cb_struct in ipairs(next_tick_callbacks) do
         cb_struct.cb(cb_struct.args)
      end
   end
end

function WaterSignalService:_get_chunks(region)
   local chunks = {}
   if region then
      local bounds = region:get_bounds()
      local min = bounds.min
      local max = bounds.max
      local chunk_region_size = CHUNK_SIZE
      for x = math.floor((min.x + 1)/chunk_region_size), math.floor(max.x/chunk_region_size) do
         for y = math.floor((min.y + 1)/chunk_region_size), math.floor(max.y/chunk_region_size) do
            for z = math.floor((min.z + 1)/chunk_region_size), math.floor(max.z/chunk_region_size) do
               chunks[string.format('%d,%d,%d', x, y, z)] = true
            end
         end
      end
   end
   return chunks
end

return WaterSignalService
