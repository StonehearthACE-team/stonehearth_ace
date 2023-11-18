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

local CHUNK_SIZE = 10   -- this should be a reasonably large number because lakes can take up a lot of chunks
local CHUNK_DIVISOR = 1 / CHUNK_SIZE
local floor = math.floor
local format = string.format

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
   self._changed_water_volumes = {}
   self._changed_pathing = {}
   self._changed_waterfalls = {}
   self._changed_waterfall_volumes = {}
   self._water_change_listeners = {}
   self._waterfall_change_listeners = {}
   self._next_tick_callbacks = {}
   self._current_tick = 0
   self:set_update_frequency(radiant.util.get_config('water_signal_update_frequency', 1))

   self._processing_on_tick = false
end

function WaterSignalService:destroy()
	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
   end
   --[[
   if self._world_generated_listener then
		self._world_generated_listener:destroy()
		self._world_generated_listener = nil
   end
   ]]
end

function WaterSignalService:start()
   self:_create_tick_listener()
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
   --self._update_pathing_tick = self._update_tick_mod / 2
end

function WaterSignalService:register_water_signal(water_signal)
   local id = water_signal:get_id()
   if not id then
      return
   end

   local check_signals

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
   else
      check_signals = true
   end
   self:_update_signal_region(signal)
   self:_update_signal_monitor_types(signal)

   -- if check_signals then
   --    if not signal.region then
   --       return true
   --    end
   --    -- if it still intersects with its cached waters and waterfalls, it didn't change
   --    for id, _ in pairs(signal.waters) do
   --       local water = radiant.entities.get_entity(id)
   --       water = water and water:is_valid() and water:get_component('stonehearth:water')
   --       if not water then
   --          return true
   --       end
   --       local location = water:get_location()
   --       if location then
   --          local water_region = water:get_region():get():translated(location)
   --          if not water_region:intersects_region(signal.region) then
   --             return true
   --          end
   --       end
   --    end

   --    for id, _ in pairs(signal.waterfalls) do
   --       local waterfall = radiant.entities.get_entity(id)
   --       waterfall = waterfall and waterfall:is_valid() and waterfall:get_component('stonehearth:waterfall')
   --       if not waterfall then
   --          return true
   --       end
   --       local location = waterfall:get_location()
   --       if location then
   --          local waterfall_region = waterfall:get_region():get():translated(location)
   --          if not waterfall_region:intersects_region(signal.region) then
   --             return true
   --          end
   --       end
   --    end

   --    return false
   -- end

   -- return true
end

function WaterSignalService:_update_signal_region(signal)
   local region = signal.signal:get_world_signal_region()
   if region or (region == nil) ~= (signal.region == nil) then
      signal.region = region
      
      -- most of the time, an entity is only in 1 or maybe 2 chunks
      -- it's probably not worth it to compare the old chunks to the new chunks to cancel this process
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

   local signal = self._signals[id]
   if signal and signal.chunks then
      for chunk_id, _ in pairs(signal.chunks) do
         local chunk = self._signals_by_chunk[chunk_id]
         if chunk then
            chunk[id] = nil
            if not next(chunk) then
               self._signals_by_chunk[chunk_id] =  nil
            end
         end
      end
   end
   self._signals[id] = nil
end

-- if the water component was modified, make sure it gets processed on the next tick
function WaterSignalService:water_component_modified(entity, volume_change)
   if volume_change then
      self._changed_water_volumes[entity:get_id()] = entity:get_component('stonehearth:water')
   else
      self._changed_waters[entity:get_id()] = entity:get_component('stonehearth:water')
   end
end

function WaterSignalService:water_component_pathing_modified(entity)
   --self._changed_pathing[entity] = entity:get_component('stonehearth:water')
end

function WaterSignalService:waterfall_component_modified(entity, volume_change)
   if volume_change then
      self._changed_waterfall_volumes[entity:get_id()] = entity:get_component('stonehearth:waterfall')
   else
      self._changed_waterfalls[entity:get_id()] = entity:get_component('stonehearth:waterfall')
   end
end

function WaterSignalService:register_water_change_listener(id, water_id, callback_fn)
   local listeners = self._water_change_listeners[water_id]
   if not listeners then
      listeners = {}
      self._water_change_listeners[water_id] = listeners
   end

   listeners[id] = callback_fn or true
end

function WaterSignalService:unregister_water_change_listener(id, water_id)
   local listeners = self._water_change_listeners[water_id]
   if listeners then
      listeners[id] = nil
      if not next(listeners) then
         self._water_change_listeners[water_id] = nil
      end
   end
end

function WaterSignalService:register_waterfall_change_listener(id, waterfall_id, callback_fn)
   local listeners = self._waterfall_change_listeners[waterfall_id]
   if not listeners then
      listeners = {}
      self._waterfall_change_listeners[waterfall_id] = listeners
   end

   listeners[id] = callback_fn or true
end

function WaterSignalService:unregister_waterfall_change_listener(id, waterfall_id)
   local listeners = self._waterfall_change_listeners[waterfall_id]
   if listeners then
      listeners[id] = nil
      if not next(listeners) then
         self._waterfall_change_listeners[waterfall_id] = nil
      end
   end
end

function WaterSignalService:add_next_tick_callback(cb, args)
   table.insert(self._next_tick_callbacks, {cb = cb, args = args})
end

function WaterSignalService:is_processing_on_tick()
   return self._processing_on_tick
end

function WaterSignalService:_on_tick()
   self._processing_on_tick = true
   
   self._current_tick = (self._current_tick + 1) % self._update_tick_mod
   -- if self._current_tick == self._update_pathing_tick then  -- do it on the opposite tick compared to the regular water signal updates (tick 0)
   --    -- this isn't really the best place for this, but it's the simplest place for it
   --    if next(self._changed_pathing) then
   --       for entity, water in pairs(self._changed_pathing) do
   --          if entity:is_valid() then
   --             water:update_pathable_region()
   --          end
   --       end
   --       self._changed_pathing = {}
   --    end
   -- end
   
   if self._current_tick % self._update_frequency > 0 then
      self._processing_on_tick = false
      return
   end

   --log:debug('water signal tick with %s changed waters, %s changed waterfalls, %s signals',
   --      radiant.size(self._changed_waters), radiant.size(self._changed_waterfalls), radiant.size(self._signals))

   local signals_to_signal = {}
   local next_tick_callbacks
   if next(self._next_tick_callbacks) then
      next_tick_callbacks = self._next_tick_callbacks
      self._next_tick_callbacks = {}
   end

   -- first check the volume only changes to see if they should be upgraded to real changes (i.e., volume change was significant)
   for water_id, water in pairs(self._changed_water_volumes) do
      if not self._changed_waters[water_id] and water:was_changed_since_signal() then
         self._changed_waters[water_id] = water
      --    log:debug('water %s had significant volume changed', water_id)
      -- else
      --    log:debug('water %s didn\'t change', water_id)
      end
      self._changed_water_volumes[water_id] = nil
   end
   for waterfall_id, waterfall in pairs(self._changed_waterfall_volumes) do
      if not self._changed_waterfalls[waterfall_id] and waterfall:was_changed_since_signal() then
         self._changed_waterfalls[waterfall_id] = waterfall
      --    log:debug('waterfall %s had significant volume changed', waterfall_id)
      -- else
      --    log:debug('waterfall %s didn\'t change', waterfall_id)
      end
      self._changed_waterfall_volumes[waterfall_id] = nil
   end

   for water_id, water in pairs(self._changed_waters) do
      radiant.events.trigger_async(radiant.entities.get_entity(water_id), 'stonehearth_ace:water:level_changed', water:get_water_level())

      --log:debug('water %s changed, processing... (water level = %s)', water_id, water:get_water_level())
      local old_chunks = self._water_chunks[water_id]
      
      local location = water:get_location()
      if location then
         local water_region = water:get_region():get():translated(location)
         local chunks = self:_get_chunks(water_region)
         local checked = {}
         --log:debug('setting water_chunks for %s to %s', water_id, radiant.util.table_tostring(chunks))
         self._water_chunks[water_id] = chunks

         for chunk_id, _ in pairs(chunks) do
            for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
               -- only need to check each signal once for each water region, even if it's in multiple chunks
               if not checked[id] then
                  checked[id] = true
                  local signal = self._signals[id]
                  -- we're just checking water right now, not waterfalls, so only care about those that monitor water
                  if signal.region and signal.monitors_water then
                     local intersects = water._entity:is_valid() and water_region:intersects_region(signal.region)
                     -- if it intersects now, or if it used to intersect and no longer does, signal it
                     if intersects or signal.waters[water_id] then
                        signals_to_signal[id] = signal
                        log:debug('signal %s: water %s intersection from %s => %s', signal.id, water_id, tostring(signal.waters[water_id]), intersects)
                        signal.waters[water_id] = intersects
                     end
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

   for waterfall_id, waterfall in pairs(self._changed_waterfalls) do
      --log:debug('waterfall %s changed, processing...', waterfall_id)
      local old_chunks = self._waterfall_chunks[waterfall_id]
      
      local location = waterfall:get_location()
      if location then
         local waterfall_region = waterfall:get_region():get():translated(location)
         -- waterfalls are 1x1 x/z, and we no longer care about y dimension for chunks
         -- since waterfalls never get moved and their size doesn't change, once their chunks are determined, they don't need to be redetermined
         local chunks = self._waterfall_chunks[waterfall_id]
         if not chunks then
            chunks = self:_get_chunks(waterfall_region)
            self._waterfall_chunks[waterfall_id] = chunks
         end
         local checked = {}

         for chunk_id, _ in pairs(chunks) do
            for id, _ in pairs(self._signals_by_chunk[chunk_id] or {}) do
               if not checked[id] then
                  checked[id] = true
                  local signal = self._signals[id]
                  if signal.region and signal.monitors_waterfall then
                     local intersects = waterfall._entity:is_valid() and waterfall_region:intersects_region(signal.region)
                     -- if it intersects now, or if it used to intersect and no longer does, signal it
                     if intersects or signal.waterfalls[waterfall_id] then
                        signals_to_signal[id] = signal
                        signal.waterfalls[waterfall_id] = intersects
                     end
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

   for _, signal in pairs(signals_to_signal) do
      local entity = signal.entity or radiant.entities.get_entity(signal.entity_id)
      --log:debug('getting signal entity from id %s: %s', signal.entity_id, entity or 'NIL')
      if entity and entity:is_valid() then
         signal.entity = entity
         signal.signal:_on_tick_water_signal(signal.waters, signal.waterfalls)
      end

      for water_id, intersects in pairs(signal.waters) do
         if not intersects then
            signal.waters[water_id] = nil
         end
      end
      for waterfall_id, intersects in pairs(signal.waterfalls) do
         if not intersects then
            signal.waterfalls[waterfall_id] = nil
         end
      end
   end

   if next_tick_callbacks then
      for _, cb_struct in ipairs(next_tick_callbacks) do
         cb_struct.cb(cb_struct.args)
      end
   end

   for water_id, water in pairs(self._changed_waters) do
      water:reset_changed_since_signal()
      self._changed_waters[water_id] = nil
      local listeners = self._water_change_listeners[water_id]
      if listeners then
         local trigger_event = false
         for entity_id, callback_fn in pairs(listeners) do
            if callback_fn == true then
               trigger_event = true
            else
               callback_fn(water)
            end
         end
         if trigger_event then
            radiant.events.trigger_async(water, 'stonehearth_ace:water_component:changed')
         end
      end
   end

   for waterfall_id, waterfall in pairs(self._changed_waterfalls) do
      waterfall:reset_changed_since_signal()
      self._changed_waterfalls[waterfall_id] = nil
      local listeners = self._waterfall_change_listeners[waterfall_id]
      if listeners then
         local trigger_event = false
         for entity_id, callback_fn in pairs(listeners) do
            if callback_fn == true then
               trigger_event = true
            else
               callback_fn(waterfall)
            end
         end
         if trigger_event then
            radiant.events.trigger_async(waterfall, 'stonehearth_ace:waterfall_component:changed')
         end
      end
   end

   self._processing_on_tick = false
end

-- old way of doing this was cubes
-- but since most content is spread horizontally, new way is the old minecraft way: only care about x and z bounds, not y
function WaterSignalService:_get_chunks(region)
   local chunks = {}
   if region then
      local bounds = region:get_bounds()
      local min = bounds.min
      local max = bounds.max
      local min_x = floor((min.x + 1) * CHUNK_DIVISOR)
      local max_x = floor(max.x * CHUNK_DIVISOR)
      local min_z = floor((min.z + 1) * CHUNK_DIVISOR)
      local max_z = floor(max.z * CHUNK_DIVISOR)
      for x = min_x, max_x do
         for z = min_z, max_z do
            chunks[format('%d,%d', x, z)] = true
         end
      end
   end
   return chunks
end

return WaterSignalService
