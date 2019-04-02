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
      if town and job and job:curr_job_has_perk('crafter_recipe_unlock_3') then
         self._prefer_high_quality = stonehearth.client_state
            :get_client_gameplay_setting(town:get_player_id(), 'stonehearth_ace', 'default_craft_order_prefer_high_quality', true)
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

      local max_distance_for_rating_sq = stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH
      local close_distance_for_rating_sq = stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH
      local rating_fn
      if self._prefer_high_quality then
         rating_fn = function(item, entity, entity_location, storage_location)
            local rating = radiant.entities.get_item_quality(item) / 3
            return rating

            -- local distance_sq = (entity_location or radiant.entities.get_world_grid_location(entity))
            --       :distance_to_squared(storage_location or radiant.entities.get_world_grid_location(item))
            -- local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))

            -- return rating * 0.8 + distance_score * 0.2
         end
      else
         rating_fn = function(item, entity, entity_location, storage_location)
            local rating = 2 - radiant.entities.get_item_quality(item)
            return rating

            -- local distance_sq = (entity_location or radiant.entities.get_world_grid_location(entity))
            --       :distance_to_squared(storage_location or radiant.entities.get_world_grid_location(item))
            -- local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))
            
            -- return rating * 0.8 + distance_score * 0.2
         end
      end

      local distance_rating_fn = function(item, entity, entity_location, storage_location)
         -- anything within the close distance is considered "best"; doesn't matter if it goes negative
         local distance_sq = (entity_location or radiant.entities.get_world_grid_location(entity))
               :distance_to_squared(storage_location or radiant.entities.get_world_grid_location(item)) - close_distance_for_rating_sq
         local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))
         
         return distance_score
      end

      while not ingredients:completed() do
         local ing = ingredients:get_next_ingredient()
         local args = {
            ingredient = ing,
            ingredient_list = ingredients
         }

         -- for each ingredient, check if we actually have any higher quality ingredients
         -- if we don't, don't bother with a rating function
         if self._order:ingredient_has_multiple_qualities(ing) then
            args.rating_fn = rating_fn
         else
            args.rating_fn = distance_rating_fn
         end

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
