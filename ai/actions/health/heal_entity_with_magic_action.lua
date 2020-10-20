local HealEntityWithMagic = radiant.class()

HealEntityWithMagic.name = 'magically heal entity'
HealEntityWithMagic.status_text_key = 'stonehearth:ai.actions.status_text.healing'
HealEntityWithMagic.does = 'stonehearth:healing'
HealEntityWithMagic.args = {}
HealEntityWithMagic.priority = 1

local MIN_GUTS_PERCENTAGE_TO_PREFER = 90

local function make_is_healable_entity_filter(player_id)
   return stonehearth.ai:filter_from_key('stonehearth_ace:healing:heal_entity_with_magic', player_id, function(target)
         if target:get_player_id() ~= player_id then
            return false
         end

         if not radiant.entities.has_buff(target, 'stonehearth:buffs:hidden:needs_medical_attention') then
            return false
         end

         if radiant.entities.has_buff(target, 'stonehearth_ace:buffs:recently_magically_treated') then
            return false
         end
         local mount = radiant.entities.get_parent(target)
         local mount_component = mount and mount:get_component('stonehearth:mount')
         if not mount_component or mount_component:get_user() ~= target then
            return false
         end
   
         return true
      end)
end

local function rate_healable_entity(target)
   local species = radiant.entities.get_entity_data(target, 'stonehearth:species', false)
   local is_hearthling = species and species.id == 'hearthling'
   local is_pet = target:get_component('stonehearth:pet') ~= nil

   local score
   if is_hearthling then
      -- Prefer hearthlings who would probably be revived by this healing.
      local resources = target:get_component('stonehearth:expendable_resources')
      local will_revive = resources:get_percentage('guts') >= MIN_GUTS_PERCENTAGE_TO_PREFER
      
      -- Prefer higher level hearthlings.
      local level_score = 0
      local job_component = target:get_component('stonehearth:job')
      if job_component then
         level_score = job_component:get_normalized_level_score()
      end

      if will_revive then
         score = 0.7 + level_score * 0.3
      else
         score = 0.2 + level_score * 0.55
      end
   elseif is_pet then
      -- Prefer pets over other animals.
      -- TODO: Pets should get needs_medical_attention at some point.
      score = 0.1
   else
      -- Probably a pasture animal.
      score = 0
   end

   return score
end

function HealEntityWithMagic:start_thinking(ai, entity, args)
   self._ready = false

   local set_ready = function(ready)
         if ready ~= self._ready then
            self._ready = ready
            if ready then
               local player_id = radiant.entities.get_work_player_id(entity)
               ai:set_think_output({
                  filter_healable_entity = make_is_healable_entity_filter(player_id)
               })
            else
               ai:clear_think_output()
            end
         end
      end

   local check_cooldown = function()
         local combat_state = entity:add_component('stonehearth:combat_state')
         local cooldown = combat_state:get_cooldown_end_time('stonehearth_ace:magic_medic')
         if cooldown then
            local duration = cooldown - radiant.gamestate.now()
            self._cooldown_timer = stonehearth.combat:set_timer('stonehearth_ace:magic_medic cooldown', duration, function() set_ready(true) end)
         end
         set_ready(not cooldown)
      end

   -- do we even have any magical medical capabilities?
   local check_medic_capabilities
   check_medic_capabilities = function(capabilities)
         self:_destroy_cooldown_timer()   
         if capabilities then
            check_cooldown()
         else
            self._medic_capabilities_changed_listener = radiant.events.listen(entity, 'stonehearth_ace:medic_capabilities_changed', check_medic_capabilities)
         end
      end

   local job = entity:get_component('stonehearth:job')
   local medic_capabilities = job and job:get_curr_job_controller():get_medic_capabilities()
   check_medic_capabilities(medic_capabilities)
end

function HealEntityWithMagic:stop_thinking(ai, entity, args)
   self:_destroy_timers()
end

function HealEntityWithMagic:_destroy_timers()
   self:_destroy_cooldown_timer()
   self:_destroy_medic_capabilities_changed_listener()
end

function HealEntityWithMagic:_destroy_cooldown_timer()
   if self._cooldown_timer then
      self._cooldown_timer:destroy()
      self._cooldown_timer = nil
   end
end

function HealEntityWithMagic:_destroy_medic_capabilities_changed_listener()
   if self._medic_capabilities_changed_listener then
      self._medic_capabilities_changed_listener:destroy()
      self._medic_capabilities_changed_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(HealEntityWithMagic)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).filter_healable_entity,
            rating_fn = rate_healable_entity,
            description = 'find healable entity',
            ignore_leases = true,
         })
         :execute('stonehearth:get_mounted_item', {
            entity = ai.PREV.item,
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).filter_healable_entity,
            item = ai.BACK(2).item,
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(3).item
         })
         :execute('stonehearth:goto_entity', {
            entity = ai.BACK(3).mount
         })
         :execute('stonehearth_ace:heal_entity_adjacent_with_magic', {
            container = ai.BACK(4).mount
         })
