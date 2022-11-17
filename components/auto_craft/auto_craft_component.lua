--[[
   TODO: handle player id changing
   add option to default output to separate output storage entity on top of this entity:
      - if it doesn't exist, create it
      - if it's not empty, don't output to it
      - set capacity to the number of products that don't have other outputs available to them
      - if we get destroyed, dump its contents on the ground
]]

local AutoCraftComponent = class()
local log = radiant.log.create_logger('auto_craft_component')

function AutoCraftComponent:restore()
   -- if we had a craft going, just cancel that craft (ingredient leases and storage reservations are already temporary)
   -- just need to cancel the progress and destroy the products we have in reserve
   self:_destroy_order()
end

function AutoCraftComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   -- self._entity:add_component('stonehearth:crafter')
   -- self._entity:add_component('stonehearth_ace:input')
   -- self._entity:add_component('stonehearth_ace:output')

   -- TODO: handle a changing player id
   self._player_id = radiant.entities.get_player_id(self._entity)

   -- make sure we have the necessary craft order list; this isn't actually used except to avoid exceptions from the craft order
   if not self._sv._craft_order_list then
      self._sv._craft_order_list = radiant.create_controller('stonehearth:craft_order_list', self._player_id)
   end
   -- just in case
   self._sv._craft_order_list:clear_all_orders()

   if self._json.fallback_output_on_top then

   end

   self._got_new_ingredients = false
end

function AutoCraftComponent:post_activate()
   self._storage = self._entity:get_component('stonehearth:storage')

   if not self._storage then
      log:debug('cannot set up auto-craft component for %s, missing storage component for ingredients', self._entity)
      return
   end

   self:_setup()
end

function AutoCraftComponent:destroy()
   self._got_new_ingredients = nil
   self:_destroy_listeners()
   self:_destroy_order()
end

function AutoCraftComponent:_destroy_listeners()
   if self._storage_item_added_listener then
      self._storage_item_added_listener:destroy()
      self._storage_item_added_listener = nil
   end
   if self._new_ingredient_listener then
      self._new_ingredient_listener:destroy()
      self._new_ingredient_listener = nil
   end
end

function AutoCraftComponent:_destroy_order()
   local workshop = self._entity:get_component('stonehearth:workshop')
   if workshop then
      workshop:finish_crafting_progress()
   end
   if self._sv._products then
      self:_destroy_items(self._sv._products)
      self._sv._products = nil
   end
   if self._sv._order then
      self._sv._order:destroy()
      self._sv._order = nil
   end
   if self._crafting_effect then
      self._crafting_effect:destroy()
      self._crafting_effect = nil
   end
   if self._crafting_finished_timer then
      self._crafting_finished_timer:destroy()
      self._crafting_finished_timer = nil
   end
end

function AutoCraftComponent:_setup()
   self:_load_all_recipes()

   self._storage_item_added_listener = radiant.events.listen(self._entity, 'stonehearth:storage:item_added', self, self._on_storage_item_added)
   self._try_crafting_from_recipes(self._all_recipes)
end

-- load up recipes from json and any saved recipes
-- saved recipes can include disabling default recipes!
function AutoCraftComponent:_load_all_recipes()
   local known_recipes = {}
   self:_load_recipes(known_recipes, self._json.recipes)
   self:_load_recipes(known_recipes, self._sv.recipes)

   -- TODO: check with town or player jobs controller to verify what recipes should currently be available for this auto-crafter?

   self._sv.recipes = known_recipes
   self.__saved_variables:mark_changed()

   self:_load_ingredient_map()
end

function AutoCraftComponent:_load_recipes(into, recipes)
   if recipes then
      for job, job_recipes in pairs(recipes) do
         local into_job = into[job]
         if not into_job then
            into_job = {}
            into[job] = into_job
         end
         for key, enabled in pairs(job_recipes) do
            into_job[key] = enabled or nil
         end
      end
   end
end

-- go through all the recipes we can make and index by ingredients
-- so when a new potential ingredient becomes available, we can see if any recipes become craftable
function AutoCraftComponent:_load_ingredient_map()
   local player_jobs = stonehearth.job:get_jobs_controller(self._player_id)
   local ingredient_uri_map = {}
   local ingredient_material_map = {}

   self._all_recipes = {}

   if player_jobs then
      for job, job_recipes in pairs(self._sv.recipes) do
         local job_info = player_jobs:get_job(job)

         if job_info then
            for category, category_data in pairs(job_info:get_recipe_list()) do
               if category_data.recipes then
                  for job_recipe, _ in pairs(job_recipes) do
                     for recipe_name, recipe_data in pairs(category_data.recipes) do
                        if recipe_data.recipe and recipe_data.recipe.recipe_key == job_recipe and recipe_data.recipe.ingredients then
                           for _, ingredient in ipairs(recipe_data.recipe.ingredients) do
                              if ingredient.count > 0 then
                                 local ing_key = ingredient.uri or ingredient.material
                                 local map = ingredient.uri and ingredient_uri_map or ingredient_material_map
                                 local map_entry = map[ing_key]
                                 if not map_entry then
                                    map_entry = {}
                                    map[ing_key] = map_entry
                                 end
                                 table.insert(map_entry, {
                                    job = job,
                                    recipe_key = job_recipe,
                                    recipe_data = recipe_data.recipe
                                 })
                                 table.insert(self._all_recipes, recipe_data.recipe)
                              end
                           end
                        end
                     end
                  end
               end
            end
         end
      end
   end

   self._ingredient_map = {
      uris = ingredient_uri_map,
      materials = ingredient_material_map
   }
end

function AutoCraftComponent:add_recipe(job, recipe)
   if not self._sv.recipes[job] or not self._sv.recipes[job][recipe] then
      self:_load_recipes(self._sv.recipes, { [job] = { [recipe] = true} })
      self.__saved_variables:mark_changed()

      self:_load_ingredient_map()
   end
end

function AutoCraftComponent:remove_recipe(job, recipe)
   if self._sv.recipes[job] and self._sv.recipes[job][recipe] then
      self._sv.recipes[job][recipe] = nil
      if not next(self._sv.recipes[job]) then
         self._sv.recipes[job] = nil
      end
      self.__saved_variables:mark_changed()

      self:_load_ingredient_map()
   end
end

-- this is triggered async, so we don't have to worry about products being added triggering it while we're crafting
function AutoCraftComponent:_on_storage_item_added(args)
   if self._sv._order then
      self._got_new_ingredients = true
      return
   end

   self._got_new_ingredients = false
   local recipes = self:_get_recipes_for_item(args.item)

   if #recipes > 0 then
      -- first sort by priority, if the recipes have that field
      table.sort(recipes, function(a, b)
         if a.priority and b.priority then
            return a.priority > b.priority
         elseif a.priority then
            return true
         else
            return false
         end
      end)

      self:_try_crafting_from_recipes(recipes)
   end
end

function AutoCraftComponent:_try_crafting_from_recipes(recipes)
   -- try to find a recipe for which we have all the ingredients and have room for the products
   for _, recipe in ipairs(recipes or {}) do
      if self:_try_craft_recipe(recipe) then
         return
      end
   end
end

function AutoCraftComponent:_get_recipes_for_item(item)
   -- first check uri ingredient map, then material map
   local recipes = {}

   local uri_recipes = self._ingredient_map.uris[item:get_uri()]
   if uri_recipes then
      for _, recipe in ipairs(uri_recipes) do
         table.insert(recipes, recipe.recipe_data)
      end
   end

   for material, material_recipes in pairs(self._ingredient_map.materials) do
      if radiant.entities.is_material(item, material) then
         for _, recipe in ipairs(material_recipes) do
            table.insert(recipes, recipe.recipe_data)
         end
      end
   end

   return recipes
end

function AutoCraftComponent:_item_fits_ingredient(item, ingredient)
   if ingredient.uri then
      return item:get_uri() == ingredient.uri
   else
      return radiant.entities.is_material(item, ingredient.material)
   end
end

function AutoCraftComponent:_try_craft_recipe(recipe)
   -- first check if we have all the ingredients
   local ingredients = {}
   -- first first make sure that there are enough items in storage that we even conceivably could have all the ingredients
   -- yeah, this could be cached, but... eeehhh... recipes are pretty simple
   local total_ing_count = 0
   for _, ingredient in ipairs(recipe.ingredients) do
      total_ing_count = total_ing_count + ingredient.count
   end
   if total_ing_count > self._storage:num_items() then
      log:debug('%s can\'t craft %s: %s total ingredients and only %s items in storage', self._entity, recipe.recipe_key, total_ing_count, self._storage:num_items())
      return false
   end

   local all_items = self._storage:get_items()
   for _, ingredient in ipairs(recipe.ingredients) do
      local num_found = 0
      for id, item in pairs(all_items) do
         if not ingredients[id] and self:_item_fits_ingredient(item, ingredient) and radiant.entities.can_acquire_lease(item, 'auto_craft', self._entity) then
            ingredients[id] = item
            num_found = num_found + 1
            if num_found >= ingredient.count then
               break
            end
         end
      end
      if num_found < ingredient.count then
         log:debug('%s can\'t craft %s: only %s (%s needed) of "%s"', self._entity, recipe.recipe_key, num_found, ingredient.count, ingredient.uri or ingredient.material)
         return false
      end
   end

   -- then create the products and try to put them somewhere
   local products = {}
   local num_products = 0
   for _, product in ipairs(recipe.produces) do
      local item = radiant.entities.create_entity(product.item, {owner = self._entity})
      products[item:get_id()] = item
      num_products = num_products + 1
   end

   local output_fn = radiant.entities.can_output_spawned_items(products, self._entity)
   if output_fn then
      -- we succeeded; complete the crafting
      self:_finish_crafting(recipe, ingredients, products, output_fn)
      return true
   end

   -- if that fails, determine if there's room in this entity's storage
   -- TODO: switch this with fallback_output_on_top
   if self._storage:num_items() + num_products <= self._storage:get_capacity() then
      output_fn = radiant.entities.can_output_spawned_items(products, nil, self._entity)
      if output_fn then
         -- we succeeded; complete the crafting
         self:_finish_crafting(recipe, ingredients, products, output_fn)
         return true
      end
   end

   -- if all of that fails, cancel the process
   self:_destroy_items(products)
end

function AutoCraftComponent:_finish_crafting(recipe, ingredients, products, output_fn)
   -- get leases on all the ingredients
   for id, ingredient in pairs(ingredients) do
      radiant.entities.acquire_lease(ingredient, 'auto_craft', self._entity, false)
   end

   -- store the products so they can be destroyed on reload
   self._sv._products = products

   -- set up crafting order and workshop progress
   -- don't use the order list the same way as other order lists are used; it makes lots of assumptions about the crafter (e.g., has a job component)
   local condition = {
      type = "make",
      amount = 1
   }
   self._sv._order = radiant.create_controller('stonehearth:craft_order', 0, recipe, condition, self._player_id, self._sv._craft_order_list)
   self._sv._order:set_crafting_status(self._entity)
   local workshop = self._entity:get_component('stonehearth:workshop')
   local progress = workshop:start_crafting_progress(self._sv._order)
   progress:crafting_started()

   -- listen for completion or cancellation
   self._crafting_finished_timer = stonehearth.calendar:set_timer("RunAutoCraftEffect finished", progress:get_duration(), function()
      --log:debug('%s crafting effect finished, proceeding with auto-crafting', self._entity)
      self:_destroy_items(ingredients)
      output_fn()
      progress:crafting_stopped()
      -- the products were successfully output (presumably), so we don't want to destroy them
      self._sv._products = nil
      self:_destroy_order()

      -- schedule a check to see if there were new ingredients added
      self._new_ingredient_listener = radiant.on_game_loop_once('consider crafting again', function()
         self._new_ingredient_listener = nil
         if self._got_new_ingredients then
            self._try_crafting_from_recipes(self._all_recipes)
         end
      end)
   end)
end

function AutoCraftComponent:_destroy_items(items)
   for id, item in pairs(items) do
      -- in case it's in our inventory, remove it first
      self._storage:remove_item(id)
      radiant.entities.destroy_entity(item)
   end
end

return AutoCraftComponent
