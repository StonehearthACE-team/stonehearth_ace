local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local MarketStallComponent = class()

function MarketStallComponent:initialize()
   self._sv._occupied = nil
   self._sv.merchant = nil
   self._sv.reenable_timer = nil
end

function MarketStallComponent:create()
   self._sv._is_open = false
end

function MarketStallComponent:post_activate()
   local shop_commands = self._entity:get_component('stonehearth:commands')

   if self._sv.reenable_timer then
      shop_commands:set_command_enabled('stonehearth:commands:trigger_trader_encounter', false)
   end
end

-- Function added just so market stalls still work like default until this is done. TODO: REMOVE ME
function MarketStallComponent:trigger_trader_encounter()
   local game_master = stonehearth.game_master:get_game_master(radiant.entities.get_player_id(self._entity))
   radiant.events.trigger(game_master, 'stonehearth:trigger_trader_encounter')

   local shop_commands = self._entity:get_component('stonehearth:commands')
   shop_commands:set_command_enabled('stonehearth:commands:trigger_trader_encounter', false)
   
   self._sv.reenable_timer = stonehearth.calendar:set_persistent_timer(
      'Enable call trader command', stonehearth.constants.shop.TRIGGER_TRADER_ENCOUNTER_COOLDOWN, radiant.bind(self, '_enable_call'))
end

-- Function added just so market stalls still work like default until this is done. TODO: REMOVE ME
function MarketStallComponent:_enable_call()
   local shop_commands = self._entity:get_component('stonehearth:commands')
   shop_commands:set_command_enabled('stonehearth:commands:trigger_trader_encounter', true)
   if self._sv.reenable_timer then
      self._sv.reenable_timer:destroy()
      self._sv.reenable_timer = nil
   end
end

function MarketStallComponent:occupy(merchant_id)
   self._sv._occupied = true
	self._entity:get_component('render_info'):set_model_variant(merchant_id or "default_merchant")
   self:create_merchant(merchant_id)
end

function MarketStallComponent:create_merchant(merchant_id)
   local stall_location = Point3(radiant.entities.get_world_grid_location(self._entity))
   local merchant_location = (Point3(stall_location.x + 4, stall_location.y, stall_location.z + 4))
   local standable = radiant.terrain.is_standable(merchant_location)
   if standable then
      local merchant_info = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:merchant_data') and radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:merchant_data').merchant_id or nil
      local merchant_entity = merchant_info and merchant_info.entity or "stonehearth_ace:npc:trader:male"
      local merchant_model_variant = merchant_info and merchant_info.model_variant or "default"
      self._sv.merchant = radiant.entities.create_entity(merchant_entity, { owner = self._entity })
      self._sv.merchant:get_component('render_info'):set_model_variant(merchant_model_variant)
      radiant.terrain.place_entity_at_exact_location(self._sv.merchant, merchant_location)
   end
end

function MarketStallComponent:remove_merchant()
	self._entity:get_component('render_info'):set_model_variant("default")
   radiant.effects.run_effect(self._sv.merchant, 'stonehearth:effects:spawn_entity')
   self._sv.merchant:destroy()   
   self._sv._occupied = false
end

function MarketStallComponent:destroy()
   if self._sv.merchant then
      self._sv.merchant:destroy()
      self._sv.merchant = nil
   end

   if self._sv.reenable_timer then
      self._sv.reenable_timer:destroy()
      self._sv.reenable_timer = nil
   end
end

return MarketStallComponent