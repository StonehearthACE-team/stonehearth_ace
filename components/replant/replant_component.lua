local Point3 = _radiant.csg.Point3

local ReplantComponent = class()

function ReplantComponent:activate()
   self._replant_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:replant_data')
   if self._replant_data then
      self._on_harvest_listener = radiant.events.listen(self._entity, 'stonehearth:kill_event', function(args)
            self:_replant(args.kill_data and args.kill_data.source_id)
            self._on_harvest_listener = nil
         end)
      self._original_rotation = radiant.entities.get_facing(self._entity) or 0
   end
end

function ReplantComponent:destroy()
   if self._on_harvest_listener then
      self._on_harvest_listener:destroy()
      self._on_harvest_listener = nil
   end
end

function ReplantComponent:_replant(killer_player_id)
   --Create the entity and put it on the ground
   if not self._replant_data.seed_alias then
      return
   else
      local location = radiant.entities.get_world_grid_location(self._entity)
      local parent = radiant.entities.get_parent(self._entity)
      if location and parent and radiant.terrain.is_standable(self._entity, location) then -- make sure location is valid
         local placement_info = {
               location = location,
               normal = Point3(0, 1, 0),
               rotation = self._original_rotation,
               structure = parent,
            }
         local town = stonehearth.town:get_town(killer_player_id)
         town:place_item_type(self._replant_data.seed_alias, nil, placement_info)
      end
   end
end

return ReplantComponent