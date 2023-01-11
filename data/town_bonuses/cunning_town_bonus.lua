local CunningTownBonus = class()

local ROAD_URI = 'stonehearth:build:prototypes:road'
local ROAD2_URI = 'stonehearth:build2:entities:road_blueprint' 
local STRUCTURE_URI = 'stonehearth:build2:entities:structure'

function CunningTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'i18n(stonehearth:entities.gizmos.town_banner_guardian.town_banner_guardian_ghost.display_name)'
   self._sv.description = 'i18n(stonehearth:entities.gizmos.town_banner_guardian.town_banner_guardian_ghost.town_bonus_description)'

   self._json = radiant.resources.load_json('stonehearth_ace:data:town_bonuses:cunning')
   self._trader_gold_mult = self._json.trader_gold_mult or 1
   self._trader_gold_add = self._json.trader_gold_add or 0
   self._trader_quantity_mult = self._json.trader_quantity_mult or 1
   self._trader_quantity_add = self._json.trader_quantity_add or 0
   self._sell_price_mult = self._json.sell_price_mult or 1
   self._sell_price_add = self._json.sell_price_add or 0
   self._road_speed_mult = self._json.road_speed_mult or 1
   self._road_speed_add = self._json.road_speed_add or 0
   self._merchant_cooldown_mult = self._json.merchant_cooldown_mult or 1
   self._merchant_cooldown_add = self._json.merchant_cooldown_add or 0
end

function CunningTownBonus:activate()
   -- Upgrade new roads when they are created.
   radiant.events.listen(radiant, 'radiant:entity:post_create', function(e)
         -- New builder structures don't become roads until next frame. -_-
         local entity = e.entity
         radiant.on_game_loop_once('unning road detector', function()
               self:_process_entity_if_its_a_road(entity)
            end)
      end)
end

function CunningTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function CunningTownBonus:initialize_bonus()
   -- Recompute item sell prices.
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   inventory:recompute_item_tracker('stonehearth:sellable_item_tracker')

   -- Update all roads with a faster movement speed modifier.
   -- Find all growing things owned by this player and restart their growing so they use the bonus.
   -- This is slow, but only happens once a playthrough, so whatever.
   for _, entity in pairs(_radiant.sim.get_all_entities()) do
      self:_process_entity_if_its_a_road(entity)
   end
end

function CunningTownBonus:apply_trader_gold_bonus(base_gold)
   return base_gold * self._trader_gold_mult + self._trader_gold_add
end

function CunningTownBonus:apply_trader_quantity_bonus(quantity)
   return quantity * self._trader_quantity_mult + self._trader_quantity_add
end

function CunningTownBonus:apply_sell_price_bonus(price)
   return price * self._sell_price_mult + self._sell_price_add
end

function CunningTownBonus:apply_road_speed_bonus(speed)
   return speed * self._road_speed_mult + self._road_speed_add
end

--new ACE bonus
function CunningTownBonus:apply_merchant_cooldown_bonus(cooldown)
   return cooldown * self._merchant_cooldown_mult + self._merchant_cooldown_add
end

function CunningTownBonus:_process_entity_if_its_a_road(entity)
   if self._sv.player_id == entity:get_player_id() and entity:get_uri() == ROAD_URI then
      local base_mm_data = radiant.entities.get_component_data(ROAD_URI, 'movement_modifier_shape')
      local movement_modifier = entity:get_component('movement_modifier_shape')  --currently 0.2 (road.json)
      self:_set_movement_modifier(movement_modifier, base_mm_data)
   elseif self._sv.player_id == entity:get_player_id() and entity:get_uri() == STRUCTURE_URI then
      local structure = entity:get_component('stonehearth:build2:structure')
      if structure:is_road() then
         local base_mm_data = radiant.entities.get_entity_data(ROAD2_URI, 'movement_modifier_shape')
         local movement_modifier = entity:get_component('movement_modifier_shape')  --currently 0.2 (road.json)
         self:_set_movement_modifier(movement_modifier, base_mm_data)
      end
   end
end

function CunningTownBonus:_set_movement_modifier(movement_modifier, base_mm_data)
   movement_modifier:set_modifier(self:apply_road_speed_bonus(base_mm_data.modifier))
   movement_modifier:set_nav_preference_modifier(self:apply_road_speed_bonus(base_mm_data.nav_preference_modifier))
end

return CunningTownBonus
