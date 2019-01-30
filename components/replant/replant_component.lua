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
   if not (self._replant_data.seed_alias or self._replant_data.sapling_alias) then
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
         -- check if there's a sapling specified and prioritize that if there are any in inventory
         if self._replant_data.sapling_alias and self:_can_place_more(killer_player_id, self._replant_data.sapling_alias) then
            town:place_item_type(self._replant_data.sapling_alias, nil, placement_info)
         elseif self._replant_data.seed_alias then
            town:place_item_type(self._replant_data.seed_alias, nil, placement_info)
         end
      end
   end
end

-- copied from PlaceItemCallHandler
function ReplantComponent:_can_place_more(player_id, entity_uri)
   local inventory = stonehearth.inventory:get_inventory(player_id)
   local more_items = false
   if inventory then
      for _, entity_tracking_data in ipairs(inventory:get_placeable_items_of_type(entity_uri)) do
         local total_count = entity_tracking_data.count
         local placed = entity_tracking_data.num_placements_requested or 0
         local remaining = total_count - placed

         if remaining > 0 then
            return true
         end
      end
   end
   return false
end

return ReplantComponent