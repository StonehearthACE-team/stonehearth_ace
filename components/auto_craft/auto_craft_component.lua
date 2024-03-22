--[[
   TODO:
      - handle player id changing
      - handle active craft order getting canceled
      - handle active craft order recipe enabled status changing
      - quest storage needs to be a separate entity, because its storages are added to entity_container
      - have craft order query auto_craft component to check ingredients of quest storage
]]

local constants = require 'stonehearth.constants'
local crafting_lib = require 'stonehearth_ace.lib.crafting.crafting_lib'
local MIN_INGREDIENT_BUFFER_MULTIPLIER = constants.auto_crafting.MIN_INGREDIENT_BUFFER_MULTIPLIER
local MAX_INGREDIENT_BUFFER_MULTIPLIER = constants.auto_crafting.MAX_INGREDIENT_BUFFER_MULTIPLIER

local AutoCraftComponent = class()
local log = radiant.log.create_logger('auto_craft_component')

function AutoCraftComponent:initialize()
   self._sv.enabled_recipes = {}
   self._sv.ingredient_buffer_multiplier = 1
   self._craft_order_listeners = {}
end

function AutoCraftComponent:restore()
   self._is_restore = true
end

function AutoCraftComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   -- self._entity:add_component('stonehearth:crafter')
   -- self._entity:add_component('stonehearth_ace:input')
   -- self._entity:add_component('stonehearth_ace:output')

   -- TODO: handle a changing player id
   self._player_id = radiant.entities.get_player_id(self._entity)
   self:_build_enabled_recipes_lookup()
end

function AutoCraftComponent:post_activate()
   local siblings_comp = self._entity:get_component('stonehearth_ace:sibling_entities')
   self._ingredient_storage = siblings_comp:get_sibling('ingredient_storage')
   self._output_storage = siblings_comp:get_sibling('output_storage')

   if self._ingredient_storage then
      self._storage_item_added_listener = radiant.events.listen(self._ingredient_storage, 'stonehearth_ace:quest_storage:item_added', self, self._on_storage_item_added)
      self._sv.ingredient_tracker = self._ingredient_storage:add_component('stonehearth_ace:quest_storage'):get_item_tracker()
   end

   if self._output_storage then
      self._entity:add_component('stonehearth_ace:output'):add_input(self._output_storage)
      self._output_storage_listener = radiant.events.listen(self._output_storage, 'stonehearth:storage:item_removed', self, self._on_output_storage_item_removed)
      self._output_storage_listener_2 = radiant.events.listen(self._output_storage, 'stonehearth:storage:item_added', self, self._update_output_num_items)

      local storage_comp = self._output_storage:add_component('stonehearth:storage')
      self._sv.output_tracker = storage_comp:get_item_tracker()
      self._sv.output_capacity = storage_comp:get_capacity()
      self._sv.output_num_items = storage_comp:get_num_items()
   end

   self._consumer_fueled_changed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:consumer:fueled_changed', self, self._on_fueled_changed)
   self._crafting_time_modifier_changed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:workshop:crafting_time_modifier_changed', self, self._on_crafting_time_modifier_changed)

   self:_setup()
   
   -- if restoring, check to see if we were already crafting something
   -- if so, make sure that starts up again
   if self._is_restore then
      local workshop = self._entity:get_component('stonehearth:workshop')
      local progress = workshop and workshop:get_crafting_progress_controller()
      if progress and workshop:get_crafting_time_modifier() ~= 0 and workshop:available_for_work(self._entity) then
         -- also reacquire leases on all the ingredients
         local leases = self:_lease_all_ingredients()
         progress:add_ingredient_leases(leases)

         -- don't actually start crafting unless the secondary order list is active
         local crafter_component = self._entity:get_component('stonehearth:crafter')
         local curr_order = crafter_component and crafter_component:get_current_order()
         if curr_order and not curr_order:get_order_list():is_secondary_list_paused() then
            progress:crafting_started()
            self:_create_crafting_finish_time_changed_listener(progress)
         end
      end
   end
end

function AutoCraftComponent:destroy()
   self:_destroy_listeners()
   self:_cancel_crafting()
end

function AutoCraftComponent:_destroy_listeners()
   if self._storage_item_added_listener then
      self._storage_item_added_listener:destroy()
      self._storage_item_added_listener = nil
   end
   if self._output_storage_listener then
      self._output_storage_listener:destroy()
      self._output_storage_listener = nil
   end
   if self._output_storage_listener_2 then
      self._output_storage_listener_2:destroy()
      self._output_storage_listener_2 = nil
   end
   if self._consumer_fueled_changed_listener then
      self._consumer_fueled_changed_listener:destroy()
      self._consumer_fueled_changed_listener = nil
   end
   if self._crafting_time_modifier_changed_listener then
      self._crafting_time_modifier_changed_listener:destroy()
      self._crafting_time_modifier_changed_listener = nil
   end
   if self._try_crafting_again_timer then
      self._try_crafting_again_timer:destroy()
      self._try_crafting_again_timer = nil
   end
   self:_destroy_craft_order_listeners()
end

function AutoCraftComponent:_destroy_crafting_finish_time_changed_listener()
   if self._crafting_finish_time_changed_listener then
      self._crafting_finish_time_changed_listener:destroy()
      self._crafting_finish_time_changed_listener = nil
   end
end

function AutoCraftComponent:_destroy_crafting_finished_timer()
   if self._crafting_finished_timer then
      self._crafting_finished_timer:destroy()
      self._crafting_finished_timer = nil

      self:_update_commands()
   end
end

function AutoCraftComponent:_destroy_craft_order_listeners()
   for _, entry in pairs(self._craft_order_listeners) do
      entry.listener:destroy()
   end
   self._craft_order_listeners = {}
end

function AutoCraftComponent:get_output_capacity()
   local output_storage = self._output_storage and self._output_storage:get_component('stonehearth:storage')
   return output_storage and output_storage:get_capacity()
end

function AutoCraftComponent:get_ingredient_storage()
   return self._ingredient_storage
end

function AutoCraftComponent:_build_enabled_recipes_lookup()
   -- go through the enabled recipes and build our lookup
   self._enabled_recipes = {}
   for _, enabled_recipe in ipairs(self._sv.enabled_recipes) do
      local enabled_job = self._enabled_recipes[enabled_recipe.job]
      if not enabled_job then
         enabled_job = {}
         self._enabled_recipes[enabled_recipe.job] = enabled_job
      end
      enabled_job[enabled_recipe.recipe_key] = true
   end
end

function AutoCraftComponent:_setup()
   self:_load_all_recipes()
end

-- load up recipes from json and any saved recipes
-- saved recipes can include disabling default recipes!
function AutoCraftComponent:_load_all_recipes()
   local known_recipes = {}
   local enabled_recipes = {}
   local new_recipes_to_enable = {}
   self:_load_recipes(known_recipes, self._json.recipes, enabled_recipes, new_recipes_to_enable)
   self:_load_recipes(known_recipes, self._sv.recipes, enabled_recipes, new_recipes_to_enable)

   self._sv.recipes = known_recipes
   self._enabled_recipes = enabled_recipes

   -- remove any enabled recipes that are no longer valid
   for i = #self._sv.enabled_recipes, 1, -1 do
      local enabled_recipe = self._sv.enabled_recipes[i]
      if not self._enabled_recipes[enabled_recipe.job] or
            not self._enabled_recipes[enabled_recipe.job][enabled_recipe.recipe_key] then
         table.remove(self._sv.enabled_recipes, i)
      end
   end

   -- add any new valid recipes to the end of the list
   for _, enabled_recipe in ipairs(new_recipes_to_enable) do
      -- just make sure in case a secondary source wanted to disable it
      if self._enabled_recipes[enabled_recipe.job] and self._enabled_recipes[enabled_recipe.job][enabled_recipe.recipe_key] then
         table.insert(self._sv.enabled_recipes, enabled_recipe)
      end
   end

   self.__saved_variables:mark_changed()

   self:_check_craft_orders()
end

function AutoCraftComponent:_load_recipes(into, recipes, enabled_recipes, new_recipes_to_enable)
   if recipes then
      for job, job_recipes in pairs(recipes) do
         local into_job = into[job]
         if not into_job then
            into_job = {}
            into[job] = into_job
         end

         local enabled = enabled_recipes[job]
         if not enabled then
            enabled = {}
            enabled_recipes[job] = enabled
         end

         local cur_enabled = self._enabled_recipes[job]

         for key, allowed in pairs(job_recipes) do
            into_job[key] = allowed or nil
            if cur_enabled and cur_enabled[key] ~= nil then
               enabled[key] = cur_enabled[key]
            else
               enabled[key] = true
               table.insert(new_recipes_to_enable, { job = job, recipe_key = key })
            end
         end
      end
   end
end

-- go through all the recipes we can make and index by ingredients
-- so when a new potential ingredient becomes available, we can see if any recipes become craftable
function AutoCraftComponent:_check_craft_orders()
   self:_destroy_craft_order_listeners()
   
   local player_jobs = stonehearth.job:get_jobs_controller(self._player_id)
   if player_jobs then
      for job, job_recipes in pairs(self._sv.recipes) do
         local job_info = player_jobs:get_job(job)
         local order_list = job_info and job_info:get_order_list()

         if order_list then
            -- listen to auto-order changes in the craft order list
            self._craft_order_listeners[job] = {
               order_list = order_list,
               listener = radiant.events.listen(order_list, 'stonehearth_ace:craft_order_list:auto_craft_orders_changed', function()
                     self:_on_auto_craft_orders_changed(order_list)
                  end),
            }
         end
      end
   end

   self:_update_ingredients()
end

function AutoCraftComponent:_on_auto_craft_orders_changed(order_list)
   -- first check to see if we're currently crafting a recipe that was removed
   -- if so, we need to cancel crafting
   local workshop = self._entity:get_component('stonehearth:workshop')
   local progress = workshop and workshop:get_crafting_progress_controller()
   local crafter_component = self._entity:get_component('stonehearth:crafter')
   local curr_order = crafter_component and crafter_component:get_current_order()
   -- log:debug('%s auto craft orders changed; progress: %s, curr_order: %s (%s)',
   --       self._entity, tostring(progress), tostring(curr_order), tostring(curr_order and curr_order.__destroyed))
   if progress and (not curr_order or curr_order.__destroyed) then
      -- we were crafting a recipe that was destroyed, cancel crafting
      self:_cancel_crafting()
   elseif progress then
      -- we're currently crafting, but maybe the order list has had its secondary orders paused
      -- if so, we need to pause crafting by disabling progress and destroying the timer
      -- otherwise, if it was paused and now it's not, we need to resume crafting
      if progress:is_active() and order_list:is_secondary_list_paused() then
         self:_destroy_crafting_finished_timer()
         self:_destroy_crafting_finish_time_changed_listener()
         progress:crafting_stopped()
      elseif not progress:is_active() and not order_list:is_secondary_list_paused() then
         progress:crafting_started()
         self:_create_crafting_finish_time_changed_listener(progress)
      end
   end

   self:_update_ingredients()
end

-- TODO: if this ends up being bad for performance, we can break it up and handle add/remove individually
-- but the operations are probably infrequent enough and the processing needed small enough that it's not worth it
function AutoCraftComponent:_update_ingredients()
   -- TODO: set requirements in quest storage component
   -- determine all ingredients (with max amounts) needed for each allowed and enabled recipe with a queued craft order
   -- multiply by ingredient buffer multiplier
   local requirements = {}

   local player_jobs = stonehearth.job:get_jobs_controller(self._player_id)
   for job, entry in pairs(self._craft_order_listeners) do
      local enabled_recipes = self._enabled_recipes[job]
      local auto_orders = enabled_recipes and entry.order_list:get_all_auto_craft_orders()
      if auto_orders and #auto_orders > 0 then
         for _, order in ipairs(auto_orders) do
            local recipe = order:get_recipe()
            if enabled_recipes[recipe.recipe_key] then
               for _, ingredient in ipairs(recipe.ingredients) do
                  local ing_key = ingredient.uri or ingredient.material
                  local requirement_entry = requirements[ing_key]
                  if not requirement_entry then
                     requirement_entry = {
                        uri = ingredient.uri,
                        material = ingredient.material,
                        quantity = ingredient.count,
                     }
                     requirements[ing_key] = requirement_entry
                  else
                     requirement_entry.quantity = math.max(requirement_entry.quantity, ingredient.count)
                  end
               end
            end
         end
      end
   end

   self._requirements = requirements
   self:_update_ingredient_storage()
end

function AutoCraftComponent:_update_ingredient_storage()
   local quest_storage = self._ingredient_storage and self._ingredient_storage:get_component('stonehearth_ace:quest_storage')
   if quest_storage and next(self._requirements) then
      -- duplicate the requirements, but with the adjusted quantities based on ingredient buffer multiplier
      local requirements = {}
      for key, requirement in pairs(self._requirements) do
         table.insert(requirements, {
            uri = requirement.uri,
            material = requirement.material,
            quantity = math.ceil(requirement.quantity * self._sv.ingredient_buffer_multiplier),
         })
      end
      quest_storage:set_requirements(requirements)
      self:_try_crafting()
   end
end

function AutoCraftComponent:is_crafting()
   return self._crafting_finished_timer ~= nil
end

function AutoCraftComponent:set_ingredient_buffer_multiplier(session, response, multiplier)
   self:_set_ingredient_buffer_multiplier(multiplier)
   return true
end

function AutoCraftComponent:_set_ingredient_buffer_multiplier(multiplier)
   self._sv.ingredient_buffer_multiplier = math.min(MAX_INGREDIENT_BUFFER_MULTIPLIER, math.max(MIN_INGREDIENT_BUFFER_MULTIPLIER, multiplier))
   self.__saved_variables:mark_changed()
   self:_update_ingredient_storage()
end

function AutoCraftComponent:set_enabled_recipes(session, response, enabled_recipes)
   self._sv.enabled_recipes = enabled_recipes
   self.__saved_variables:mark_changed()
   self:_build_enabled_recipes_lookup()
   return true
end

function AutoCraftComponent:add_recipe(job, recipe_key)
   if not self._sv.recipes[job] or not self._sv.recipes[job][recipe_key] then
      self:_load_recipes(self._sv.recipes, { [job] = { [recipe_key] = true} }, {})
      table.insert(self._sv.enabled_recipes, { job = job, recipe_key = recipe_key })
      self.__saved_variables:mark_changed()

      self:_update_ingredients()
   end
end

function AutoCraftComponent:remove_recipe(job, recipe_key)
   if self._sv.recipes[job] and self._sv.recipes[job][recipe_key] then
      self._sv.recipes[job][recipe_key] = nil
      if not next(self._sv.recipes[job]) then
         self._sv.recipes[job] = nil
      end
      self.__saved_variables:mark_changed()

      self:_update_ingredients()
   end
end

function AutoCraftComponent:_update_output_num_items()
   local storage_comp = self._output_storage and self._output_storage:get_component('stonehearth:storage')
   if storage_comp then
      self._sv.output_num_items = storage_comp:get_num_items()
      self.__saved_variables:mark_changed()
   end
end

-- this is triggered async, so we don't have to worry about products being added triggering it while we're crafting
function AutoCraftComponent:_on_storage_item_added(args)
   self:_try_crafting()
end

-- also triggered async; when our output storage has room, we can try to craft again
function AutoCraftComponent:_on_output_storage_item_removed(args)
   self:_update_output_num_items()
   if self:get_output_capacity() > 0 then
      self:_try_crafting()
   end
end

function AutoCraftComponent:_on_fueled_changed(args)
   -- TODO: if no fuel and we're actively crafting, something went seriously wrong... pause crafting?
   -- but if we weren't crafting and now there's fuel, maybe we can craft
   self:_try_crafting()
end

function AutoCraftComponent:_on_crafting_time_modifier_changed()
   -- if we're already crafting, the modifier changing will be handled by a different event
   -- if we're not crafting, and it was 0, we need to try crafting
   self:_try_crafting()
end

function AutoCraftComponent:_try_crafting()
   local workshop = self._entity:get_component('stonehearth:workshop')
   -- if we're currently crafting, we can't start crafting something else
   if not workshop or workshop:get_crafting_progress_controller() then
      return
   end

   -- if we actually *can* craft right now (e.g., have enough mechanical power so the modifier > 0)
   if workshop:get_crafting_time_modifier() ~= 0 and workshop:available_for_work(self._entity) and #self._sv.enabled_recipes > 0 then
      -- try to find a recipe for which we have all the ingredients and have room for the products
      -- check each enabled recipe in order to see if one is available
      local possible_orders = {}
      for job, entry in pairs(self._craft_order_listeners) do
         -- make sure this order list doesn't have secondary orders paused
         if self._enabled_orders[job] and not entry.order_list:is_secondary_list_paused() then
            for _, order in ipairs(order_list:get_all_auto_craft_orders()) do
               local recipe = order:get_recipe()
               if self._enabled_orders[job][recipe.recipe_key] then
                  local job_orders = possible_orders[job]
                  if not job_orders then
                     job_orders = {}
                     possible_orders[job] = job_orders
                  end
                  job_orders[recipe.recipe_key] = order
               end
            end
         end
      end

      -- if we have any possible orders, pick one and start crafting it
      if next(possible_orders) then
         for _, enabled_recipe in ipairs(self._sv.enabled_recipes) do
            local job_orders = possible_orders[enabled_recipe.job]
            if job_orders then
               local order = job_orders[enabled_recipe.recipe_key]
               if order then
                  self:_start_crafting(order)
                  return
               end
            end
         end
      end
   end

   local crafter_comp = self._entity:get_component('stonehearth:crafter')
   crafter_comp:set_current_order(nil)
end

function AutoCraftComponent:_lease_all_ingredients()
   local leases = {}
   local entity_container = self._entity:get_component('entity_container')
   if entity_container then
      local ec_children = {}
      for id, child in entity_container:each_child() do
         ec_children[id] = child
      end
      for i, item in pairs(ec_children) do
         if item and item:is_valid() then
            table.insert(leases, stonehearth.ai:acquire_ai_lease(item, self._entity))
         end
      end
   end
   return leases
end

function AutoCraftComponent:_start_crafting(order)
   local crafter_comp = self._entity:get_component('stonehearth:crafter')
   crafter_comp:set_current_order(order)
   order:set_crafting_status(self._entity)
   while order:get_progress(self._entity) < constants.crafting_status.CRAFTING do
      order:progress_to_next_stage(self._entity)
   end

   -- move ingredients into entity_container component
   local entity_container = self._entity:add_component('entity_container')
   local quest_storage = self._ingredient_storage:get_component('stonehearth_ace:quest_storage')
   local ingredients = order:get_recipe().ingredients
   for _, ingredient in ipairs(ingredients) do
      local storage = quest_storage:get_storage_by_requirement(ingredient.uri or ingredient.material)
      -- TODO: allow for min_stacks type ingredients
      assert(storage and storage:get_num_items() >= ingredient.count, 'ingredient storage does not have enough items for crafting')
      local items = storage:get_items()
      for i = 1, ingredient.count do
         local item = storage:remove_item(next(items))
         if item then
            entity_container:add_child(item)
         end
      end
   end

   local workshop_comp = self._entity:get_component('stonehearth:workshop')
   workshop_comp:run_effect()
   local progress = workshop_comp:start_crafting_progress(order)
   progress:add_ingredient_leases(self:_lease_all_ingredients())
   progress:crafting_started()
   
   -- listen for completion or cancellation
   self:_create_crafting_finish_time_changed_listener(progress)
end

function AutoCraftComponent:_create_crafting_finish_time_changed_listener(progress)
   self:_destroy_crafting_finish_time_changed_listener()
   self._crafting_finish_time_changed_listener = radiant.events.listen(progress, 'stonehearth_ace:crafting_progress:end_time_changed', function()
         self:_create_crafting_finished_timer(progress)
      end)
   self:_create_crafting_finished_timer(progress)
end

function AutoCraftComponent:_create_crafting_finished_timer(progress)
   self:_destroy_crafting_finished_timer()
   if progress:get_workshop_modifier() ~= 0 then
      self._crafting_finished_timer = stonehearth.calendar:set_timer("auto-crafting ", progress:get_duration(), function()
         self:_finish_crafting(progress)
      end)

      self:_update_commands()
   end
end

function AutoCraftComponent:_finish_crafting(progress)
   local crafter_component = self._entity:get_component('stonehearth:crafter')
   local curr_order = crafter_component and crafter_component:get_current_order()
   local workshop_comp = self._entity:get_component('stonehearth:workshop')
   if curr_order then
      local consumer_comp = self._entity:get_component('stonehearth_ace:consumer')
      if consumer_comp then
         consumer_comp:consume_fuel(self._entity)
      end

      local ingredients, ingredient_quality = crafting_lib.get_ingredients_and_quality(self._entity)
      local primary_output, all_outputs = crafting_lib.craft_items(nil, self._entity, self._entity, curr_order:get_recipe(), ingredients, ingredient_quality)
      crafting_lib.destroy_ingredients(ingredients)
      progress:destroy_working_ingredient()

      -- try to add all the outputs to any of our ingredient (input) storages, or any connected output storage
      local quest_storage = self._ingredient_storage:get_component('stonehearth_ace:quest_storage')
      local result = radiant.entities.output_spawned_items(all_outputs, nil, nil, nil, {
         output = self._entity,
         inputs = quest_storage:get_storage_entities(),
         spill_fail_items = false,
         delete_fail_items = false,
         force_add = true, -- force_add is only used for outputs, not inputs (inputs have to match the filter)
      })
      --log:debug('%s finished crafting; result: %s', self._entity, radiant.util.table_tostring(result))

      progress:crafting_stopped()
      curr_order:progress_to_next_stage(self._entity)
      curr_order:set_crafting_status(nil)

      workshop_comp:stop_running_effect()
      workshop_comp:finish_crafting_progress()

      -- schedule a check to see if we can craft again
      self._try_crafting_again_timer = radiant.on_game_loop_once('consider crafting again', function()
         self._try_crafting_again_timer = nil
         self:_try_crafting()
      end)
   end
end

function AutoCraftComponent:_cancel_crafting()
   self:_destroy_crafting_finished_timer()
   self:_destroy_crafting_finish_time_changed_listener()

   local workshop_comp = self._entity:get_component('stonehearth:workshop')
   local progress = workshop_comp and workshop_comp:get_crafting_progress_controller()
   if progress then
      progress:destroy_working_ingredient()
      progress:crafting_stopped()
   end
   if workshop_comp then
      workshop_comp:stop_running_effect()
      workshop_comp:finish_crafting_progress()
   end

   -- try to add all the active ingredients to any of our ingredient (input) storages, or any connected output storage
   local ingredients, ingredient_quality = crafting_lib.get_ingredients_and_quality(self._entity)
   if next(ingredients) then
      local quest_storage = self._ingredient_storage and self._ingredient_storage:get_component('stonehearth_ace:quest_storage')
      radiant.entities.output_spawned_items(ingredients, radiant.entities.get_world_grid_location(self._entity), 1, 4, {
         output = self._entity,
         inputs = quest_storage and quest_storage:get_storage_entities(),
         spill_fail_items = true,
         delete_fail_items = false,
         force_add = true, -- force_add is only used for outputs, not inputs
      })
   end
end

function AutoCraftComponent:_update_commands()
   local is_crafting = self:is_crafting()

   local commands_component = self._entity:get_component('stonehearth:commands')
   if commands_component then
      commands_component:set_command_enabled('stonehearth:commands:move_item', is_crafting)
      commands_component:set_command_enabled('stonehearth:commands:undeploy_item', is_crafting)
   end

   -- also, if we're crafting, cancel any tasks on us
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   if task_tracker_component and is_crafting then
      task_tracker_component:cancel_current_task(true)
   end
end

return AutoCraftComponent
