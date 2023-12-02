local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AcePlayerMarketStall = class()

function AcePlayerMarketStall:sell_items_to_player(to_player_id, item_uri_to_sell, quality, quantity)
   local storage = self._entity:get_component('stonehearth:storage')
   local target_town = stonehearth.town:get_town(to_player_id)
   local target_drop_origin = target_town:get_landing_location()
   local item_catalog_data = stonehearth.catalog.get_catalog_data(stonehearth.catalog, item_uri_to_sell)

   if not item_catalog_data then
      return false
   end

   if not target_drop_origin then
      return false
   end

   local player_id = radiant.entities.get_player_id(self._entity)
   local from_inventory = stonehearth.inventory:get_inventory(player_id)
   local is_boosted = self:_is_value_booster_in_range(from_inventory)
   local item_cost = self:_calculate_item_cost(item_uri_to_sell, quality, is_boosted)

   local to_inventory = stonehearth.inventory:get_inventory(to_player_id)
   local gold = to_inventory:get_gold_count()
   local buy_quantity = math.min(quantity or 1, math.floor(gold / item_cost))

   if buy_quantity <= 0 then
      return false
   end

   local item_list = {}
   local item_count = 0
   for id, item in pairs(storage:get_items()) do
      local item_uri = item:get_uri()
      local item_root_entity = entity_forms_lib.get_root_entity(item) or item
      local item_quality = radiant.entities.get_item_quality(item_root_entity)

      if item_uri == item_uri_to_sell and item_quality == quality then
         item_count = item_count + 1
         item_list[id] = item

         if item_count >= buy_quantity then
            break
         end
      end
   end

   if item_count <= 0 then
      return false
   end

   local total_cost = item_cost * item_count
   to_inventory:subtract_gold(total_cost)
   from_inventory:add_gold(total_cost)

   for _, entity in pairs(item_list) do
      from_inventory:remove_item(entity:get_id())
      to_inventory:add_item(entity)

      stonehearth.ai:reconsider_entity(entity, 'entity was purchased from a stockpile')
   end

   local default_storage = target_town:get_default_storage()
   local options = {
      inputs = default_storage,
      spill_fail_items = true,
      require_matching_filter_override = true,
   }
   radiant.entities.output_spawned_items(item_list, target_drop_origin, 1, 5, options)

   stonehearth.ai:reconsider_entity(self._entity, 'purchased item was removed from storage')
   return true
end

function AcePlayerMarketStall:sell_next_items(max_quantity)
   local storage = self._entity:get_component('stonehearth:storage')

   local item_list = {}
   local item_count = 0
   for id, item in pairs(storage:get_items()) do
      item_count = item_count + 1
      item_list[item_count] = item

      if item_count >= max_quantity then
         break
      end
   end

   if item_count <= 0 then
      return false
   end

   local player_id = radiant.entities.get_player_id(self._entity)
   local from_inventory = stonehearth.inventory:get_inventory(player_id)
   local is_boosted = self:_is_value_booster_in_range(from_inventory)

   for _, entity in ipairs(item_list) do
      local quality = radiant.entities.get_item_quality(entity)
      local item_cost = self:_calculate_item_cost(entity:get_uri(), quality, is_boosted)

      from_inventory:remove_item(entity:get_id())
      from_inventory:add_gold(item_cost)
      radiant.effects.run_effect(self._entity, 'stonehearth:effects:poof_sell_effect:small')
      radiant.entities.destroy_entity(entity)
   end

   stonehearth.ai:reconsider_entity(self._entity, 'purchased item was removed from storage')
   return true
end

function AcePlayerMarketStall:_calculate_item_cost(item_uri, quality, is_boosted)
   local item_catalog_data = stonehearth.catalog.get_catalog_data(stonehearth.catalog, item_uri)
   local item_cost = radiant.entities.apply_item_quality_bonus('net_worth', item_catalog_data.net_worth, quality)

   if is_boosted then
      item_cost = item_cost * (1 + stonehearth.constants.traveler.VALUE_BOOSTER_BOOST)
   end

   return math.floor(item_cost + 0.5) or 1
end

function AcePlayerMarketStall:_is_value_booster_in_range(from_inventory)
   if from_inventory then
      for uri, active in pairs(stonehearth.constants.traveler.VALUE_BOOSTER_URIS) do
		   local matching = active and from_inventory:get_items_of_type(uri)
         if matching and matching.items then
            for _, booster in pairs(matching.items) do
               if radiant.entities.distance_between_entities(booster, self._entity) < stonehearth.constants.traveler.VALUE_BOOSTER_RANGE then
                  return true
               end
            end
         end
      end
	end
end

return AcePlayerMarketStall
