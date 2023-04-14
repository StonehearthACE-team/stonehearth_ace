local Point3 = _radiant.csg.Point3

local AceGhostFormComponent = class()

function AceGhostFormComponent:can_iconic_be_used(uri)
   local placement_info = self._sv.placement_info
   if placement_info then
      if uri == placement_info.iconic_uri then
         return true
      end
      if not placement_info.require_exact then
         local alternates = radiant.entities.get_alternate_uris(placement_info.iconic_uri)
         return alternates and alternates[uri]
      end
   end

   return false
end

function AceGhostFormComponent:is_building_fixture()
   return self._sv.placement_info and self._sv.placement_info.owner_bid ~= nil
end

-- split town placement task requests into "build" and normal
function AceGhostFormComponent:_remove_from_town()
   if not self._sv.placement_info then
      return
   end
   local player_id = radiant.entities.get_player_id(self._entity)
   local inventory = stonehearth.inventory:get_inventory(player_id)
   if inventory and self._added_to_town then
      inventory:update_placeable_items_placed(self._root_entity_uri, self._sv.quality, -1)
      self._added_to_town = nil
   end

   if self._sv._limited_registration_tag then
      local town = stonehearth.town:get_town(player_id)
      if town then
         town:unregister_limited_placement_item(self._entity, self._sv._limited_registration_tag)
         local is_place_item_type = self:is_place_item_type()
         if is_place_item_type then
            local placement_tag = self:_get_placement_tag()
            if self:is_building_fixture() then
               town:unrequest_build_placement_task(self._sv.placement_info.iconic_uri, self._sv.quality, false, placement_tag)
            else
               town:unrequest_placement_task(self._sv.placement_info.iconic_uri, self._sv.quality, false, placement_tag)
            end
         end
      end
   end
end

function AceGhostFormComponent:_add_to_town(moving_placed_item)
   if not self._sv.placement_info then
      return
   end
   local player_id = radiant.entities.get_player_id(self._entity)
   local inventory = stonehearth.inventory:get_inventory(player_id)
   local is_place_item_type = self:is_place_item_type()
   if is_place_item_type and inventory then
      self._added_to_town = inventory:update_placeable_items_placed(self._root_entity_uri, self._sv.quality, 1)
   end

   local dst = self._entity:add_component('destination')
   if not dst:get_region() then
      dst:set_region(_radiant.sim.alloc_region3())
      dst:get_region():modify(function(cursor)
            cursor:add_point(Point3.zero)
         end)
      dst:set_auto_update_adjacent(true)
   end

   local town = stonehearth.town:get_town(player_id)
   if town and not moving_placed_item then -- only register items that aren't being moved, to avoid duplicate counts
      if self._root_entity_uri then
         local limit_data = radiant.entities.get_entity_data(self._root_entity_uri, 'stonehearth:item_placement_limit')
         if limit_data then
            self._sv._limited_registration_tag = limit_data.tag
            town:register_limited_placement_item(self._entity, limit_data.tag)
         end
      end
      if is_place_item_type then
         local placement_tag = self:_get_placement_tag()
         if self:is_building_fixture() then
            town:request_build_placement_task(self._sv.placement_info.iconic_uri, self._sv.quality, false, placement_tag)
         else
            town:request_placement_task(self._sv.placement_info.iconic_uri, self._sv.quality, false, placement_tag)
         end
      end
   end
end

function AceGhostFormComponent:_get_placement_tag()
   local placement_data = self._root_entity_uri and radiant.entities.get_entity_data(self._root_entity_uri, 'stonehearth:placement')
   return placement_data and placement_data.tag
end

return AceGhostFormComponent
