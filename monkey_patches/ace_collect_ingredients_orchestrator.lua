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

      -- local max_distance_for_rating_sq = stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH
      -- local close_distance_for_rating_sq = stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH * stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH
      local rating_fn
      if self._prefer_high_quality then
         rating_fn = function(item, entity, entity_location, storage_location)
            local rating = radiant.entities.get_item_quality(item) / 3
            --return rating

				if radiant.entities.is_material(item, 'preferred_ingredient') then
               return rating
            end
				
				if radiant.entities.is_material(item, 'undesirable_ingredient') then
               rating = rating * 0.9
            end

            return rating
				
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
      else
         rating_fn = function(item, entity, entity_location, storage_location)
            local rating = 1 / radiant.entities.get_item_quality(item)
            --return rating

				if radiant.entities.is_material(item, 'preferred_ingredient') then
               return rating
            end
				
				if radiant.entities.is_material(item, 'undesirable_ingredient') then
               rating = rating * 0.9
            end

            return rating

            -- local p1 = entity_location or radiant.entities.get_world_grid_location(entity)
            -- local p2 = storage_location or radiant.entities.get_world_grid_location(item)

            -- if not p1 or not p2 then
            --    log:debug('LQ distance sq no location! %s (%s) -> %s (%s)', entity, p1 or 'NIL', item, p2 or 'NIL')
            --    return rating
            -- else
            --    local distance_sq = p1:distance_to_squared(p2) - close_distance_for_rating_sq
            --    local distance_score = (1 - math.min(1, distance_sq / max_distance_for_rating_sq))

            --    --log:debug('LQ distance sq %s and score %s for %s to %s', distance_sq, distance_score, entity, item)
               
            --    return rating * 0.8 + distance_score * 0.2
            -- end
         end
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
                               recipe_name = recipe.display_name or recipe.recipe_key
                            })

   -- Destroy the current collecting task so that the craft items orchestrator knows that something went wrong
   self:destroy()
end

return AceCollectIngredients
