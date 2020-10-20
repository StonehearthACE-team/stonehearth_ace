local RestInBed = radiant.class()

RestInBed.name = 'rest in bed'
RestInBed.does = 'stonehearth:rest_from_injuries'
RestInBed.args = {
   rest_from_conditions = {
      type = 'boolean',
      default = false
   }
}
RestInBed.priority = 0

local function make_bed_filter()
   return stonehearth.ai:filter_from_key('stonehearth:rest_from_injuries:rest_in_bed', 'none', function(target)
         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data and not target:add_component('stonehearth:mount'):is_in_use() then
            return true
         end
         return false
      end)
end

local function make_bed_rater()
   return function(target)
         -- rate priority care beds highest, then owned beds, then unowned beds, then anything else
         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data.priority_care then
            return 1
         else
            local ownable_component = target:get_component('stonehearth:ownable_object')
            local owner = ownable_component:get_owner()
            if not owner or not owner:is_valid() then
               return 0.5
            elseif owner:get_id() == self._entity_id then
               return 0.75
            else
               return 0
            end
         end
      end
end

function RestInBed:start_thinking(ai, entity, args)
   -- Can only start thinking if we have a medic and that medic can attend to us
   local player_id = radiant.entities.get_player_id(entity)
   self._player_id = player_id
   self._entity_id = entity:get_id()
   self._entity = entity
   self._ai = ai
   self._rest_from_conditions = args.rest_from_conditions
   self._signaled = false
   self._started = false
   self._town = stonehearth.town:get_town(player_id)

   self._medic_listener = radiant.events.listen(self._town, 'stonehearth:town:medic_available', self, self._try_request_medic)
   self._medics_unavailable_listener = radiant.events.listen(self._entity, 'stonehearth:town:medic_unavailable', self, self._on_medics_unavailable)

   if self._rest_from_conditions then
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory then
         self._tracker = inventory:add_item_tracker('stonehearth_ace:healing_item_tracker')
         self._medicine_available_listener = radiant.events.listen(self._tracker, 'stonehearth:inventory_tracker:item_added', self, self._on_medicine_available)
      end
   end

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

function RestInBed:_on_medicine_available(e)
   if not self._signaled then
      local id = e.key
      if id then
         local tracking_data = self._tracker:get_tracking_data()
         local item = tracking_data:contains(id) and tracking_data:get(id)
         if item and item:is_valid() and self._town:is_healing_item_valid(item, self._entity) then
            -- we just did the rest from conditions check, so we can bypass the town doing it
            self:_try_request_medic(true)
         end
      end
   end
end

function RestInBed:_try_request_medic(bypass_rest_from_conditions_check)
   local do_rest_from_conditions_check = not bypass_rest_from_conditions_check and self._rest_from_conditions
   if not self._signaled and self._town:try_request_medic(self._entity, do_rest_from_conditions_check) then
      self._signaled = true
      self._ai:set_think_output({
         filter_fn = make_bed_filter(),
         rating_fn = make_bed_rater(),
         description = 'find bed to rest in',
         owner_player_id = self._player_id,
      })
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
   if self._medicine_available_listener then
      self._medicine_available_listener:destroy()
      self._medicine_available_listener = nil
   end
end

function RestInBed:destroy()
   self:_clear_listener()
   if self._town then
      self._town:unrequest_medic(self._entity_id)
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(RestInBed)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).filter_fn,
            rating_fn = ai.BACK(2).rating_fn,
            description = ai.BACK(2).description,
            owner_player_id = ai.BACK(2).owner_player_id,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(3).item })
         :execute('stonehearth:add_buff', {buff = 'stonehearth:buffs:bed_ridden', target = ai.ENTITY, immediate = false})
         :execute('stonehearth:rest_in_bed_adjacent', { bed = ai.BACK(2).entity })
