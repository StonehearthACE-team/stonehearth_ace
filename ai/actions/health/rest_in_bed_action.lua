local RestInBed = radiant.class()

RestInBed.name = 'rest in bed'
RestInBed.does = 'stonehearth:rest_from_injuries'
RestInBed.args = {}
RestInBed.priority = 0

function RestInBed:start_thinking(ai, entity, args)
   -- Can only start thinking if we have a medic and that medic can attend to us
   local player_id = radiant.entities.get_player_id(entity)
   self._entity_id = entity:get_id()
   self._entity = entity
   self._ai = ai
   self._signaled = false
   self._started = false
   self._town = stonehearth.town:get_town(player_id)

   self._medic_listener = radiant.events.listen(self._town, 'stonehearth:town:medic_available', self, self._try_request_medic)
   self._medics_unavailable_listener = radiant.events.listen(self._entity, 'stonehearth:town:medic_unavailable', self, self._on_medics_unavailable)

   self:_try_request_medic()
end

function RestInBed:_on_medics_unavailable()
   if self._signaled then
      if not self._started then
         self._ai:clear_think_output()
      else
         self._ai:abort('Medics no longer available in town')
      end
      self._signaled = false
   end
end

function RestInBed:_try_request_medic()
   if not self._signaled and self._town:try_request_medic(self._entity) then
      self._signaled = true
      self._ai:set_think_output()
   end
end

function RestInBed:start(ai, entity, args)
   self._started = true
end

function RestInBed:stop_thinking(ai, entity, args)
   if self._started then
      self:_clear_listener()
   else
      self:destroy()
   end
end

function RestInBed:stop(ai, entity, args)
   self:destroy()
   self._started = false
end

function RestInBed:_clear_listener()
   if self._medic_listener then
      self._medic_listener:destroy()
      self._medic_listener = nil
   end
   if self._medics_unavailable_listener then
      self._medics_unavailable_listener:destroy()
      self._medics_unavailable_listener = nil
   end
end

function RestInBed:destroy()
   if self._town then
      self._town:unrequest_medic(self._entity_id)
   end
   self:_clear_listener()
end

function make_is_available_bed_filter()
   return stonehearth.ai:filter_from_key('stonehearth:rest_from_injuries:rest_in_bed', 'none', function(target)
         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data and not bed_data.priority_care then
            if not target:add_component('stonehearth:mount'):is_in_use() then
               return true
            end
         end
         return false
      end)
end

local ai = stonehearth.ai
return ai:create_compound_action(RestInBed)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:goto_entity_type', {
            filter_fn = make_is_available_bed_filter(),
            description = 'rest in bed'
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
         :execute('stonehearth:add_buff', {buff = 'stonehearth:buffs:bed_ridden', target = ai.ENTITY, immediate = false})
         :execute('stonehearth:rest_in_bed_adjacent', { bed = ai.BACK(2).entity })
