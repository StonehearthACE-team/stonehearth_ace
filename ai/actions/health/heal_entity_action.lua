local HealEntity = radiant.class()

HealEntity.name = 'heal entity'
HealEntity.status_text_key = 'stonehearth:ai.actions.status_text.healing'
HealEntity.does = 'stonehearth:healing'
HealEntity.args = {}
HealEntity.priority = 0

local MIN_GUTS_PERCENTAGE_TO_PREFER = 90

local function make_is_healable_entity_filter(player_id)
   return stonehearth.ai:filter_from_key('stonehearth:healing:heal_entity', player_id, function(target)
         if target:get_player_id() ~= player_id then
            return false
         end

         if not radiant.entities.has_buff(target, 'stonehearth:buffs:hidden:needs_medical_attention') then
            return false
         end

         if radiant.entities.has_buff(target, 'stonehearth:buffs:recently_treated') then
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

function HealEntity:start_thinking(ai, entity, args)
   ai:set_think_output({
      filter_healable_entity = make_is_healable_entity_filter(entity:get_player_id())
   })
end

local ai = stonehearth.ai
return ai:create_compound_action(HealEntity)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_healable_entity,
            rating_fn = rate_healable_entity,
            description = 'find healable entity',
            ignore_leases = true,
         })
         :execute('stonehearth:get_mounted_item', {
            entity = ai.PREV.item,
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(3).filter_healable_entity,
            item = ai.BACK(2).item,
         })
         :execute('stonehearth_ace:pickup_healing_item', {
            target = ai.BACK(3).item
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(4).item
         })
         :execute('stonehearth:goto_entity', {
            entity = ai.BACK(4).mount
         })
         :execute('stonehearth:heal_entity_adjacent', {
            container = ai.BACK(5).mount,
            item = ai.BACK(3).item
         })
