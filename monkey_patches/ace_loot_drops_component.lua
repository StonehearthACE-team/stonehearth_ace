local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local util = require 'stonehearth_ace.lib.util'

--[[
   Used to determine what loot a mob drops when it dies.  This program is for
   dynamically spcifing loot drops on existing entities!  If you want to declare loot
   constantly, then use the stonehearth:destroyed_loot_table entity data.
]]

local AceLootDropsComponent = class()

local log = radiant.log.create_logger('loot_drops_component')

function AceLootDropsComponent:set_filter_script(filter_script, filter_args)
   self._sv._filter_script = filter_script
   self._sv._filter_args = filter_args
end

-- changed the "auto_loot = " line, also changed to use output system instead of just raw spawning items
function AceLootDropsComponent:_on_kill_event(e)
   log:debug('_on_kill_event: %s', e and radiant.util.table_tostring(e) or 'nil')
   if self._entity:get_component('stonehearth:pet') then
      return
   end
   local loot_table, filter_script, filter_args = self._sv.loot_table, self._sv._filter_script, self._sv._filter_args
   if not loot_table then
      loot_table = radiant.entities.get_json(self)
      if loot_table then
         filter_script = loot_table.filter_script
         filter_args = loot_table.filter_args
      end
   end

   if loot_table then
      local kill_data = e.kill_data or {}
      local location = kill_data.location or radiant.entities.get_world_grid_location(self._entity)
      if location then
         local player_id = radiant.entities.get_player_id(self._entity)
         local loot_player_id = kill_data.source or kill_data.source_id or self._sv.auto_loot_player_id
         if radiant.entities.is_entity(loot_player_id) then
            loot_player_id = radiant.entities.get_player_id(loot_player_id)
         end
         local auto_loot, force_auto_loot
         if loot_player_id then
            auto_loot = stonehearth.client_state:get_client_gameplay_setting(loot_player_id, 'stonehearth', 'auto_loot', false)
            force_auto_loot = loot_table.force_auto_loot or player_id == loot_player_id
         elseif loot_player_id == player_id then
            force_auto_loot = true
         end
         log:debug('%s dropping loot: %s, %s, %s, %s', self._entity, player_id, tostring(loot_player_id), tostring(auto_loot), tostring(force_auto_loot))
         local town = stonehearth.town:get_town(loot_player_id)

         local quality
         if loot_table.apply_entity_quality then
            quality = radiant.entities.get_item_quality(self._entity)
         end

         if filter_script and not filter_args then
            filter_args = util.get_current_conditions_loot_table_filter_args()
         end
         local items = LootTable(loot_table, quality, filter_script, filter_args)
                           :roll_loot()
         local options = {
            owner = force_auto_loot and loot_player_id or player_id,
            add_spilled_to_inventory = force_auto_loot,
            inputs = kill_data.source,
            output = self._entity,
            spill_fail_items = true,
         }
         local min_distance = loot_table.drop_range and loot_table.drop_range.min or 1
         local max_distance = loot_table.drop_range and loot_table.drop_range.max or 3
         local spawned_entities = radiant.entities.output_items(items, location, min_distance, max_distance, options).spilled

         --Add a loot command to each of the spawned items, or claim them automatically
         if not force_auto_loot then
            for id, entity in pairs(spawned_entities) do
               local target = entity
               local entity_forms = entity:get_component('stonehearth:entity_forms')
               if entity_forms then
                  target = entity_forms:get_iconic_entity() or target
               end

               -- make sure the item is in the world and hasn't been scooped up by something
               if radiant.entities.get_world_grid_location(target) then
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
end

return AceLootDropsComponent
