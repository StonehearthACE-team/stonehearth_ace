local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('interaction_proxy')

local InteractionProxyComponent = class()

function InteractionProxyComponent:initialize()
   self._destination = self._entity:add_component('destination')
end

function InteractionProxyComponent:create()
   self._destination
      :set_region(_radiant.sim.alloc_region3())
      :set_auto_update_adjacent(true)
end

function InteractionProxyComponent:activate()
   self:_setup()
end

function InteractionProxyComponent:destroy()
   self:_destroy_traces()
end

function InteractionProxyComponent:_destroy_traces()
   if self._pre_destroy_trace then
      self._pre_destroy_trace:destroy()
      self._pre_destroy_trace = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._collision_trace then
      self._collision_trace:destroy()
      self._collision_trace = nil
   end
   if self._destination_trace then
      self._destination_trace:destroy()
      self._destination_trace = nil
   end
   self._sv._entity = nil
end

function InteractionProxyComponent:get_entity()
   return self._sv._entity
end

function InteractionProxyComponent:set_entity(entity)
   self:_destroy_traces()
   
   self._sv._entity = entity
   radiant.entities.set_player_id(self._sv._entity, entity:get_player_id())

   self:_setup()
end

function InteractionProxyComponent:_setup()
   -- ensure destination/adjacency region match up with traced collision region
   local entity = self._sv._entity
   if entity and entity:is_valid() then
      self._pre_destroy_trace = radiant.events.listen(entity, 'radiant:entity:pre_destroy', function()
            radiant.entities.destroy_entity(self._entity)
         end)
      
      local mob = entity:add_component('mob')
      self._entity:add_component('mob'):set_region_origin(mob:get_region_origin())
      self._parent_trace = mob:trace_parent('interaction proxy component')
         :on_changed(function(parent)
               self:_on_parent_changed(parent)
            end)
         :push_object_state()

      local rcs = entity:get_component('region_collision_shape')
      local cur_rcs, cur_dest
      if rcs then
         local region = rcs:get_region()
         self._collision_trace = region:trace('interaction proxy')
            :on_changed(function()
                  self:_update_destination(region:get(), nil)
               end)
         cur_rcs = region:get()
      end

      local destination = entity:get_component('destination')
      if destination then
         local region = destination:get_region()
         self._destination_trace = region:trace('interaction proxy')
            :on_changed(function()
                  self:_update_destination(nil, region:get())
               end)
         cur_dest = region:get()
      end

      if cur_rcs or cur_dest then
         self:_update_destination(cur_rcs, cur_dest)
      end
   end
end

function InteractionProxyComponent:_update_destination(rcs_region, dest_region)
   self._cur_rcs_region = rcs_region or self._cur_rcs_region
   self._cur_dest_region = dest_region or self._cur_dest_region
   local region = Region3()
   if rcs_region then
      region:add_region(rcs_region)
   end
   if dest_region then
      region:add_region(dest_region)
   end

   self._destination:get_region():modify(function(cursor)
         cursor:copy_region(region)
      end)
end

function InteractionProxyComponent:_on_parent_changed(parent)
   local entity = self._sv._entity
   local this_parent = radiant.entities.get_parent(self._entity)

   if entity and entity:is_valid() and parent ~= this_parent then
      --log:debug('%s parent changed to %s (from %s)', entity, parent, tostring(this_parent))

      if this_parent then
         log:debug('removing %s from %s', self._entity, this_parent)
         radiant.entities.remove_child(this_parent, self._entity)
      end

      if parent then
         local location = radiant.entities.get_location(entity)
         local facing = radiant.entities.get_facing(entity)

         log:debug('placing %s on %s at %s (%s)', self._entity, parent, location, facing)

         local options = {
            root_entity = parent,
            facing = facing,
         }
         radiant.terrain.place_entity_at_exact_location(self._entity, location, options)
      end
   end
end

return InteractionProxyComponent
