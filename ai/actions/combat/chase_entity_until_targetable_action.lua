-- not sure if/how to monkey-patch a compound action, so we're just overriding the whole thing :-\

local Entity = _radiant.om.Entity

local ChaseEntityUntilTargetable = radiant.class()

ChaseEntityUntilTargetable.name = 'chase entity until targetable'
ChaseEntityUntilTargetable.does = 'stonehearth:combat:chase_entity_until_targetable'
ChaseEntityUntilTargetable.args = {
   target = Entity
}
ChaseEntityUntilTargetable.priority = 0

local function is_entity_targetable(entity, target)
   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      return false
   end

   if not stonehearth.combat:in_range_and_has_line_of_sight(entity, target, weapon) then
      return false
   end

   if radiant.entities.is_standing_on_ladder(entity) then
      return false
   end

   return true
end

function ChaseEntityUntilTargetable:start_thinking(ai, entity, args)
   self._ready = false
   self._is_thinking = true
   
   -- Make sure any clear_think_outputs that might happen happen asynchronously.
   self._delay_start_timer = radiant.on_game_loop_once('ChaseEntityUntilTargetable start_thinking', function()
         self:_update_think_output(ai, entity, args)

         self._leash_changed_trace = radiant.events.listen(entity, 'stonehearth:combat_state:leash_changed', function()
               self:_update_think_output(ai, entity, args)
            end)
      end)
end

function ChaseEntityUntilTargetable:_update_think_output(ai, entity, args)
   if not self._is_thinking then
      return
   end

   local clear_think_output = function()
      if self._ready then
         ai:clear_think_output()
         self._ready = false
      end
   end

   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   -- ACE: Do not chase if very slow
   local attributes_comp = entity:get_component('stonehearth:attributes')
   local speed = attributes_comp and attributes_comp:get_attribute('speed')
   if speed and speed < 10 then
      clear_think_output()
      return
   end

   -- This action is not responsible for movement within a leash
   if stonehearth.combat:has_leash(entity) then
      clear_think_output()
      return
   end

   -- If the entity is suspended we don't want to waste any thought power
   if not args.target or not args.target:is_valid() or radiant.entities.is_entity_suspended(args.target) then
      clear_think_output()
      return
   end

   -- We only think if the target is not targetable.
   -- This prevents unnecessary pathfinding when we can already target/shoot the target.
   if stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
      clear_think_output()
      return
   end

   if not self._ready then
      self._ready = true
      ai:set_think_output()
   end
end

function ChaseEntityUntilTargetable:stop_thinking(ai, entity, args)
   self._is_thinking = false
   if self._leash_changed_trace then
      self._leash_changed_trace:destroy()
      self._leash_changed_trace = nil
   end
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(ChaseEntityUntilTargetable)
   :execute('stonehearth:chase_entity', {
      target = ai.ARGS.target,
      grid_location_changed_cb = is_entity_targetable,
   })
