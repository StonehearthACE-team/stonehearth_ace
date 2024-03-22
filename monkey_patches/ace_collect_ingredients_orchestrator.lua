local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

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
   local job_comp = self._crafter:get_component('stonehearth:job')
   local job_level = job_comp:get_current_job_level()
   self._max_quality = item_quality_lib.get_max_crafting_quality(self._crafter:get_player_id(), job_level)

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

      -- local max_distance_for_rating_sq = stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH
      -- local close_distance_for_rating_sq = stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH
      local max_distance = stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH * 5
      local max_distance_sq = max_distance * max_distance
      local rating_fn = function(item, entity, entity_location, storage_location)
         local quality = radiant.entities.get_item_quality(item)

         -- if the quality is greater than we can effectively use, rate that item lower so we don't waste it
         if quality > self._max_quality then
            return 0
         end

         -- if it's higher quality but further than some arbitrary distance, rate it lower so we don't waste time
         -- storage location might not be representative if it's a universal storage entity
         if quality > 1 then
            local p1 = entity_location or radiant.entities.get_world_grid_location(entity)
            local p2 = storage_location or radiant.entities.get_world_grid_location(item)
            if p1 and p2 and p1:distance_to_squared(p2) > max_distance_sq then
               return 0
            end
         end

         local rating = quality / self._max_quality

         if radiant.entities.is_material(item, 'preferred_ingredient') then
            return rating
         end

         if radiant.entities.is_material(item, 'undesirable_ingredient') then
            return rating * 0.1
         end

         return rating * 0.5

         -- local p1 = entity_location or radiant.entities.get_world_grid_location(entity)
         -- local p2 = storage_location or radiant.entities.get_world_grid_location(item)

         -- if not p1 or not p2 then
         --    log:debug('HQ distance sq no location! %s (%s) -> %s (%s)', entity, p1 or 'NIL', item, p2 or 'NIL')
         --    return rating
         -- else
         --    local distance_sq = p1:distance_to_squared(p2) - close_distance_for_rating_sq
         --    local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))

         --    --log:debug('HQ distance sq %s and score %s for %s to %s', distance_sq, distance_score, entity, item)

         --    return rating * 0.8 + distance_score * 0.2
         -- end
      end

      local distance_rating_fn = function(item, entity, entity_location, storage_location)
			if radiant.entities.is_material(item, 'preferred_ingredient') then
            return 1
         end

			if radiant.entities.is_material(item, 'undesirable_ingredient') then
            return 0
         end

         return 0.5

         -- -- anything within the close distance is considered "best"; doesn't matter if it goes negative
         -- local p1 = entity_location or radiant.entities.get_world_grid_location(entity)
         -- local p2 = storage_location or radiant.entities.get_world_grid_location(item)

         -- if not p1 or not p2 then
         --    return 0
         -- else
         --    local distance_sq = p1:distance_to_squared(p2) - close_distance_for_rating_sq
         --    local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))

         --    --log:debug('distance sq %s and score %s for %s to %s', distance_sq, distance_score, entity, item)

         --    return distance_score
         -- end
      end

      local first_loop = true
      while not ingredients:completed() do
         -- if we're on the second or later ingredient, re-verify that all ingredients are available
         if first_loop then
            first_loop = false
         else
            local failed_ingredient = self._order:is_missing_ingredient(ingredients._remaining_ingredients)
            if failed_ingredient then
               return false
            end
         end

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

function AceCollectIngredients:_on_aborted_looking_for_ingredients(event_args)
   -- Register that this order is stuck, so that we don't reconsider it until we reach the end of the list
   self._craft_order_list:register_stuck_order(self._order:get_id())

   -- Show a notification to the player if needed
   local recipe = self._order:get_recipe()
   radiant.events.trigger(self._craft_order_list, 'stonehearth:cant_reach_ingredients',
                           {
                              ingredient = event_args.ingredient,
                              recipe_name = recipe.display_name or recipe.recipe_name or recipe.recipe_key
                           })

   -- Destroy the current collecting task so that the craft items orchestrator knows that something went wrong
   self:destroy()
end

return AceCollectIngredients
