--[[
   using the connection service, detect when there are adjacent entities of the same type
   automatically change model variant and rotation to fit position
   since manual rotations could cause issues, use a renderer to set that
]]

local log = radiant.log.create_logger('tile')

local TileComponent = class()

local _rotations = {
   ['z+'] = 0,
   ['x+z+'] = 0,
   ['x-'] = 90,
   ['x-z+'] = 90,
   ['z-'] = 180,
   ['x-z-'] = 180,
   ['x+'] = 270,
   ['x+z-'] = 270
}

local _cardinal_directions = {
   ['x-'] = true,
   ['x+'] = true,
   ['z-'] = true,
   ['z+'] = true
}
local _diagonal_directions = {
   ['x-z-'] = true,
   ['x-z+'] = true,
   ['x+z-'] = true,
   ['x+z+'] = true
}
local _opposite_directions = {
   ['x-'] = 'x+',
   ['x+'] = 'x-',
   ['z-'] = 'z+',
   ['z+'] = 'z-'
}
local _opposite_corner = {
   ['x-z-'] = 'x+z+',
   ['z-x-'] = 'x+z+',
   ['x-z+'] = 'x+z-',
   ['z+x-'] = 'x+z-',
   ['x+z-'] = 'x-z+',
   ['z-x+'] = 'x-z+',
   ['x+z+'] = 'x-z-',
   ['z+x+'] = 'x-z-'
}
local _adjacent_corners = {
   ['x-'] = {clock = 'x-z-', counter = 'x-z+'},
   ['x+'] = {clock = 'x+z+', counter = 'x+z-'},
   ['z-'] = {clock = 'x+z-', counter = 'x-z-'},
   ['z+'] = {clock = 'x-z+', counter = 'x+z+'}
}

function TileComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._sv.connection_type = json.connection_type
   self._sv.rotation = 0
   self._sv.proper_rotation = 0
end

function TileComponent:post_activate()
   local conn_comp = self._entity:get_component('stonehearth_ace:connection')
   if conn_comp then
      self._connection_data_trace = conn_comp:trace_data('tile')
         :on_changed(function()
            self:_update()
         end)
   end
end

function TileComponent:destroy()
   if self._connection_data_trace then
      self._connection_data_trace:destroy()
      self._connection_data_trace = nil
   end
end

function TileComponent:_update()
   local render_info = self._entity:get_component('render_info')
   local type = self._sv.connection_type
   local data = type and self._entity:get_component('stonehearth_ace:connection'):get_connected_stats(type)
   data = data and data[type]
   
   -- based on the number of connections, we can narrow down our model
   -- then we can determine proper rotation based on which connectors are connected
   -- finally, adjust the rotation based on the facing of the entity
   -- (since changing the rotation manually will result in a change in connections, this will always get processed after such a change)

   if not data or data.num_connections == 0 then
      render_info:set_model_variant('default')
      self._sv.proper_rotation = 0
      self._sv.rotation = 0
      self.__saved_variables:mark_changed()
      return
   end
   
   local cardinal, diagonal = self:_get_connected_connectors(data.connectors)
   local cardinal_keys = radiant.keys(cardinal)
   local diagonal_keys = radiant.keys(diagonal)

   if #cardinal_keys == 1 then   -- 1 total option
      -- if there's only one cardinal connection, it's a simple end point
      render_info:set_model_variant('end_point')
      self._sv.proper_rotation = _rotations[cardinal_keys[1]]
   elseif #cardinal_keys == 2 then  -- 3 total options
      -- if there are two cardinal connections, it can either be a straight piece (with opposites) or an angle
      -- if it's an angle, check for the concave diagonal corner
      if string.sub(cardinal_keys[1], 1, 1) == string.sub(cardinal_keys[2], 1, 1) then
         render_info:set_model_variant('straight')
         self._sv.proper_rotation = _rotations[cardinal_keys[1]]
      else
         local corner = cardinal_keys[1] .. cardinal_keys[2]
         local opposite = _opposite_corner[corner]
         local opp_opp = _opposite_corner[opposite]
         if diagonal[opp_opp] then
            render_info:set_model_variant('corner_concave_open')
         else
            render_info:set_model_variant('corner_concave_closed')
         end
         -- do opposite of opposite so it doesn't matter what order the cardinal keys were processed
         self._sv.proper_rotation = _rotations[opp_opp]
         log:debug('corner %s, opposite %s, diagonals %s', corner, opposite, radiant.util.table_tostring(diagonal))
      end
   elseif #cardinal_keys == 3 then  -- 4 total options
      -- if there are three cardinal connections, it's a T, but there are 0-2 diagonals that affect it
      -- get side that's not connected
      local off_side
      for side, _ in pairs(_cardinal_directions) do
         if not cardinal[side] then
            off_side = side
            break
         end
      end
      local opposite = _opposite_directions[off_side]
      local adj_corners = _adjacent_corners[off_side]
      local adj_2_clock = _opposite_corner[adj_corners.clock]
      local adj_2_counter = _opposite_corner[adj_corners.counter]

      if diagonal[adj_2_clock] and diagonal[adj_2_counter] then
         render_info:set_model_variant('edge_open')
      elseif diagonal[adj_2_clock] then
         render_info:set_model_variant('edge_closed_clock')
      elseif diagonal[adj_2_counter] then
         render_info:set_model_variant('edge_closed_counter')
      else
         render_info:set_model_variant('edge_closed_both')
      end
      self._sv.proper_rotation = _rotations[opposite]
   elseif #cardinal_keys == 4 then  -- 6 total options
      -- if all four cardinals are connected, 0,1,2,3,4 diagonals result in 1,1,2,1,1 different models
      if #diagonal_keys == 0 then
         render_info:set_model_variant('center_closed_all')
         self._sv.proper_rotation = 0
      elseif #diagonal_keys == 1 then
         render_info:set_model_variant('center_closed_three')
         self._sv.proper_rotation = _rotations[diagonal_keys[1]]
      elseif #diagonal_keys == 2 then
         local adj_side
         for side, corners in pairs(_adjacent_corners) do
            if diagonal[corners.clock] and diagonal[corners.counter] then
               adj_side = side
               break
            end
         end

         if adj_side then
            render_info:set_model_variant('center_closed_adjacent')
            self._sv.proper_rotation = _rotations[_opposite_directions[adj_side]]
         else
            render_info:set_model_variant('center_closed_opposite')
            self._sv.proper_rotation = _rotations[diagonal_keys[1]]
         end
      elseif #diagonal_keys == 3 then
         local off_corner
         for corner, _ in pairs(_diagonal_directions) do
            if not diagonal[corner] then
               off_corner = corner
               break
            end
         end
         
         render_info:set_model_variant('center_closed_one')
         self._sv.proper_rotation = _rotations[off_corner]
      elseif #diagonal_keys == 4 then
         render_info:set_model_variant('center_open')
         self._sv.proper_rotation = 0
      end
   end

   local facing = radiant.entities.get_facing(self._entity)
   local rotation = (360 - self._sv.proper_rotation + facing) % 360
   self._sv.rotation = rotation
   self.__saved_variables:mark_changed()
end

function TileComponent:_get_connected_connectors(connectors)
   local cardinal = {}
   local diagonal = {}

   for name, conn in pairs(connectors) do
      if conn.num_connections > 0 then
         if _cardinal_directions[name] then
            cardinal[name] = true
         elseif _diagonal_directions[name] then
            diagonal[name] = true
         end
      end
   end

   return cardinal, diagonal
end

return TileComponent