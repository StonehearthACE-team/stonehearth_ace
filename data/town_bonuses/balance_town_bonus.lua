local BalanceTownBonus = class()

local ROAD_URI = 'stonehearth:build:prototypes:road'
local ROAD2_URI = 'stonehearth:build2:entities:road_blueprint' 
local STRUCTURE_URI = 'stonehearth:build2:entities:structure'

function BalanceTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'Banner of Cunning'
   self._sv.description = '<i>This settlement will be a bustling hub of trade.</i><ul><li>Roads give 3x their normal speed boost</li><li>Your items sell for 50% more</li><li>Traders will bring 2x the goods and Gold</li></ul>'
end

function BalanceTownBonus:activate()
   -- Upgrade new roads when they are created.
   radiant.events.listen(radiant, 'radiant:entity:post_create', function(e)
         -- New builder structures don't become roads until next frame. -_-
         local entity = e.entity
         radiant.on_game_loop_once('running road detector', function()
               if entity:is_valid() then
                  self:_process_entity_if_its_a_road(entity)
               end
            end)
      end)
end

function BalanceTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function BalanceTownBonus:initialize_bonus()
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

function BalanceTownBonus:apply_trader_gold_bonus(base_gold)
   return base_gold * 2
end

function BalanceTownBonus:apply_trader_quantity_bonus(quantity)
   return quantity * 2
end

function BalanceTownBonus:apply_sell_price_bonus(price)
   return price * 1.5
end

function BalanceTownBonus:apply_road_speed_bonus(speed)
   return speed * 3
end

function BalanceTownBonus:_process_entity_if_its_a_road(entity)
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

function BalanceTownBonus:_set_movement_modifier(movement_modifier, base_mm_data)
   movement_modifier:set_modifier(self:apply_road_speed_bonus(base_mm_data.modifier))
   movement_modifier:set_nav_preference_modifier(self:apply_road_speed_bonus(base_mm_data.nav_preference_modifier))
end

return BalanceTownBonus
