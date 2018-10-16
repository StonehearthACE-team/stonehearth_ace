local LootTable = require 'stonehearth.lib.loot_table.loot_table'

--[[
   Used to determine what loot a mob drops when it dies.  This program is for
   dynamically spcifing loot drops on existing entities!  If you want to declare loot
   constantly, then use the stonehearth:destroyed_loot_table entity data.
]]

local AceLootDropsComponent = class()

-- the only thing we're changing for ACE is the "local auto_loot = " line
function AceLootDropsComponent:_on_kill_event()
   local loot_table = self._sv.loot_table or radiant.entities.get_json(self)
   if loot_table then
      local location = radiant.entities.get_world_grid_location(self._entity)
      if location then
         local auto_loot = stonehearth.client_state:get_client_gameplay_setting(self._sv.auto_loot_player_id, 'stonehearth', 'auto_loot', false)
         local town = stonehearth.town:get_town(self._sv.auto_loot_player_id)

         local items = LootTable(loot_table)
                           :roll_loot()
         local spawned_entities = radiant.entities.spawn_items(items, location, 1, 3, { owner = self._entity })

         --Add a loot command to each of the spawned items, or claim them automatically
         for id, entity in pairs(spawned_entities) do
            local target = entity
            local entity_forms = entity:get_component('stonehearth:entity_forms')
            if entity_forms then
               target = entity_forms:get_iconic_entity()
            end
            if self._sv.auto_loot_player_id and (loot_table.force_auto_loot or self._entity:get_player_id() == self._sv.auto_loot_player_id) then
               entity:set_player_id(self._sv.auto_loot_player_id)
               target:set_player_id(self._sv.auto_loot_player_id)
               stonehearth.inventory:get_inventory(self._sv.auto_loot_player_id)
                                       :add_item_if_not_full(entity)
            else
               local command_component = target:add_component('stonehearth:commands')
               command_component:add_command('stonehearth:commands:loot_item')
               if auto_loot and town then
                  town:loot_item(target)
               end
            end
         end
      end
   end
end

return AceLootDropsComponent
