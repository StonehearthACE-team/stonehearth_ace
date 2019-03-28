local CraftItemsOrchestrator = require 'stonehearth.services.server.town.orchestrators.craft_items_orchestrator'
local constants = require 'stonehearth.constants'
local log = radiant.log.create_logger('crafter'):set_prefix('craft_items_orchestrator')

local AceCraftItemsOrchestrator = class()

-- Paul: only three lines are changed from the original function in order to support multiple crafters per order:
--    the references to workshop_component:start_crafting_progress(...), order:reset_progress(...), and order:progress_to_next_stage(...)
--- Find a workshop of an appropriate type, if needed, and perform the crafting action
--  Action finds a workshop, if needed, reserves it, dumps items onto it, does the work,
--  destroys the ingredients, produces the output
function AceCraftItemsOrchestrator:_process_order(order)
   local recipe = order:get_recipe()

   local args = {
      craft_order = order,
      ingredients = recipe.ingredients,
      item_name = recipe.recipe_name
   }

   --Do we already have a workshop, because we are loading into a partially completed order?
   local curr_workshop = self._crafter:get_component('stonehearth:crafter'):get_current_workshop()
   if curr_workshop then
      args.proxy_workshop = curr_workshop
   elseif recipe.workshop then
      --if there is no current workshop but the recipe specifies one, then set workshop type
      args.workshop_type = recipe.workshop.uri
   else
      --if neither of the above are true, put down an invisible temporary workshop,
      --where we will create the target item
      local location = radiant.entities.get_world_grid_location(self._crafter)
      local items = {}

      local temp_workbench_location, _ = radiant.terrain.find_closest_standable_point_to(location, 30, self._crafter)
      self._temp_workbench = radiant.entities.create_entity('stonehearth:crafter:temporary_workbench', { owner = radiant.entities.get_player_id(self._crafter) })
      radiant.terrain.place_entity(self._temp_workbench, temp_workbench_location)
      args.proxy_workshop = self._temp_workbench
      local workshop_component = self._temp_workbench:get_component('stonehearth:workshop')
      workshop_component:start_crafting_progress(order, self._crafter) -- Paul: this line was changed
      self._crafter:get_component('stonehearth:crafter'):set_current_workshop(self._temp_workbench)
   end

   log:detail('Crafter %s is about to craft item %s', self._crafter, recipe.recipe_name)

   self._task = self._task_group:create_task('stonehearth:craft_item', args)
                                     :once()
                                     :start()

   --If the task does not complete, then return false
   local success = self._task:wait()
   self:_destroy_task()

   if not success then
      log:detail('Crafter %s craft_item task failed. Resetting order progress', self._crafter)
      self:_cleanup_order()
      order:reset_progress(self._crafter) -- failed! reset our progress -- Paul: this line was changed
      return false
   end

   log:detail('Crafter %s craft_item task succeeded', self._crafter)

   --if we get here, the task completed, so we return true
   --Time to move to the next step
   order:progress_to_next_stage(self._crafter)  -- Paul: this line was changed
   self:_cleanup_order()
   return true
end

-- Paul only two lines are changed from the original function in order to support multiple crafters per order:
--    both references to craft_order:set_crafting_status(...)
function AceCraftItemsOrchestrator:run(town, args)
   self._town = town
   self._thread = stonehearth.threads:get_current_thread()
   self._crafter = args.crafter
   local job_component = self._crafter:get_component('stonehearth:job')
   self._job_uri = job_component:get_job_uri()
   self._bulletins = {} -- list of unreachable ingredient notifications

   --Find the order_list from the job_controller
   self._craft_order_list = job_component:get_job_info():get_order_list()

   self._task_group = stonehearth.tasks:instantiate_task_group('stonehearth:task_groups:orchestrated_crafting')
                                                  :add_worker(self._crafter)

   self._inventory = stonehearth.inventory:get_inventory(town:get_player_id())
   self._order_changed_listener = radiant.events.listen(self._craft_order_list, 'stonehearth:order_list_changed', self, self._on_order_list_changed)
   self:_on_order_list_changed()
   self._usable_item_tracker = self._inventory:get_item_tracker('stonehearth:usable_item_tracker')

   --Listen to level up in case leveling now allows us to make an item
   self._level_up_listener = radiant.events.listen(self._crafter, 'stonehearth:level_up', self, self._on_order_list_changed)

   -- Listen to incapacitation changes
   self._became_incapacitated_listener = radiant.events.listen(self._crafter, 'stonehearth:entity:became_incapacitated', self, self._on_became_incapacitated)
   self._incapacitated_changed_listener = radiant.events.listen(self._crafter, 'stonehearth:entity:incapacitate_state_changed', self, self._on_incapacitate_changed)
   self._unreachable_ingredients_listener = radiant.events.listen(self._craft_order_list, 'stonehearth:cant_reach_ingredients', self, self._show_unreachable_ingredients_notification)

   local crafter_component = self._crafter:get_component('stonehearth:crafter')

   while true do
      log:detail('Crafter %s is starting base crafting loop', self._crafter)

      --first, check if we already have an order
      local order = crafter_component:get_current_order()
      --if not, get the next available order
      if not order then
         log:detail('Crafter %s looks for a new order', self._crafter)

         --Dump everything in the crafter pack, which may be stuff from the last completed or
         --aborted order. Always start a new order with an empty backpack.
         self:_drop_crafted_items(order)

         order = self:_get_next_order()

         crafter_component:set_current_order(order)
         order:set_crafting_status(self._crafter, true) -- Paul: this line was changed
      end

      local recipe_name = order:get_recipe().recipe_name
      log:detail('Crafter %s has an order for recipe %s', self._crafter, recipe_name)

      --try collecting the ingredients
      local collection_success = self:_collect_ingredients(order)
      log:detail('Crafter %s collected ingredients: %s', self._crafter, tostring(collection_success))

      --If we collected all the items and the order is still valid, process the order
      if collection_success and order then
         log:detail('Crafter %s processing order %s', self._crafter, recipe_name)
         if self:_process_order(order) then
            if order:is_complete() then
               log:detail('Crafter %s finished order %s', self._crafter, recipe_name)
               self._craft_order_list:remove_order(order:get_id())
            end
            log:detail('Crafter %s setting crafting status and current order to nil', self._crafter)
            order:set_crafting_status(self._crafter, false) -- Paul: this line was changed
            crafter_component:set_current_order(nil)
         end
      else
         -- Collecting ingredients failed, we need to reset the current order here.
         -- Player will be notified once a day if there are still unreachable ingredients.
         crafter_component:clean_up_order()
      end
   end
end

-- overriding this to add title data to the bulletin (also implemented gameplay setting since it didn't exist)
function AceCraftItemsOrchestrator:_show_unreachable_ingredients_notification(event_args)
   local player_id = radiant.entities.get_player_id(self._crafter)
   local enable_notification = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'show_unreachable_ingredients_notification', false)
   if enable_notification then
      local missing_ingredient = event_args.ingredient.ingredient -- ingredient field of the ingredient argument

      -- Use the material or uri of the ingredient to keep track of which notifications have been posted
      local ingredient_name = ''
      local material_in_inventory = nil
      local uri_in_inventory = nil
      if missing_ingredient.material ~= nil then
         ingredient_name = missing_ingredient.material
         if self._usable_item_tracker then
            material_in_inventory = self._usable_item_tracker:contains_item_with_material(ingredient_name)
         end
      elseif missing_ingredient.uri ~= nil then
         ingredient_name = missing_ingredient.uri
         uri_in_inventory = self._inventory:get_items_of_type(ingredient_name)
      end

      --Only post the bulletin if:
      -- * It's the first time that we can't reach the ingredient or
      -- * If a day has passed and we are trying to craft any recipe that uses it and we still can't reach it
      if self._bulletins[ingredient_name] == nil then
         -- Don't notify if we just ran out of that ingredient
         if material_in_inventory or uri_in_inventory then
            self._bulletins[ingredient_name] = true
            stonehearth.bulletin_board:post_bulletin(player_id)
                                       :set_callback_instance(stonehearth.town:get_town(player_id))
                                       :set_type('info')
                                       :set_data ({
                                          title = 'i18n(stonehearth:ui.game.entities.unreachable_ingredient_notification)',
                                          message = constants.crafting.UNREACHABLE_INGREDIENT_NOTIFICATION_MESSAGE,
                                          zoom_to_entity = self._crafter,
                                       })
                                       :set_active_duration(constants.crafting.UNREACHABLE_INGREDIENT_NOTIFICATION_DURATION)
                                       :add_i18n_data('citizen_custom_name', radiant.entities.get_custom_name(self._crafter))
                                       :add_i18n_data('citizen_display_name', radiant.entities.get_display_name(self._crafter))
                                       :add_i18n_data('citizen_custom_data', radiant.entities.get_custom_data(self._crafter))
                                       :add_i18n_data('crafting_order', event_args.recipe_name)

            -- Set up a timer to clear the bulletin from our list after a day
            stonehearth.calendar:set_timer("clear craft bulletins daily", constants.crafting.UNREACHABLE_INGREDIENT_NOTIFICATION_TIMEOUT,
               function()
                  self._bulletins[ingredient_name] = nil
               end)
         end
      end
   end
end

return AceCraftItemsOrchestrator
