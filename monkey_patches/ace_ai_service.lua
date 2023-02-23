local AceAiService = class()

function AceAiService:reconsider_entity(entity, reason, reconsider_parent)
   if not entity or not entity:is_valid() then
      return
   end

   self:_add_reconsidered_entity(entity, reason)

   -- if the thing we're reconsidering resides in non-stockpile storage, we also need to reconsider
   -- the storage too (otherwise the pathfinder looking to take things out of storage
   -- won't know to look again).  it is obnoxious how expensive this is.  consider adding
   -- `container_for` to stonehearth.inventory (implemented with a single, global map) -- tony

   local player_id = radiant.entities.get_player_id(entity)
   if player_id then
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory then
         local container = inventory:container_for(entity)
         if container then
            local is_stockpile = container:get_component('stoneheath:stockpile')
            if not is_stockpile then
               -- ACE: also inform that container that it should remove the reconsidered entity from its storage filter caches
               local storage_comp = container:get_component('stonehearth:storage')
               if storage_comp then
                  storage_comp:reconsider_entity_in_filter_caches(entity:get_id(), entity)
               end
               self:_add_reconsidered_entity(container, reason .. '(also triggering container)')
            end
         end
      end
   end

   if reconsider_parent then
      local parent = radiant.entities.get_parent(entity)
      if parent and parent:get_id() ~= radiant._root_entity_id then
         self:_add_reconsidered_entity(parent, reason .. '(reconsider_parent)')
      end
   end
end

return AceAiService
