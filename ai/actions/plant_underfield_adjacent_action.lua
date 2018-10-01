local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local PlantUnderfieldAdjacent = radiant.class()
PlantUnderfieldAdjacent.name = 'plant underfield adjacent'
PlantUnderfieldAdjacent.does = 'stonehearth_ace:plant_underfield_adjacent'
PlantUnderfieldAdjacent.args = {
   underfield_layer = Entity,      -- the field the undercrop is in
   location = Point3,         -- the offset of the undercrop in the underfield
}
PlantUnderfieldAdjacent.priority = 0

function PlantUnderfieldAdjacent:start_thinking(ai, entity, args)
   self._log = ai:get_log()
   self._entity = entity

   self._grower_underfield = args.underfield_layer:get_component('stonehearth_ace:grower_underfield_layer')
                                    :get_grower_underfield()
   if not self:_is_plantable_location(args.location) then
      self._log:detail('location either was not tilled or was already planted at %s', args.location)
      return
   end
   self._current_location_plantable = true

   self._origin = radiant.entities.get_world_grid_location(args.underfield_layer)
   self._location = args.location
   self._destination = args.underfield_layer:get_component('destination')

   ai:set_think_output()
end

function PlantUnderfieldAdjacent:_is_plantable_location(location)
   local substrate_data = self._grower_underfield:substrate_data_at(location)

   if not substrate_data or (substrate_data.contents and substrate_data.contents:is_valid()) then
      -- location either was not tilled or was already planted
      return false
   end
   return true
end

function PlantUnderfieldAdjacent:_run_till_animation(ai, entity)
   -- Till Once
   ai:execute('stonehearth:run_effect', { effect = 'hoe', facing_point = self._location })
   return true
end

function PlantUnderfieldAdjacent:run(ai, entity, args)
   self._log:detail('entering loop..')

   while self._current_location_plantable and self:_run_till_animation(ai, entity) and radiant.entities.exists_in_world(entity) do
      self:_plant_at_current_location()
      self:_unreserve_location()

      -- See if we can find another planable location
      self._log:detail('gimme more..')
      self:_move_to_next_available_till_location(ai, entity, args)
   end

   self._log:detail('exited loop..')
end

function PlantUnderfieldAdjacent:stop(ai, entity, args)
   self:_unreserve_location()
end

function PlantUnderfieldAdjacent:_plant_at_current_location()
   if self._location then
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:plant_undercrop', {undercrop_uri = self._grower_underfield:get_undercrop_details().uri})
      self._log:detail('Planted undercrop at location %s', tostring(self._location))
      self._grower_underfield:notify_plant_location_finished(self._location)
   end
end

function PlantUnderfieldAdjacent:_unreserve_location()
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

function PlantUnderfieldAdjacent:_move_to_next_available_till_location(ai, entity, args)
   self._location = nil
   self._current_location_plantable = false
   -- see if there's a path to an unbuilt block on the same entity within 8 voxels
   local path = entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another location to plant',
                                                     args.underfield_layer,
                                                     8)

   if path then
      local location = path:get_destination_point_of_interest()
      local reserved = self._destination:get_reserved()

      -- Does this location have substrate data?
      if not self:_is_plantable_location(location) then
         return
      elseif _physics:is_blocked(location, 0) then
         -- HACK: If the location is blocked, this would stall as it tries to plant the same location.
         --        Instead, mark it as reserved, and move on. That means the location will be unplantable
         --        until a reload, but that's better than stalling.
         reserved:modify(function(cursor)
               cursor:add_point(location - self._origin)
            end)
         return self:_move_to_next_available_till_location(ai, entity, args)
      end
      self._current_location_plantable = true

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

return PlantUnderfieldAdjacent
