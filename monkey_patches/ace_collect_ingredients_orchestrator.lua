local AceCollectIngredients = class()
local IngredientList = require 'stonehearth.components.workshop.ingredient_list'

local log = radiant.log.create_logger('crafter'):set_prefix('collect_ingredients_orchestrator')

-- Paul: changed all order progress gets/sets to pass the crafter along
function AceCollectIngredients:run(town, args)
   local task_group = args.task_group
   local ingredients = IngredientList(args.ingredients)
   self._crafter = args.crafter
   self._craft_order_list = args.order_list
   self._order = args.order
   self._prefer_high_quality = self._order:get_high_quality_preference()
   if self._prefer_high_quality == nil then
      -- if an explicit quality preference wasn't set, use the default gameplay setting for it
      -- but only if the crafter has the quality crafting perk; otherwise prefer lower quality
      local job = self._crafter:get_component('stonehearth:job')
      if job and job:curr_job_has_perk('crafter_recipe_unlock_3') then
         self._prefer_high_quality = stonehearth.client_state
            :get_client_gameplay_setting(self._sv.player_id, 'stonehearth_ace', 'default_craft_order_prefer_high_quality', true)
      else
         self._prefer_high_quality = false
      end
   end

   if self._craft_order_list and self._order then
      self._order_list_listener = radiant.events.listen(self._craft_order_list, 'stonehearth:order_list_changed', self, self._on_order_list_changed)
   end

   self._became_incapacitated_listener = radiant.events.listen(self._crafter, 'stonehearth:entity:became_incapacitated', self, self._on_became_incapacitated)
   self._abort_listener = radiant.events.listen(self._crafter, 'stonehearth:entity:stopped_looking_for_ingredients', self, self._on_aborted_looking_for_ingredients)

   --If the order was unstarted, then move it to Collecting, and get the next phase
   if self._order:get_progress(self._crafter) == stonehearth.constants.crafting_status.UNSTARTED then
      self._order:progress_to_next_stage(self._crafter)
   end

   --If we're in collecting, then progress with getting ingredients
   if self._order:get_progress(self._crafter) == stonehearth.constants.crafting_status.COLLECTING then
      --first check of any ingredients that may already be in our crafter pack
      self:_check_off_crafter_pack_ingredients(ingredients)

      --Then, if the ingredients are not still completed, get more from the world

      local rating_fn
      if self._prefer_high_quality then
         rating_fn = function(item)
            return radiant.entities.get_item_quality(item) / 3
         end
      else
         rating_fn = function(item)
            return 2 - radiant.entities.get_item_quality(item)
         end
      end

      while not ingredients:completed() do
         local ing = ingredients:get_next_ingredient()
         local args = {
            ingredient = ing,
            ingredient_list = ingredients,
            rating_fn = rating_fn
         }

         log:detail('Crafter %s looks for ingredient %s', self._crafter, radiant.util.table_tostring(ing))

         self._task = task_group:create_task('stonehearth:collect_ingredient', args)
                             :once()
                             :start()

         local check_task_fn = function()
            if not self._crafter or not self._crafter:is_valid() then
               self:_destroy_task()
            end
         end

         self._retry_listener = radiant.events.listen(self._crafter, 'stonehearth:ai:ended_main_ai_loop_iteration', check_task_fn)

         if not self._task:wait() then
            self:_destroy_task()
            if self._retry_listener then
               self._retry_listener:destroy()
               self._retry_listener = nil
            end
            return false
         end
         if self._retry_listener then
            self._retry_listener:destroy()
            self._retry_listener = nil
         end
         self:_destroy_task()
      end

      log:detail('Crafter %s has found all ingredients', self._crafter)

      --we should now have all the ingredients in our backpack
      --exit to the next stage
      self._order:progress_to_next_stage(self._crafter)
   end

   --Note: if we are loading, and past this stage, then we just return true.
   return true
end

return AceCollectIngredients
