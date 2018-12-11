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

function WaterSignalService:initialize()
   if not self._sv.signals then
      self._sv.signals = {}
   end
   self._changed_waters = {}
   self._changed_waterfalls = {}
   self._next_tick_callbacks = {}
   
   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      self._game_loaded_listener = nil
      self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
         self:_on_tick()
      end)
   end)
end

function WaterSignalService:destroy()
	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
   end
end

function WaterSignalService:register_water_signal(water_signal)
   local id = water_signal:get_id()
   if not id then
      return
   end
   
   local signal = self._sv.signals[id]
   if not signal then
      signal = {
         id = id,
         entity_id = water_signal:get_entity_id(),
         signal = water_signal,
         waters = {},
         waterfalls = {}
      }
      self._sv.signals[id] = signal
   end
   self:_update_signal_regions(water_signal)
end

function WaterSignalService:_update_signal_regions(water_signal)
   local signal = self._sv.signals[water_signal:get_id()]
   if signal then
      local region = signal.signal:get_world_signal_region()
      if (region == nil) ~= (signal.region == nil) then
         signal.region = region
         self.__saved_variables:mark_changed()
      end
   end
end

function WaterSignalService:unregister_water_signal(water_signal)
	local id = water_signal and water_signal:get_id()
	if not id then
		return
	end

   self._sv.signals[id] = nil
   self.__saved_variables:mark_changed()
end

-- if the water component was modified, make sure it gets processed on the next tick
function WaterSignalService:water_component_modified(entity)
   self._changed_waters[entity:get_id()] = entity:get_component('stonehearth:water')
end

function WaterSignalService:waterfall_component_modified(entity)
   self._changed_waterfalls[entity:get_id()] = entity:get_component('stonehearth:waterfall')
end

function WaterSignalService:add_next_tick_callback(cb, args)
   table.insert(self._next_tick_callbacks, {cb = cb, args = args})
end

function WaterSignalService:_on_tick()
   local signals_to_signal = {}
   local next_tick_callbacks
   if next(self._next_tick_callbacks) then
      next_tick_callbacks = self._next_tick_callbacks
      self._next_tick_callbacks = {}
   end

   if next(self._changed_waters) then
      for water_id, water in pairs(self._changed_waters) do
         local location = water:get_location()
         if location then
            local water_region = water:get_region():get():translated(location)
            for id, signal in pairs(self._sv.signals) do
               if signal.region and signal.signal:monitors_water() and water_region:intersects_region(signal.region) then
                  signals_to_signal[id] = signal
                  signal.waters[water_id] = true
               elseif signal.waters[water_id] ~= nil then
                  signals_to_signal[id] = signal
               end
            end
         end
      end
      self._changed_waters = {}
   end

   if next(self._changed_waterfalls) then
      for waterfall_id, waterfall in pairs(self._changed_waterfalls) do
         local location = waterfall:get_location()
         if location then
            local waterfall_region = waterfall:get_region():get():translated(location)
            for id, signal in pairs(self._sv.signals) do
               if signal.region and signal.signal:monitors_waterfall() and waterfall_region:intersects_region(signal.region) then
                  signals_to_signal[id] = signal
                  signal.waterfalls[waterfall_id] = true
               elseif signal.waterfalls[waterfall_id] ~= nil then
                  signals_to_signal[id] = signal
               end
            end
         end
      end
      self._changed_waterfalls = {}
   end

   for _, signal in pairs(signals_to_signal) do
      signal.signal:_on_tick_water_signal()

      for water_id, intersects in pairs(signal.waters) do
         if intersects then
            signal.waters[water_id] = false
         else
            signal.waters[water_id] = nil
         end
      end
      for water_id, intersects in pairs(signal.waterfalls) do
         if intersects then
            signal.waters[water_id] = false
         else
            signal.waters[water_id] = nil
         end
      end
   end

   if next_tick_callbacks then
      for _, cb_struct in ipairs(next_tick_callbacks) do
         cb_struct.cb(cb_struct.args)
      end
   end
end

return WaterSignalService
