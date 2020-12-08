local AceShop = class()
local rng = _radiant.math.get_default_rng()

function AceShop:dump_escrow_at_location(location)
   if not radiant.entities.exists(self._sv.escrow_entity) then
      return false
   end

   local default_storage
   if not location then
      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         default_storage = town:get_default_storage()
         location = town:get_landing_location()
      end
      if not location then
         return false
      end
   end

   local escrow_storage_component = self._sv.escrow_entity:get_component('stonehearth:storage')
   local escrow_items = escrow_storage_component:get_items()
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   if escrow_items then
      local items = radiant.shallow_copy(escrow_items)
      for id, item in pairs(items) do
         if item and item:is_valid() then
            escrow_storage_component:remove_item(id)
            
            -- If the purchased "item" has AI, it's a pet. Remove it from the inventory and let it befriend a random townsperson.
            if item:get_component('stonehearth:ai') then
               items[id] = nil
               inventory:remove_item(id)
               local pet_component = item:add_component('stonehearth:pet')
               pet_component:convert_to_pet(self._sv.player_id)
               local citizens = stonehearth.population:get_population(self._sv.player_id):get_citizens()
               local citizen_ids = citizens:get_keys()
               local citizen_id = citizen_ids[rng:get_int(1, #citizen_ids)]
               pet_component:set_owner(citizens:get(citizen_id))
            end
         end
      end

      radiant.entities.output_spawned_items(items, location, 1, 7, nil, nil, default_storage, true)
   end
end

return AceShop
