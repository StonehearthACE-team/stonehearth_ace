local RestInBedTrivial = radiant.class()

RestInBedTrivial.name = 'rest in bed trivial'
RestInBedTrivial.does = 'stonehearth:rest_from_injuries'
RestInBedTrivial.args = {}
RestInBedTrivial.priority = 1.0

function RestInBedTrivial:start_thinking(ai, entity, args)
   local parent = radiant.entities.get_parent(entity)
   if not parent then
      return
   end

   if radiant.entities.get_entity_data(parent, 'stonehearth:bed') then
      -- hey, we're already in bed!
      local bed = parent
      local mount_component = bed:add_component('stonehearth:mount')
      if mount_component:is_in_use() then
         assert(mount_component:get_user() == entity)
      end

      ai:set_think_output({ bed = bed })
   end
end

function RestInBedTrivial:start(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)
   self._town = stonehearth.town:get_town(player_id)
   self._town:force_request_medic(entity)
end

function RestInBedTrivial:stop(ai, entity, args)
   if self._town then
      self._town:unrequest_medic(entity:get_id())
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(RestInBedTrivial)
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.bed })
         :execute('stonehearth:add_buff', {buff = 'stonehearth:buffs:bed_ridden', target = ai.ENTITY, immediate = false})
         :execute('stonehearth:rest_in_current_bed', { bed = ai.BACK(3).bed })
