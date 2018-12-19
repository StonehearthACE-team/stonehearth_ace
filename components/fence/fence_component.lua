--[[
   using the connection service, detect when there are close entities of the same type
   automatically change model variant and rotation to fit position
   also specify joiner models
   since manual rotations could cause issues, use a renderer to set that
]]

local ConnectionUtils = require 'lib.connection.connection_utils'
local log = radiant.log.create_logger('fence')

local FenceComponent = class()

local import_region = ConnectionUtils.import_region

local _rotations = {
   ['x-'] = 180,
   ['z+'] = 270,
   ['x+'] = 0,
   ['z-'] = 90
}

function FenceComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._connection_type = json.connection_type
   self._thresholds = {}
   for _, threshold in pairs(json.thresholds or {}) do
      table.insert(self._thresholds, {
         threshold = threshold.threshold,
         model = threshold.model,
         collision_region = import_region(threshold.collision_region)
      })
   end
   table.sort(self._thresholds, function(a, b) return a.threshold > b.threshold end)
   self._sv.joiners = {}
end

function FenceComponent:post_activate()
   local conn_comp = self._entity:get_component('stonehearth_ace:connection')
   if conn_comp then
      self._connection_data_trace = conn_comp:trace_data('fence')
         :on_changed(function()
            self:_update()
         end)
   end
end

function FenceComponent:destroy()
   if self._connection_data_trace then
      self._connection_data_trace:destroy()
      self._connection_data_trace = nil
   end
end

function FenceComponent:_update()
   local type = self._connection_type
   local data = type and self._entity:get_component('stonehearth_ace:connection'):get_connected_stats(type)
   data = data and data[type]
   
   self._sv.joiners = {}
   local joiners = {}

   if data and data.num_connections > 0 then
      for name, conn in pairs(data.connectors) do
         local rotation = _rotations[name]
         if rotation and conn.num_connections > 0 then
            local info = conn.connected_to[next(conn.connected_to)]
            local threshold_info = self:_get_joiner(info.threshold)
            if threshold_info then
               table.insert(joiners, {rotation = rotation, model = threshold_info.model, collision_region = threshold_info.collision_region})
            end
         end
      end
   end

   local mod_comp = self._entity:add_component('stonehearth_ace:entity_modification')
   mod_comp:reset_region3('region_collision_shape')
   for _, joiner in ipairs(joiners) do
      local origin = self._entity:add_component('mob'):get_region_origin()
      local rotation = joiner.rotation
      local region = joiner.collision_region:translated(-origin):rotated(rotation):translated(origin)
      mod_comp:set_region3('region_collision_shape', region, true)
      table.insert(self._sv.joiners, {rotation = joiner.rotation, model = joiner.model})
   end
   
   self.__saved_variables:mark_changed()
end

function FenceComponent:_get_joiner(threshold)
   for _, info in ipairs(self._thresholds) do
      if threshold >= info.threshold then
         return info
      end
   end
end

return FenceComponent