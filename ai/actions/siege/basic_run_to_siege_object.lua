-- Entities with siege breaking abilities will look for siege objects to kill when they are not in combat (or doing something with higher priority)
local RunToSiege = radiant.class()
RunToSiege.name = 'run to siege object'
RunToSiege.does = 'stonehearth:combat'
RunToSiege.args = {}
RunToSiege.priority = 0.02

function RunToSiege:start_thinking(ai, entity, args)
   local assaulting = stonehearth.combat:get_assaulting(self._entity)
   local defending = stonehearth.combat:get_defending(self._entity)
   if assaulting or defending then
      return -- don't interrupt if entity is in combat
   end

   local player_id = radiant.entities.get_player_id(entity)
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:run_to_siege', player_id, function(item)
         local is_hostile = stonehearth.player:are_entities_hostile(entity, item)
         if not is_hostile then
            return false
         end
         local entity_data = radiant.entities.get_entity_data(item, 'stonehearth:siege_object')
         local attributes_component = item:get_component('stonehearth:attributes')
         if not entity_data or not attributes_component then
            return false -- not a siege object
         end
         local health = radiant.entities.get_health(item)
         return health and health > 0 -- is it killable
      end)

   ai:set_think_output({ filter_fn = filter_fn })
end

local ai = stonehearth.ai
return ai:create_compound_action(RunToSiege)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:find_path_to_entity_type', {
            filter_fn = ai.BACK(2).filter_fn,
            description = 'find a siege object to run to',
         })
         :execute('stonehearth:follow_path', {
            path = ai.BACK(1).path,
         })
         :execute('stonehearth:combat:attack_siege_object', {
            target = ai.BACK(2).destination
         })
