local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local TillUnderfieldAdjacent = radiant.class()
TillUnderfieldAdjacent.name = 'till underfield adjacent'
TillUnderfieldAdjacent.does = 'stonehearth_ace:till_underfield_adjacent'
TillUnderfieldAdjacent.args = {
   underfield_layer = Entity,      -- the field to till
   location = Point3,           -- the offset of the location to till in the field
}
TillUnderfieldAdjacent.priority = 0

function TillUnderfieldAdjacent:start_thinking(ai, entity, args)
   self._log = ai:get_log()
   self._entity = entity

   self._grower_underfield = args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer')
                                    :get_grower_underfield()
   local substrate_data = self._grower_underfield:substrate_data_at(args.location)

   if substrate_data then
      self._log:detail('location already tilled at %s', offset)
      return
   end
   self._current_location_tillable = true

   self._origin = radiant.entities.get_world_grid_location(args.underfield_layer)
   self._location = args.location
   self._destination = args.underfield_layer:get_component('destination')

   ai:set_think_output()
end

function TillUnderfieldAdjacent:_run_till_animation(ai, entity)
   -- Till Once
   ai:execute('stonehearth:run_effect', { effect = 'hoe', facing_point = self._location })
   return true
end

function TillUnderfieldAdjacent:run(ai, entity, args)
   self._log:detail('entering loop..')

   while self._current_location_tillable and self:_run_till_animation(ai, entity) do
      self:_till_current_location()
      self:_unreserve_location()

      -- woot!  see if we can find another tillable location
      self._log:detail('gimme more..')
      self:_move_to_next_available_till_location(ai, entity, args)
   end

   self._log:detail('exited loop..')
end

function TillUnderfieldAdjacent:stop(ai, entity, args)
   self:_unreserve_location()
end

function TillUnderfieldAdjacent:_till_current_location()
   if self._location then
      self._log:detail('Tilled location %s', tostring(self._location))
      self._grower_underfield:notify_till_location_finished(self._location)
   end
end

function TillUnderfieldAdjacent:_unreserve_location()
   if self._location then
      if self._destination:is_valid() then
         local block = self._location - self._origin
         self._destination:get_reserved():modify(function(cursor)
            cursor:subtract_point(block)
         end)
      end
      self._location = nil
   end
end

function TillUnderfieldAdjacent:_move_to_next_available_till_location(ai, entity, args)
   self._location = nil
   self._current_location_tillable = false
   -- see if there's a path to an unbuilt block on the same entity within 8 voxels
   local path = entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another location to till',
                                                     args.underfield_layer,
                                                     8)

   if path then
      local location = path:get_destination_point_of_interest()
      local reserved = self._destination:get_reserved()

      -- Does this location have substrate data?
      local substrate_data = args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer')
                                 :get_grower_underfield()
                                    :substrate_data_at(location)
      if substrate_data then
         return
      end
      self._current_location_tillable = true

      -- reserve the substrate_plot so no one else grabs it
      local block = location - self._origin
      reserved:modify(function(cursor)
            cursor:add_point(block)
         end)

      -- remember the location so we can unreserve it later
      self._location = location

      -- follow the path.  this may go away for a while (which is why we had to reserve the
      -- block a few lines ago!)
      ai:execute('stonehearth:follow_path', { path = path })
   end
end

return TillUnderfieldAdjacent
