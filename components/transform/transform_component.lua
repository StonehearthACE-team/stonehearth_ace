--[[
   transform data can be specified overall or for individual options, indexed by keys (e.g., for multiple different commands):
   "entity_data": {
      "stonehearth_ace:transform_data": {
         "command": "...",
         "transform_effect": "...",
         "transform_script": "..."
      }
   }
   -- or --
   "entity_data": {
      "stonehearth_ace:transform_data": {
         "default_key": "key1",
         "transform_options": {
            "key1": {
               "command": "...",
               "transform_effect": "...",
               "transform_script": "..."
            },
            "key2": {
               "command": "...",
               "transform_effect": "...",
               "transform_script": "..."
            }
         }
      }
   }
]]

local transform_lib = require 'stonehearth_ace.lib.transform.transform_lib'
local log = radiant.log.create_logger('transform')
local LootTable = require 'stonehearth.lib.loot_table.loot_table'

local TransformComponent = class()

function TransformComponent:initialize()
   self._sv.option_overrides = {}
end

function TransformComponent:restore()
   self._is_restore = true
end

function TransformComponent:activate()
   self._all_transform_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:transform_data')
end

function TransformComponent:post_activate()
   if self._is_restore then
      self:_set_transform_option(self._sv.transform_key or self._all_transform_data.default_key, self._sv.option_overrides)
   else
      self:set_transform_option(self._sv.transform_key or self._all_transform_data.default_key)
   end
end

function TransformComponent:destroy()
   self:_destroy_effect()
   self:_destroy_progress()
   self:_destroy_request_listeners()
end

function TransformComponent:_create_request_listeners()
   self:_destroy_request_listeners()
   
   if self._transform_data and self._transform_data.request_action then
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

function TransformComponent:_destroy_progress()
   if self._sv.progress then
      self._sv.progress:destroy()
      self._sv.progress = nil
      self.__saved_variables:mark_changed()
   end
end

function TransformComponent:get_progress()
   return self._sv.progress
end

function TransformComponent:get_transform_key()
   return self._sv.transform_key
end

function TransformComponent:get_transform_options()
   if self._transform_data then
      local options = {}
      radiant.util.merge_into_table(options, self._transform_data)
      radiant.util.merge_into_table(options, self._sv.option_overrides)
      return options
   end
end

function TransformComponent:set_transform_option(key)
   self._sv.transform_key = key
   self.__saved_variables:mark_changed()

   self:_set_transform_option(key)
end

function TransformComponent:_set_transform_option(key, overrides)
   if key and self._all_transform_data.transform_options and self._all_transform_data.transform_options[key] then
      self._transform_data = self._all_transform_data.transform_options[key]
   elseif not self._all_transform_data.transform_options then
      self._transform_data = self._all_transform_data
   else
      self._transform_data = nil
   end

   self._sv.option_overrides = {}
   if overrides then
      self:add_option_overrides(overrides)
   end

   self:_create_request_listeners()
   self:_set_up_commands()
end

function TransformComponent:_set_up_commands()
   -- if there's a transform_command, add that command
   local options = self._all_transform_data.transform_options or { default = self._all_transform_data }
   for key, options in pairs(options) do
      if options.command then
         local command_comp = self._entity:add_component('stonehearth:commands')
         if not command_comp:has_command(options.command) then
            command_comp:add_command(options.command)
         end
      end
   end
end

function TransformComponent:add_option_overrides(overrides)
   radiant.util.merge_into_table(self._sv.option_overrides, overrides)
   self.__saved_variables:mark_changed()
end

function TransformComponent:transform()
   local options = {
      check_script = self._transform_data.transform_check_script,
      transform_effect = self._transform_data.transform_effect,
      auto_harvest = self._transform_data.auto_harvest,
      transform_script = self._transform_data.transform_script,
      kill_entity = self._transform_data.kill_entity,
		model_variant = self._transform_data.model_variant,
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
         -- If someone had already requested to transform, just cancel the request and exit out
         self:cancel_craft_order()
         return false
      end

      self:request_craft_order()
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
   
   if not self._sv.progress then
      self._sv.progress = radiant.create_controller('stonehearth_ace:progress_tracker', self._entity)
      self.__saved_variables:mark_changed()
   end

   local max_progress
   local duration
   if data.transforming_effect_duration then
      duration = stonehearth.calendar:parse_duration(data.transforming_effect_duration, true)
      self._sv.progress:set_max_progress(100)
      self._sv.progress:start_time_tracking(duration / 100, 1)
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

-- for whatever ingredient is required and auto-crafted for the transformation, so that it can be modified/canceled
function TransformComponent:request_craft_order()
   local player_id = radiant.entities.get_player_id(self._entity)
   local ingredient = self._transform_data and self._transform_data.transform_ingredient_auto_craft and self._transform_data.transform_ingredient_uri
   if ingredient and stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth', 'building_auto_queue_crafters', true) then
      local player_jobs = stonehearth.job:get_jobs_controller(player_id)
      local order = player_jobs:request_craft_product(ingredient, 1)
      self:set_craft_order(order)
   end
end

function TransformComponent:set_craft_order(order)
   if order then
      self._sv.craft_order_id = order:get_id()
      self._sv.craft_order_list = order:get_order_list()
      self.__saved_variables:mark_changed()
   end
end

function TransformComponent:cancel_craft_order()
   local order_id = self._sv.craft_order_id
   local order_list = self._sv.craft_order_list
   if order_id and order_list then
      order_list:remove_order(order_id, 1)
   end
   self._sv.craft_order_id = nil
   self._sv.craft_order_list = nil
   self.__saved_variables:mark_changed()
end

return TransformComponent
