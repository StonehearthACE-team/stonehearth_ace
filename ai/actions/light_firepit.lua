--[[
   Task that represents a worker bringing a piece of wood to a firepit and setting it on fire.
]]
FirepitComponent  = require 'components.firepit.firepit_component'

local LightFirepit = radiant.class()
LightFirepit.name = 'light fire'
LightFirepit.does = 'stonehearth:light_firepit'
LightFirepit.args = {
   firepit = FirepitComponent, -- the firepit component of the entity to light
}
LightFirepit.priority = 0

function LightFirepit:start(ai, entity, args)
   ai:set_status_text_key('stonehearth:ai.actions.status_text.light_firepit', { target = args.firepit:get_entity() })
end

local _rating_fn = function(item)
   if radiant.entities.is_material(item, 'preferred_ingredient') then
      return 1
   end

   return 0
end

local ai = stonehearth.ai
return ai:create_compound_action(LightFirepit)
            :execute('stonehearth:abort_on_event_triggered', {
               source = ai.ENTITY,
               event_name = 'stonehearth:work_order:haul:work_player_id_changed',
            })
            :execute('stonehearth:pickup_item_made_of', {
               material = ai.ARGS.firepit:get_fuel_material(),
					rating_fn = _rating_fn,
               owner_player_id = ai.CALL(radiant.entities.get_work_player_id, ai.ENTITY)
            })
            :execute('stonehearth:drop_carrying_into_entity', { entity = ai.ARGS.firepit:get_entity() })
            :execute('stonehearth:call_function', { fn = ai.ARGS.firepit._retrieve_charcoal, args = { ai.ARGS.firepit } })
            :execute('stonehearth:run_effect', { effect = 'light_fire' })
            :execute('stonehearth:call_function', { fn = ai.ARGS.firepit.light, args = { ai.ARGS.firepit } })
