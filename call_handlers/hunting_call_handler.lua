local validator = radiant.validator

local HuntingCallHandler = class()

function HuntingCallHandler:allow_hunting_for_entity(session, response, entity, enable)
   validator.expect_argument_types({'Entity'}, entity)
   validator.expect.matching_player_id(session.player_id, entity)
   
   local commands = entity:add_component('stonehearth:commands')

   if enable then
      entity:add_component('stonehearth:buffs'):remove_buff('stonehearth_ace:buffs:avoid_hunting', true)
      commands:remove_command('stonehearth_ace:commands:allow_hunting')
      commands:add_command('stonehearth_ace:commands:avoid_hunting')
   else
      entity:add_component('stonehearth:buffs'):add_buff('stonehearth_ace:buffs:avoid_hunting')
      commands:remove_command('stonehearth_ace:commands:avoid_hunting')
      commands:add_command('stonehearth_ace:commands:allow_hunting')
   end

   -- this forces the entity to reconsider finding a target
   radiant.events.trigger_async(entity, 'stonehearth_ace:avoid_hunting_changed')
   local aggro_observer = entity:add_component('stonehearth:observers'):get_observer('stonehearth:observers:aggro')
   if aggro_observer then
      aggro_observer:reconsider_all_targets()
   end
end

return HuntingCallHandler