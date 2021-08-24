local SitOnChair = radiant.class()

SitOnChair.name = 'sit on chair'
SitOnChair.does = 'stonehearth:sit_on_chair'
SitOnChair.args = {}
SitOnChair.priority = 0

function make_is_available_chair_fn(ai_entity)
   local player_id = ai_entity:get_player_id()

   return stonehearth.ai:filter_from_key('stonehearth:sit_on_chair', player_id, function(target)
         if target:get_player_id() ~= player_id then
            return false
         end

         if radiant.entities.get_entity_data(target, 'stonehearth:chair') then
            -- make sure it's not currently being targeted for a task
            local task_tracker = target:get_component('stonehearth:task_tracker')
            if task_tracker and task_tracker:get_task_player_id() == player_id then
               return false
            end
            
            if not target:add_component('stonehearth:mount'):is_in_use() then
               return true
            end
         end
         return false
      end)
end

local ai = stonehearth.ai
return ai:create_compound_action(SitOnChair)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.CALL(make_is_available_chair_fn, ai.ENTITY),
            description = 'sit on chair'
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
         :execute('stonehearth:sit_on_chair_adjacent', { chair = ai.PREV.entity })
