local Entity = _radiant.om.Entity

local ConsumeDrink = class()
ConsumeDrink.name = 'consume drink'
ConsumeDrink.does = 'stonehearth_ace:consume_drink'
ConsumeDrink.args = {
   drink = Entity,
}
ConsumeDrink.priority = 0

local log = radiant.log.create_logger('consume_drink_action')

function ConsumeDrink:run(ai, entity, args)
   local drink = args.drink

   self._drink_data = self:_get_drink_data(drink, entity)
   if not self._drink_data then
      ai:abort(string.format('Cannot consume drink: No drink data for %s.', tostring(drink)))
   end

   ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.consume_drink', { target = drink })
	
	local effect_loops = self._drink_data.effect_loops or 2

   local quality_component = drink:get_component("stonehearth:item_quality")
   local quality = (quality_component and quality_component:get_quality()) or stonehearth.constants.item_quality.NONE
   if quality > stonehearth.constants.item_quality.NORMAL then
      effect_loops = math.max(1, effect_loops - (quality-1) ) 
   end

   local drink_effect = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink').drinking_effect or 'sitting_drink'
   ai:execute('stonehearth:run_effect', {
      effect = drink_effect,
      times = effect_loops
   })

   entity:get_component('stonehearth:consumption'):consume_drink(args.drink)

   local appeal_component = entity:get_component('stonehearth:appeal')
   if appeal_component then
      appeal_component:add_dining_appeal_thought()
   end
   
   ai:unprotect_argument(args.drink)
   radiant.entities.destroy_entity(args.drink)
   self._drink_data = nil
end

function ConsumeDrink:stop(ai, entity, args)
   self._drink_data = nil
end

function ConsumeDrink:_get_drink_data(drink, entity)
   local drink_entity_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink')
   local drink_data

   if drink_entity_data then
      local posture = radiant.entities.get_posture(entity)
      drink_data = drink_entity_data[posture]

      if not drink_data then
         drink_data = drink_entity_data.default
      end
   end
   
   return drink_data
end

return ConsumeDrink
