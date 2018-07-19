local CraftOrderList = radiant.mods.require('stonehearth.components.workshop.craft_order_list')
local AceCraftOrderList = class()

local log = radiant.log.create_logger('craft_order_list')

AceCraftOrderList._ace_old_add_order = CraftOrderList.add_order
-- In addition to the original add_order function (from craft_order_list.lua),
-- here it's also checking if the order has enough of the required ingredients and,
-- if it can be crafted, adds those ingredients as orders as well.
--
-- Furthermore, when maintaining orders, it makes sure that there are no more than
-- one instance of each recipe that's maintained.
--
function AceCraftOrderList:add_order(player_id, recipe, condition, is_recursive_call)
   local auto_craft_recipe_dependencies = radiant.util.get_config('auto_craft_recipe_dependencies', true)
   if not auto_craft_recipe_dependencies then
      return self:insert_order(player_id, recipe, condition)
   end

   local inv = stonehearth.inventory:get_inventory(player_id)
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(player_id)

   -- Process the recipe's ingredients to see if the crafter has all she needs for it
   for _, ingredient in pairs(recipe.ingredients) do
      local ingredient_id = ingredient.uri or ingredient.material

      log:debug('processing ingredient "%s"', ingredient_id)

      -- Step 1: `make`:
      --         See if there are enough of the asked ingredient in the inventory:
      --            if there is, continue to the next ingredient;
      --            if missing, go to step 2.
      --
      --         `maintain`:
      --         Simply get how much the ingredient asks for and set it as missing,
      --         go to step 2.

      local missing
      if condition.type == 'make' then
         local needed = condition.amount * ingredient.count
         local in_storage = self:_ace_get_ingredient_amount_in_storage(ingredient, inv)
         -- Go through and combine the orders in all the order lists
         local in_order_list = {}
         for _, order_list in ipairs(crafter_info:get_order_lists()) do
            local order_list_amount = order_list:ace_get_ingredient_amount_in_order_list(ingredient)
            for k, v in pairs(order_list_amount) do
               in_order_list[k] = (in_order_list[k] or 0) + v
            end
         end
         missing = math.max(needed - math.max(in_storage + in_order_list.total - crafter_info:get_reserved_ingredients(ingredient_id), 0), 0)

         log:debug('we need %d, have %d in storage, have %d in order list (%d of which are maintained), and %d reserved so we are missing %d (math is hard, right?)',
            needed, in_storage, in_order_list.total, in_order_list.maintain, crafter_info:get_reserved_ingredients(ingredient_id), missing)

         crafter_info:add_to_reserved_ingredients(ingredient_id, math.max(needed - in_order_list.maintain, 0))
      else -- condition.type == 'maintain'
         missing = ingredient.count

         log:debug('maintaining the recipe requires %d of this ingredient, searching if it can be crafted itself', missing)
      end

      if missing > 0 then

         -- Step 2: Check if the ingredient can be produced through a different recipe:
         --            if it does, proceed to step 3;
         --            if not, continue on to the next ingredient.

         local recipe_info = self:_ace_get_recipe_info_from_ingredient(ingredient, crafter_info)
         if recipe_info then
            log:debug('a "%s" can be made via the recipe "%s"', ingredient_id, recipe_info.recipe.recipe_name)

            -- Step 3: Recursively check on the ingredient's recipe.

            local new_condition = { type = condition.type }
            if condition.type == 'make' then
               new_condition.amount = missing
            else -- condition.type == 'maintain'
               new_condition.at_least = missing
            end

            log:debug('adding the recipe "%s" to %s %d of those',
               recipe_info.recipe.recipe_name, new_condition.type, missing)

            -- Add the new order to the appropiate order list
            recipe_info.order_list:add_order(player_id, recipe_info.recipe, new_condition, true)
         end
      end
   end

   local old_order_index
   if condition.type == 'maintain' and not condition.order_index then
      -- See if the order_list already contains a maintain order for the recipe:
      --    if it does, remake the order if its amount is lower than `missing`, otherwise ignore it;
      --    if it doesn't, simply add it as usual
      local order = self:_ace_find_craft_order(recipe.recipe_name, 'maintain')
      if order then
         log:debug('checking if maintain order "%s" is to be replaced', order:get_recipe().recipe_name)
         log:detail('this is %sa recursive call, the order\'s value is %d and the new one is %d',
            is_recursive_call and 'NOT ' or '',
            order:get_condition().at_least,
            condition.at_least)

         if not is_recursive_call or order:get_condition().at_least < tonumber(condition.at_least) then
            -- The order is to be replaced, so remove the current one so when the new one is added;
            -- there are no duplicates of the same recipe

            log:debug('replacing the order with %d as its new amount', condition.at_least)

            -- Note: It would be preferable to change the order's `at_least` value directly instead, but
            --       I haven't found a way to accomplish that *and* have the ui update itself instantly

            old_order_index = self:find_index_of(order:get_id())
            self:remove_order(order)
         else
            log:debug('an order already exists which fulfills the request')
            return true
         end
      end
   end

   local result = self:insert_order(player_id, recipe, condition, old_order_index)

   return result
end

function AceCraftOrderList:insert_order(player_id, recipe, condition, maintain_order_index)
	local result = self:_ace_old_add_order(player_id, recipe, condition)

	local old_order_index = condition.order_index or maintain_order_index
	if old_order_index then
		-- Change the order of the recipe to what its predecessor had

		-- Note: We could call the function `change_order_position` for this one,
		--       but it uses an order's id to find its index in the table. And since
		--       we know that the newly created order is in the last index; it seems
		--       like a waste of resources to just do that sort of operation. So
		--       we just copy that function's body here with that change in mind.

		local new_order_index = radiant.size(self._sv.orders) - 1
		local order = self._sv.orders[new_order_index]
		table.remove(self._sv.orders, new_order_index)
		table.insert(self._sv.orders, old_order_index, order)

		self:_on_order_list_changed()
	end
end

AceCraftOrderList._ace_old_delete_order_command = CraftOrderList.delete_order_command
-- In addition to the original delete_order_command function (from craft_order_list.lua),
-- here it's also making sure that the ingredients needed for the order is removed
-- from the reserved ingredients table.
--
function AceCraftOrderList:delete_order_command(session, response, order_id)
   local order = self._sv.orders[ self:find_index_of(order_id) ]
   if order then
      local condition = order:get_condition()

      if condition.type == 'make' and condition.remaining > 0 then
         self:remove_from_reserved_ingredients(order:get_recipe().ingredients,
                                               order_id,
                                               session.player_id,
                                               condition.remaining)
      end
   end

   return self:_ace_old_delete_order_command(session, response, order_id)
end

-- All within `ingredients` are removed from the reserved ingredients table.
-- `order_id` is the id of the order that we are to remove of.
-- `player_id` says which player id the order belongs to.
-- `multiple` says by how much the ingredients' count will be multiplied by,
-- if it's not specified it will get the value of 1.
--
function AceCraftOrderList:remove_from_reserved_ingredients(ingredients, order_id, player_id, multiple)
   multiple = multiple or 1
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(player_id)
   for _, ingredient in pairs(ingredients) do
      local in_order_list = self:ace_get_ingredient_amount_in_order_list(ingredient, order_id)
      local ingredient_id = ingredient.uri or ingredient.material
      local amount = math.max(ingredient.count * multiple - in_order_list.maintain, 0)

      crafter_info:remove_from_reserved_ingredients(ingredient_id, amount)
   end
end

-- Used to get a recipe if it can be used to craft `ingredient`.
-- Returns information such as what the recipe itself and the order list used for it.
--
function AceCraftOrderList:_ace_get_recipe_info_from_ingredient(ingredient, crafter_info)
   local item = ingredient.uri or ingredient.material
   local chosen_recipe = nil
   local chosen_recipe_cost = 0

   -- Take the cheapest recipe
   for _, recipe_info in pairs(crafter_info:get_possible_recipes(item)) do
      local recipe_cost = self:_ace_get_recipe_cost(recipe_info, crafter_info)
      if not chosen_recipe or recipe_cost < chosen_recipe_cost then
         chosen_recipe = recipe_info
         chosen_recipe_cost = recipe_cost
      end
   end

   return chosen_recipe
end

-- Get the total cost of crafting a recipe:
-- the amount of ingredients used and their respective value,
-- how many ingredients are missing and how much it would cost to craft them.
--
function AceCraftOrderList:_ace_get_recipe_cost(recipe_info, crafter_info)
   local total_cost = 0

   local ingredients = recipe_info.recipe.ingredients
   -- TODO: check if the ingredient is available, if not then check its recipe's cost (or multiply its cost by 2)
   for _, ingredient in pairs(ingredients) do
      local cost = 0
      if ingredient.kind == 'material' then
         local uris = crafter_info:get_uris(ingredient.material)
         _, cost = self:_ace_get_least_valued_entity(uris)
      else -- ingredient.kind == 'uri'
         _, cost = self:_ace_get_least_valued_entity({ingredient.uri})
      end
      total_cost = total_cost + cost * ingredient.count
   end

   return total_cost
end

-- Get the lowest valued entity, and its cost, from a list of uris.
--
function AceCraftOrderList:_ace_get_least_valued_entity(uris)
   local least_valued_uri = nil
   local lowest_value = 0
   for _, uri in ipairs(uris) do
      local value = stonehearth.catalog:get_catalog_data(uri).sell_cost
      if value < lowest_value or not least_valued_uri then
         least_valued_uri = uri
         lowest_value = value
      end
   end
   return least_valued_uri, lowest_value
end

-- Checking `inventory` to see how much of `ingredient` is available.
--
function AceCraftOrderList:_ace_get_ingredient_amount_in_storage(ingredient, inventory)
   local tracking_data = inventory:get_item_tracker('stonehearth:usable_item_tracker')
                                       :get_tracking_data()
   local ingredient_count = 0

   if ingredient.uri then
      local item = ingredient.uri
      local entity_forms = radiant.entities.get_component_data(ingredient.uri, 'stonehearth:entity_forms')
      if entity_forms and entity_forms.iconic_form then
         item = entity_forms.iconic_form
      end

      if tracking_data:contains(item) then
         ingredient_count = tracking_data:get(item).count
      end
   elseif ingredient.material then
      for _, item in tracking_data:each() do
         if radiant.entities.is_material(item.first_item, ingredient.material) then
            ingredient_count = ingredient_count + item.count
         end
      end
   end

   return ingredient_count
end

-- Checks this order list to see how much of `ingredient` it contains.
-- The optional `to_order_id` says that any orders with their id,
-- that are at least as great as that number, will be ignored.
--
function AceCraftOrderList:ace_get_ingredient_amount_in_order_list(ingredient, to_order_id)
   local ingredient_count = {
      make = 0,
      maintain = 0,
      total = 0,
   }

   for _, order in pairs(self._sv.orders) do
      if type(order) ~= 'number' then
         if to_order_id and order:get_id() >= to_order_id then
            break
         end
         local recipe = order:get_recipe()
         local condition = order:get_condition()

         if (ingredient.material
         and type(recipe.product_uri) == 'table'
         and recipe.product_uri.entity_data["stonehearth:catalog"].material_tags
         and self:_ace_matching_tags(ingredient.material, recipe.product_uri.entity_data["stonehearth:catalog"].material_tags))
         or (ingredient.uri
         and recipe.product_uri == ingredient.uri) then

            local amount = condition.remaining
            if condition.type == 'maintain' then
               amount = condition.at_least
            end
            ingredient_count[condition.type] = ingredient_count[condition.type] + amount

         end
      end
   end

   ingredient_count.total = ingredient_count.make + ingredient_count.maintain
   return ingredient_count
end

-- Checks to see if `tags_string1` is a sub-set of `tags_string2`.
-- Returns true if it is, else false.
--
function AceCraftOrderList:_ace_matching_tags(tags_string1, tags_string2)
   -- Hack!
   -- Add a space at the end to make the frontier pattern search succeed at all times
   tags_string2 = tags_string2 .. ' '
   -- gmatch will return either 1 tag or the empty string
   -- make sure we skip over the empty strings!
   for tag in tags_string1:gmatch("([^ ]*)") do
      -- use frontier pattern to find the tag,
      -- whilst making sure that it's a word-border search
      if tag ~= '' and not tags_string2:find("%f[%a%d_]".. tag .."%f[ ]") then
         return false
      end
   end
   return true
end

-- Gets the craft order which matches `recipe_name`, if an `order_type`
-- is defined, then it will also check for a match against it.
-- Returns nil if no match was found.
--
function AceCraftOrderList:_ace_find_craft_order(recipe_name, order_type)
   log:debug('finding a recipe for "%s"', recipe_name)
   log:debug('There are %d orders', radiant.size(self._sv.orders) - 1)

   for _, order in pairs(self._sv.orders) do
      if type(order) ~= 'number' then
         local order_recipe_name = order:get_recipe().recipe_name
         log:debug('evaluating order with recipe "%s"', order_recipe_name)

         if order_recipe_name == recipe_name and (not order_type or order:get_condition().type == order_type) then
            return order
         end
      end
   end

   return nil
end

return AceCraftOrderList
