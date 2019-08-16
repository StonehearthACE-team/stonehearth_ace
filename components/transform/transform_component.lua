local transform_lib = require 'stonehearth_ace.lib.transform.transform_lib'
local log = radiant.log.create_logger('transform')
local LootTable = require 'stonehearth.lib.loot_table.loot_table'

local TransformComponent = class()

function TransformComponent:activate()
   self._transform_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:transform_data')
   self:_create_request_listeners()
end

function TransformComponent:post_activate()
   -- if there's a transform_command, add that command
   if self._transform_data.command then
      local command_comp = self._entity:add_component('stonehearth:commands')
      if not command_comp:has_command(self._transform_data.command) then
         command_comp:add_command(self._transform_data.command)
      end
   end
end

function TransformComponent:destroy()
   self:_destroy_effect()
   self:_destroy_request_listeners()
end

function TransformComponent:_create_request_listeners()
   self:_destroy_request_listeners()
   
   if self._transform_data.request_action then
      if self._transform_data.auto_request then
         self._added_to_world_listener = self._entity:add_component('mob'):trace_parent('transform entity added or removed')
            :on_changed(function(parent)
               if parent then
                  self:request_transform(self._entity:get_player_id())
               end
            end)
      end
   end
end

function TransformComponent:_destroy_request_listeners()
   if self._added_to_world_listener then
      self._added_to_world_listener:destroy()
      self._added_to_world_listener = nil
   end
end

function TransformComponent:transform()
   local options = {
      check_script = self._transform_data.transform_check_script,
      transform_effect = self._transform_data.transform_effect,
      auto_harvest = self._transform_data.auto_harvest,
      transform_script = self._transform_data.transform_script,
      kill_entity = self._transform_data.kill_entity,
      destroy_entity = self._transform_data.destroy_entity,
      transform_event = function(transformed_form)
         radiant.events.trigger(self._entity, 'stonehearth_ace:on_transformed', {entity = self._entity, transformed_form = transformed_form})
      end
   }
   local transformed = transform_lib.transform(self._entity, 'stonehearth_ace:transform', self._transform_data.transform_uri, options)

   if not transformed then
      -- if we failed, cancel the requested transform action, if there was one
      if self._transform_data.request_action then
         self._entity:add_component('stonehearth:task_tracker'):cancel_current_task(false)
      end
   end

   return transformed
end

function TransformComponent:request_transform(player_id)
   local data = self._transform_data
   if not data then
      return false
   end

   -- probably shouldn't have to check this because the command should already filter with "visible_to_all_players"
   if data.check_owner and not radiant.entities.is_neutral_animal(self._entity:get_player_id())
      and radiant.entities.is_owned_by_another_player(self._entity, player_id) then
      return false
   end

   if data.request_action then
      local task_tracker_component = self._entity:add_component('stonehearth:task_tracker')
      local was_requested = task_tracker_component:is_activity_requested(data.request_action)

      task_tracker_component:cancel_current_task(false) -- cancel current task first and force the transform request

      if was_requested then
         return false -- If someone had already requested to transform, just cancel the request and exit out
      end

      local category = 'transform'  --data.category or 
      local success = task_tracker_component:request_task(player_id, category, data.request_action, data.request_action_overlay_effect)
      return success
   else
      self:perform_transform(true)
      return true
   end
end

-- this function gets called directly by request_transform unless a request_action is specified
-- if such an action is specified, this function should be called as part of that AI action
function TransformComponent:perform_transform(use_finish_cb)
   local data = self._transform_data
   if not data then
      return false
   end

   if data.transforming_effect then
      self:_run_effect(data.transforming_effect, use_finish_cb)
   elseif not data.transforming_worker_effect then
      self:transform()
   end
end

function TransformComponent:_run_effect(effect, use_finish_cb)
   if not self._effect then
      self._effect = radiant.effects.run_effect(self._entity, effect)
      if use_finish_cb then
         self._effect:set_finished_cb(function()
               self:_destroy_effect()
               self:transform()
            end)
      end
   end
end

function TransformComponent:_destroy_effect()
   if self._effect then
      self._effect:set_finished_cb(nil)
                  :stop()
      self._effect = nil
   end
end

--[[
function TransformComponent:_refresh_attention_effect()
   local data = self._transform_data
   if not data or not data.request_action then
      return
   end
   
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   local needs_effect = not task_tracker_component or not task_tracker_component:has_any_task()
   local has_effect = self._attention_effect ~= nil
   if needs_effect ~= has_effect then
      if needs_effect then
         self._attention_effect = radiant.effects.run_effect(self._entity, 'stonehearth_ace:effects:transform_action_available_overlay_effect',
               nil, nil, { playerColor = radiant.entities.get_player_color(self._entity) })
      else
         self._attention_effect:stop()
         self._attention_effect = nil
      end
   end
end
]]

function TransformComponent:_place_additional_items(owner, collect_location)
   local data = self._transform_data
   if not data.additional_items then
      return {}
   end
   local loot_table = nil
   if data.additional_items then
      loot_table = LootTable(data.additional_items)
   end
   local spawned_items
   if loot_table then
      spawned_items = radiant.entities.spawn_items(loot_table:roll_loot(), collect_location, 1, 3, { owner = owner })
   else
      spawned_items = {}
   end

   return spawned_items
end

function TransformComponent:spawn_additional_items(transforming_worker, collect_location, owner_player_id)
   local spawned_resources = self:_place_additional_items(transforming_worker, collect_location)
   local player_id = owner_player_id or (transforming_worker and radiant.entities.get_player_id(transforming_worker))
   if transforming_worker then
      for id, item in pairs(spawned_resources) do
         -- add it to the inventory of the owner
         stonehearth.inventory:get_inventory(player_id)
                                 :add_item_if_not_full(item)

      end
   end
end

return TransformComponent
