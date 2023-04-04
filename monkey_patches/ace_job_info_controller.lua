-- changed self._craftable_recipes to contain an array of recipes for each product uri
-- so multiple different recipes for a particular product can be properly considered
local JobInfoController = require 'stonehearth.services.server.job.job_info_controller'
local AceJobInfoController = class()

local log = radiant.log.create_logger('job_info')

AceJobInfoController._ace_old_activate = JobInfoController.activate
function AceJobInfoController:activate()
   self._all_recipes = {}
   self:_ace_old_activate()
end

function AceJobInfoController:get_class_name()
   return self._sv.class_name
end

function AceJobInfoController:is_enabled()
   return self._description_json and self._description_json.enabled
end

function AceJobInfoController:foreach_available_recipes(fn)
   for _, recipe_data_tbl in pairs(self._craftable_recipes) do
      for _, recipe_data in ipairs(recipe_data_tbl) do
         if not recipe_data.manual_unlock or self._sv.manually_unlocked[recipe_data.recipe_key] then
            fn(recipe_data)
         end
      end
   end
end

function AceJobInfoController:job_can_craft(product_uri, require_unlocked, require_exact)
   if not self._sv.order_list then
      return false
   end

   local can_craft = self:_job_can_craft_exact(product_uri, require_unlocked)
   if can_craft or require_exact then
      return can_craft and product_uri
   end

   -- if we're not requiring an exact uri match, lookup any alternates
   local alternates = radiant.entities.get_alternate_uris(product_uri)
   if alternates then
      for uri, _ in pairs(alternates) do
         if uri ~= product_uri then
            if self:_job_can_craft_exact(uri, require_unlocked) then
               return uri
            end
         end
      end
   end

   return false
end

function AceJobInfoController:_job_can_craft_exact(product_uri, require_unlocked)
   local recipes = self._craftable_recipes[product_uri]
   if not recipes or not next(recipes) then
      return false
   end

   if require_unlocked then
      local available_recipe = false
      for _, recipe in ipairs(recipes) do
         if not recipe.manual_unlock or self._sv.manually_unlocked[recipe.recipe_key] then
            available_recipe = true
            break
         end
      end
      if not available_recipe then
         return false
      end
   end

   return true
end

function AceJobInfoController:is_recipe_unlocked(recipe_key)
   local recipe = self._all_recipes[recipe_key]
   return recipe and (not recipe.manual_unlock or self._sv.manually_unlocked[recipe_key])
end

function AceJobInfoController:queue_order_if_possible(product_uri, amount, building, require_exact, insert_order)
   -- this is no longer used except by deprecated building component
   -- call our new system just in case this is called
   local player_jobs_controller = stonehearth.job:get_jobs_controller(self._sv.player_id)
   return player_jobs_controller:request_craft_product(product_uri, amount, building, require_exact, insert_order)
end

function AceJobInfoController:remove_craft_orders_for_building(bid)
   if self._sv.order_list then
      self._sv.order_list:remove_craft_orders_for_building(bid)
   end
end

-- Functions for locking recipes again (Pawel)
function AceJobInfoController:manually_lock_recipe(recipe_key, ignore_missing)
   if not self._sv.recipe_list then
      radiant.verify(false, "Attempting to manually lock recipe %s when job %s does not have any recipes!", recipe_key, self._sv.alias)
      return false
   end
   local found_recipe = nil
   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            if recipe_data.recipe and recipe_data.recipe.recipe_key == recipe_key then
               found_recipe = recipe_data.recipe
               break
            end
         end
      end
      if found_recipe then
         break
      end
   end
   if not found_recipe then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually lock recipe %s when job %s does not have such a recipe!", recipe_key, self._sv.alias)
      end
      return false
   end

   self._sv.manually_unlocked[recipe_key] = nil
   self.__saved_variables:mark_changed()
   
   radiant.events.trigger(radiant, 'stonehearth_ace:crafting:recipe_hidden', {recipe_data = found_recipe})

   return true
end

function AceJobInfoController:manually_lock_recipe_category(category_key, ignore_missing)
   if not self._sv.recipe_list then
      radiant.verify(false, "Attempting to manually lock recipe category %s when job %s does not have any recipes!", category_key, self._sv.alias)
      return false
   end
   local found_category = false
   for category, category_data in pairs(self._sv.recipe_list) do
      if category == category_key and category_data.recipes then
         found_category = true
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            if recipe_data.recipe and recipe_data.recipe.recipe_key then
               self._sv.manually_unlocked[recipe_data.recipe.recipe_key] = nil
               -- radiant.events.trigger(radiant, 'stonehearth_ace:crafting:recipe_hidden', {recipe_data = recipe_data.recipe})
            end
         end
         self.__saved_variables:mark_changed()
      end
   end
   if not found_category then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually lock recipe category %s when job %s does not have such a recipe category!", category_key, self._sv.alias)
      end
      return false
   end

   return true
end

function AceJobInfoController:manually_unlock_all_recipes()
   if not self._sv.recipe_list then
      --radiant.verify(false, "Attempting to manually unlock recipes when job %s does not have any recipes!", self._sv.alias)
      return false
   end
   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            local recipe_key = recipe_data.recipe and recipe_data.recipe.recipe_key
            if recipe_key then
               if not self._sv.manually_unlocked[recipe_key] then
                  self._sv.manually_unlocked[recipe_key] = true
                  radiant.events.trigger(radiant, 'radiant:crafting:recipe_revealed', {recipe_data = recipe_data.recipe})
               end
            end
         end
      end
   end

   self.__saved_variables:mark_changed()
   return true
end

function AceJobInfoController:get_all_farmer_crops()
   return radiant.resources.load_json('stonehearth:farmer:all_crops').crops
end

function AceJobInfoController:get_all_herbalist_crops()
   return radiant.resources.load_json('stonehearth_ace:data:herbalist_planter:crops').crops
end

function AceJobInfoController:manually_unlock_crop(crop_key, ignore_missing)
   -- only farmers maintain a crop list, though it's used by other jobs (they all reference the farmer job info controller though)
   if self._sv.alias ~= 'stonehearth:jobs:farmer' then
      radiant.verify(false, "Attempting to manually unlock crop %s when job %s does not have crops!", crop_key, self._sv.alias)
      return false
   end
   
   local found_crop = false
   local farmer_crop_list = self:get_all_farmer_crops()
   local herbalist_crop_list = self:get_all_herbalist_crops()

   if not farmer_crop_list[crop_key] and not herbalist_crop_list[crop_key] then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually unlock crop %s when job %s does not have such a crop!", crop_key, self._sv.alias)
      end
      return false
   end

   local already_unlocked = self._sv.manually_unlocked[crop_key]
   if already_unlocked then
      return false
   end

   self._sv.manually_unlocked[crop_key] = true
   self.__saved_variables:mark_changed()
   return true
end

function AceJobInfoController:manually_unlock_all_crops()
   -- only farmers maintain a crop list, though it's used by other jobs (they all reference the farmer job info controller though)
   if self._sv.alias ~= 'stonehearth:jobs:farmer' then
      radiant.verify(false, "Attempting to manually unlock crops when job %s does not have crops!", self._sv.alias)
      return false
   end
   
   local farmer_crop_list = self:get_all_farmer_crops()
   local herbalist_crop_list = self:get_all_herbalist_crops()

   for crop_key, crop_data in pairs(farmer_crop_list) do
      self._sv.manually_unlocked[crop_key] = true
   end
   
   for crop_key, crop_data in pairs(herbalist_crop_list) do
      self._sv.manually_unlocked[crop_key] = true
   end

   self.__saved_variables:mark_changed()
   return true
end

--- Build the list sent to the UI from the json
--  Load each recipe's data and add it to the table
-- ACE: also set the category
function AceJobInfoController:_build_craftable_recipe_list(recipe_index_url)
   -- Note: this recipe list is recreated everytime we load the game.
   -- The reason it's in _sv is so we can easily send the recipe data to the client.
   self._sv.recipe_list = radiant.deep_copy(radiant.resources.load_json(recipe_index_url).craftable_recipes)

   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            local recipe_key = category .. ":" .. recipe_short_key
            if recipe_data.recipe == "" then
               --we've lost the recipe, for example, because it's been overridden by a mod
               self._sv.recipe_list[category].recipes[recipe_short_key] = nil
            else
               local recipe_json = radiant.resources.load_json(recipe_data.recipe, true, false)
               radiant.verify(recipe_json, 'unable to load crafting recipe %s for job %s! invalid json path %s', recipe_key, self._sv.alias, recipe_data.recipe or 'NIL')

               if not recipe_json then
                  self._sv.recipe_list[category].recipes[recipe_short_key] = nil
               else
                  recipe_data.recipe = radiant.deep_copy(recipe_json)
                  self:_initialize_recipe_data(recipe_key, recipe_data.recipe)
                  recipe_data.recipe.category = category
               end
            end
         end
      end
   end
   self.__saved_variables:mark_changed()
end

-- Prep the recipe data with any default values
function AceJobInfoController:_initialize_recipe_data(recipe_key, recipe_data)
   self._all_recipes[recipe_key] = recipe_data
   if not recipe_data.level_requirement then
      recipe_data.level_requirement = 0
   end
   recipe_data.job_alias = self._sv.alias
   recipe_data.recipe_key = recipe_key
   if recipe_data.produces then
      local first_product = recipe_data.produces[1]
      local uri = first_product.item
      recipe_data.product_uri = uri
      recipe_data.product_stacks = first_product.stacks

      local canonical = radiant.resources.convert_to_canonical_path(uri)
      radiant.verify(canonical, 'Crafter job %s has a recipe named "%s" that produces an item not in the manifest %s', self._sv.alias, recipe_key, uri)

      local products = {}
      for _, product in ipairs(recipe_data.produces) do
         local product_uri = product.item
         if not products[product_uri] then
            products[product_uri] = true
            local recipes = self._craftable_recipes[product_uri]
            if not recipes then
               recipes = {}
               self._craftable_recipes[product_uri] = recipes
            end
            table.insert(recipes, recipe_data)
         end
      end
   end
end

-- ACE: trigger an event if it changes
AceJobInfoController._ace_old__evaluate_highest_level = JobInfoController._evaluate_highest_level
function AceJobInfoController:_evaluate_highest_level()
   local highest_level = self._sv.highest_level
   self:_ace_old__evaluate_highest_level()
   if self._sv.highest_level ~= highest_level then
      radiant.events.trigger(stonehearth.job:get_jobs_controller(self._sv.player_id),
            'stonehearth_ace:job:highest_level_changed',
            { job_uri = self._sv.alias, highest_level = self._sv.highest_level })
   end
end

return AceJobInfoController
