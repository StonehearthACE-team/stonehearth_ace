local CrafterInfoController = class()

local log = radiant.log.create_logger('crafter_info')

function CrafterInfoController:initialize()
   self._recipe_map = radiant.create_controller('stonehearth_ace:recipe_map')
   self._formatted_recipes = {}

   self._sv.player_id = nil
   self._sv._order_lists = {}
   self._sv._reserved_ingredients = {}
end

function CrafterInfoController:restore()
   if self._sv.order_lists then
      self._sv._order_lists = self._sv.order_lists
      self._sv.order_lists = nil
      self._sv._reserved_ingredients = self._sv.reserved_ingredients
      self._sv.reserved_ingredients = nil
      self.__saved_variables:mark_changed()
   end
end

function CrafterInfoController:create(player_id)
   self._sv.player_id = player_id
end

function CrafterInfoController:post_activate()
   self._kingdom_changed_listener = radiant.events.listen(_radiant, 'radiant:player_kingdom_changed',
                                                          self, self._on_player_kingdom_changed)
   
   self:_create_maps()
end

function CrafterInfoController:destroy()
   if self._kingdom_changed_listener then
      self._kingdom_changed_listener:destroy()
      self._kingdom_changed_listener = nil
   end

   if self._recipe_map then
      self._recipe_map:destroy()
      self._recipe_map = nil
   end
end

function CrafterInfoController:_on_player_kingdom_changed(args)
   -- since this can change what recipes they have access to, their controller needs to be recreated
   if args.player_id == self._sv.player_id then
      self:_create_maps()
   end
end

function CrafterInfoController:_create_maps()
   self._recipe_map:clear()
   self._sv._order_lists = {}

   log:debug('creating maps for %s...', self._sv.player_id)
   
   local player_id = self._sv.player_id
   local pop = stonehearth.population:get_population(player_id)
   local job_index = radiant.resources.load_json( pop:get_job_index() )

   -- Store all the crafters recipes and order lists
   for job_key, _ in pairs(job_index.jobs) do
      local job_info = stonehearth.job:get_job_info(player_id, job_key)
      -- If `job_info` contains a recipe list, then `job` is a crafter
      local recipe_list = job_info:is_enabled() and job_info:get_recipe_list()
      if recipe_list then
         local order_list = job_info:get_order_list()
         table.insert(self._sv._order_lists, order_list)

         for category_name, category_data in pairs(recipe_list) do
            if not category_data.recipes then
               log:warning('%s has no recipes to process', category_name)
            else
               for recipe_name, recipe_data in pairs(category_data.recipes) do
                  -- Check if the recipe's workshop has a valid uri first
                  local workshop_uri = recipe_data.recipe.workshop
                  if workshop_uri and not stonehearth.catalog:get_catalog_data(workshop_uri) then
                     log:error('For recipe "%s": the workshop uri "%s" does not exist as an alias in its manifest',
                        recipe_name, workshop_uri)
                  else
                     if not recipe_data.recipe.ace_smart_crafter_ignore then  -- ignore recipes that are explicitly marked to be ignored by smart crafter
                        local formatted_recipe = self:_format_recipe(recipe_name, recipe_data.recipe)

                        if not formatted_recipe then
                           -- if there's something wrong with the recipe data, don't actually map it
                           log:debug('Skipping recipe "%s" because there\'s somethign wrong with it', recipe_name)
                        else
                           local keys = formatted_recipe.products

                           if not next(keys) then
                              log:error('For recipe "%s": no produced item exists as an alias in its manifest', recipe_name)
                           else
                              self._formatted_recipes[self:_get_recipe_key(recipe_data.recipe)] = formatted_recipe
                              self._recipe_map:add(keys, {
                                 job_key = job_key,
                                 job_info = job_info,
                                 order_list = order_list,
                                 recipe = formatted_recipe,
                              })
                           end
                        end
                     end
                  end
               end
            end
         end
      end
   end

   log:debug('finished creating maps for %s', self._sv.player_id)
end

function CrafterInfoController:_format_recipe(name, recipe)
   -- Format recipe to match show_team_workshop.js:_buildRecipeArray()
   local formatted_recipe = radiant.shallow_copy(recipe)

   -- Add information pertaining the workshop
   local workshop_uri = recipe.workshop
   formatted_recipe.hasWorkshop = workshop_uri ~= nil
   if formatted_recipe.hasWorkshop then
      local workshop_data = radiant.resources.load_json(workshop_uri)
      formatted_recipe.workshop = {
         name = workshop_data.entity_data["stonehearth:catalog"].display_name,
         icon = workshop_data.entity_data["stonehearth:catalog"].icon,
         uri  = workshop_uri,
      }
   end

   -- Add extra information to each ingredient in the recipe
   local formatted_ingredients = {}
   for _, ingredient in ipairs(recipe.ingredients) do
      local formatted_ingredient = {}

      if ingredient.material then
         local constants = radiant.resources.load_json('/stonehearth/data/resource_constants.json')

         formatted_ingredient.kind       = 'material'
         formatted_ingredient.material   = ingredient.material
         formatted_ingredient.identifier = self:_sort_material(ingredient.material)
         local resource = constants.resources[ingredient.material]
         if resource then
            formatted_ingredient.name = resource.name
            formatted_ingredient.icon = resource.icon
         end
      elseif ingredient.uri then
         local ingredient_data = radiant.resources.load_json(ingredient.uri, true, false)

         if not ingredient_data then
            log:error('recipe "%s" has invalid ingredient "%s"', name, ingredient.uri)
            return
         end

         formatted_ingredient.kind       = 'uri'
         formatted_ingredient.identifier = ingredient.uri

         if ingredient_data.components then
            formatted_ingredient.name = ingredient_data.entity_data["stonehearth:catalog"].display_name
            formatted_ingredient.icon = ingredient_data.entity_data["stonehearth:catalog"].icon
            formatted_ingredient.uri  = ingredient.uri

            if ingredient_data.components['stonehearth:entity_forms'] and ingredient_data.components['stonehearth:entity_forms'].iconic_form then
               formatted_ingredient.identifier = ingredient_data.components['stonehearth:entity_forms'].iconic_form
            end
         end
      else
         -- this ingredient has neither a material nor a uri
         log:error('recipe "%s" has invalid ingredient: %s', name, radiant.util.table_tostring(ingredient))
         return
      end

      formatted_ingredient.count = ingredient.count

      table.insert(formatted_ingredients, formatted_ingredient)
   end
   formatted_recipe.ingredients = formatted_ingredients
   formatted_recipe.cost = self:_get_recipe_cost(formatted_ingredients)

   -- Get the produces uris as well as the material tags of the recipe's products
   local products = {}
   for _, product in ipairs(recipe.produces) do
      if not products[product.item] then
         products[product.item] = 1
      else
         products[product.item] = products[product.item] + 1
      end
   end

   if recipe.ace_smart_crafter_consider_as then
      for _, product in ipairs(recipe.ace_smart_crafter_consider_as) do
         if not products[product.item] then
            products[product.item] = 1
         else
            products[product.item] = products[product.item] + 1
         end
      end
   end

   local all_products = {}
   formatted_recipe.product_materials = {}
   for product, count in pairs(products) do
      local catalog_data = radiant.resources.load_json(product, true, false)
      if not catalog_data then
         log:error('recipe "%s" has invalid product "%s"', name, product)
         return
      end

      local product_catalog = catalog_data and catalog_data.entity_data and catalog_data.entity_data["stonehearth:catalog"]

      -- first verify that the recipe has catalog data and is not for a raw resource/wealth
      -- (category "resources/wealth"; if it's not raw, it should be "refined" or something else)
      if product_catalog and
            (product_catalog.category ~= 'resources' and product_catalog.category ~= 'wealth' or recipe.ace_smart_crafter_skip_category_filter) then

         all_products[product] = count
         
         if product_catalog.material_tags then
            local mat_tags = product_catalog.material_tags
            if type(mat_tags) == 'string' then
               mat_tags = radiant.util.split_string(mat_tags, ' ')
            end

            -- store a material map instead of a string or sequence so we can easily check it when looking for recipe matches
            local mat_map = {}
            for _, mat in ipairs(mat_tags) do
               mat_map[mat] = true
               if not all_products[mat] then
                  all_products[mat] = count
               else
                  all_products[mat] = all_products[mat] + count
               end
            end

            formatted_recipe.product_materials[product] = mat_map
         end
      end
   end
   formatted_recipe.products = all_products

   return formatted_recipe
end

-- Get the total cost of crafting a recipe:
-- the amount of ingredients used and their respective value,
-- how many ingredients are missing and how much it would cost to craft them.
--
function CrafterInfoController:_get_recipe_cost(ingredients)
   local total_cost = 0

   -- TODO: check if the ingredient is available, if not then check its recipe's cost (or multiply its cost by 2)
   for _, ingredient in pairs(ingredients) do
      local cost = 0
      if ingredient.kind == 'material' then
         local uris = stonehearth_ace.crafter_info:get_uris(ingredient.material)
         _, cost = self:_get_least_valued_entity(uris)
      else -- ingredient.kind == 'uri'
         _, cost = self:_get_least_valued_entity({[ingredient.uri] = true})
      end
      total_cost = total_cost + cost * ingredient.count
   end

   return total_cost
end

-- Get the lowest valued entity, and its cost, from a list of uris.
--
function CrafterInfoController:_get_least_valued_entity(uris)
   local least_valued_uri = nil
   local lowest_value = 0
   for uri, _ in pairs(uris) do
      -- if it doesn't have a sell_cost specified, assume a very high value
      local catalog_data = stonehearth.catalog:get_catalog_data(uri)
      if not catalog_data then
         log:error('no catalog data for "%s"')
      end
      local value = catalog_data and catalog_data.sell_cost or 999
      if value < lowest_value or not least_valued_uri then
         least_valued_uri = uri
         lowest_value = value
      end
   end
   return least_valued_uri, lowest_value
end

function CrafterInfoController:_sort_material(material)
   local tags = radiant.util.split_string(material, ' ')
   table.sort(tags)

   return table.concat(tags, ' ')
end

function CrafterInfoController:get_player_id()
   return self._sv.player_id
end

function CrafterInfoController:get_formatted_recipe(recipe)
   return self._formatted_recipes[self:_get_recipe_key(recipe)]
end

function CrafterInfoController:_get_recipe_key(recipe)
   return recipe.recipe_name or recipe
end

function CrafterInfoController:get_possible_recipes(tags)
   return self._recipe_map:intersecting_values(tags)
end

function CrafterInfoController:get_order_lists()
   return self._sv._order_lists
end

function CrafterInfoController:is_product_maintained(product_uri)
   for _, order_list in pairs(self._sv._order_lists) do
      if order_list:is_product_maintained(product_uri) then
         return true
      end
   end
   return false
end

function CrafterInfoController:get_reserved_ingredients(ingredient_type)
   return self._sv._reserved_ingredients[ingredient_type] or 0
end

function CrafterInfoController:add_to_reserved_ingredients(ingredient_type, amount)
   -- uncomment logging when we want to see the table's contents
   --log:debug('current reserved list: %s', radiant.util.table_tostring(self._sv._reserved_ingredients))
   log:debug('adding %d of "%s" to the reserved list', amount, ingredient_type)

   if not self._sv._reserved_ingredients[ingredient_type] then
      self._sv._reserved_ingredients[ingredient_type] = amount
   else
      self._sv._reserved_ingredients[ingredient_type] = self._sv._reserved_ingredients[ingredient_type] + amount
   end
end

function CrafterInfoController:remove_from_reserved_ingredients(ingredient_type, amount)
   if not self._sv._reserved_ingredients[ingredient_type] then
      return
   end

   -- uncomment logging when we want to see the table's contents
   --log:debug('current reserved list: %s', radiant.util.table_tostring(self._sv._reserved_ingredients))
   log:debug('removing %d of "%s" from the reserved list', amount, ingredient_type)

   self._sv._reserved_ingredients[ingredient_type] = self._sv._reserved_ingredients[ingredient_type] - amount
   if self._sv._reserved_ingredients[ingredient_type] <= 0 then
      self._sv._reserved_ingredients[ingredient_type] = nil
   end
end

return CrafterInfoController
