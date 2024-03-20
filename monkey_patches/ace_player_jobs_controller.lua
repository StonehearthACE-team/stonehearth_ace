--[[
   the goal is to allow for population-specific jobs for citizens of different populations in the same kingdom
   e.g., an orc footman may have different skills/traits than an ascendancy footman
   also then allows for promotion to kingdom-specific classes (e.g., goblin shaman in a non-goblin kingdom)
]]

local PlayerJobsController = require 'stonehearth.services.server.job.player_jobs_controller'
local AcePlayerJobsController = class()

local log = radiant.log.create_logger('player_jobs_controller')

-- For a given player, keep a table of job_info_controllers for that player

AcePlayerJobsController._ace_old_reset = PlayerJobsController.reset
function AcePlayerJobsController:reset()
   self:_ace_old_reset()
   
   self:_ensure_all_job_indexes()
end

function AcePlayerJobsController:post_activate()
   self:_ensure_all_job_indexes()
end

function AcePlayerJobsController:_ensure_all_job_indexes()
   -- create all job info controllers so the client is aware of all possible recipes for your faction's crafters
   -- even if you haven't promoted your hearthlings to those jobs yet
   self:_ensure_job_index()
   
   local pop = stonehearth.population:get_population(self._sv.player_id)
   for id, citizen in pop:get_citizens():each() do
      if citizen:is_valid() then
         local job = citizen:get_component('stonehearth:job')
         local pop_override = job and job:get_population_override()
         if pop_override then
            self:_ensure_job_index(pop_override)
         end
      end
   end

   log:debug('ensuring all job controllers for %s...', tostring(self._sv.player_id))
   if self._job_index and self._job_index.jobs then
      for job_key, _ in pairs(self._job_index.jobs) do
         log:debug('ensuring "%s"', job_key)
         self:_ensure_job_id(job_key)
      end
   end
end

function AcePlayerJobsController:is_product_maintained(product_uri)
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(self._sv.player_id)
   return crafter_info:is_product_maintained(product_uri)
end

function AcePlayerJobsController:request_craft_product(product_uri, amount, building, require_exact, insert_order, condition, associated_orders, current_recipe)
   log:debug('request_craft_product( %s, %s, %s, %s, %s, %s, %s, %s )',
         product_uri, amount, tostring(building), tostring(require_exact), tostring(insert_order), tostring(condition), tostring(associated_orders), tostring(current_recipe))
   -- first try it with requiring exact; that way we don't default to a secondary option if the primary is available
   if not require_exact then
      local result = self:request_craft_product(product_uri, amount, building, true, insert_order, condition, associated_orders, current_recipe)
      if result ~= nil then
         return result
      end
   end

   -- TODO: this can be reworked to call crafter_info directly
   -- then it can just do the sort and pick the best recipe to use
   -- and call that job_info controller only
   -- craft_order_list will need to be patched to call this then
   local products = not require_exact and radiant.entities.get_alternate_uris(product_uri) or {[product_uri] = true}

   -- if no condition or associated orders are specified and the product is already being maintained, don't create a new craft order for it
   if not condition and not associated_orders then
      for product, consider in pairs(products) do
         if consider and self:is_product_maintained(product) then
            return false
         end
      end
   end

   local choices = self:_get_recipe_info_from_products(products, amount, associated_orders, current_recipe)

   -- prefer craftable recipes (has job and level requirement)
   table.sort(choices, function(a, b)
      if a.can_craft and b.can_craft then
         return a.cost < b.cost
      elseif a.can_craft then
         return true
      elseif b.can_craft then
         return false
      elseif a.has_job and not b.has_job then
         return true
      elseif b.has_job and not a.has_job then
         return false
      else
         return (a.recipe_info.recipe.level_requirement or 1) < (b.recipe_info.recipe.level_requirement or 1)
      end
   end)

   -- select the "best" option
   local selection = choices[1]

   if selection then
      local order = selection.recipe_info.order_list:request_order_of(
            self._sv.player_id, selection.recipe_info, selection.produces, amount, building, insert_order, condition, associated_orders)
      if order then
         -- it's just true if the order didn't need to be created
         -- otherwise it returns the actual order
         if order ~= true then
            return order
         else
            return false
         end
      end
   end
end

function AcePlayerJobsController:get_craftable_recipes_for_product(product_uri, require_exact)
   -- first try it with requiring exact; that way we don't default to a secondary option if the primary is available
   if not require_exact then
      local result = self:get_craftable_recipes_for_product(product_uri, true)
      if result ~= nil then
         return result
      end
   end

   local products = not require_exact and radiant.entities.get_alternate_uris(product_uri) or {[product_uri] = true}
   local choices = self:_get_recipe_info_from_products(products, 1)
   local craftable = {}

   for _, choice in ipairs(choices) do
      if choice.can_craft and choice.has_job and
            (choice.recipe_info.recipe.level_requirement or 1) <= choice.recipe_info.job_info:get_highest_level() then
         table.insert(craftable, choice.recipe_info)
      end
   end

   return craftable
end

-- Used to get a recipe if it can be used to craft `ingredient`.
-- Returns information such as what the recipe itself and the order list used for it.
function AcePlayerJobsController:_get_recipe_info_from_products(products, amount, associated_orders, current_recipe)
   -- Take the cheapest recipe on a per-product basis
   local choices = {}
   local crafter_info = stonehearth_ace.crafter_info:get_crafter_info(self._sv.player_id)
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)

   for product, consider in pairs(products) do
      if consider then
         local possible = crafter_info:get_possible_recipes(product)
         for recipe_info, count in pairs(possible) do
            local allowed = true
            -- first make sure the recipe isn't already included in our associated orders or current recipe
            if current_recipe and recipe_info.recipe.job_alias == current_recipe.job_alias and recipe_info.recipe.recipe_key == current_recipe.recipe_key then
               allowed = false
            end
            if allowed and associated_orders then
               for _, associated_order in ipairs(associated_orders) do
                  local recipe = associated_order.order:get_recipe()
                  if recipe_info.recipe.job_alias == recipe.job_alias and recipe_info.recipe.recipe_key == recipe.recipe_key then
                     allowed = false
                     break
                  end
               end
            end

            -- verify that the recipe is accessible (if it requires unlocking, it is unlocked)
            if not allowed then
               log:error('queuing %s recipe %s would create a loop!', recipe_info.recipe.job_alias, recipe_info.recipe.recipe_key)
            elseif recipe_info.job_info:is_recipe_unlocked(recipe_info.recipe.recipe_key) then
               -- if we only want to craft one, we don't want to divide the cost by the number produced
               table.insert(choices, {
                  recipe_info = recipe_info,
                  produces = count,
                  cost = recipe_info.recipe.cost / math.min(count, amount),
                  has_job = recipe_info.job_info:has_members(),
                  can_craft = self:_can_craft_recipe(inventory, recipe_info),
               })
            end
         end
      end
   end

   return choices
end

function AcePlayerJobsController:_can_craft_recipe(inventory, recipe_info)
   -- check max crafter level of the specified job in the specified player's town
   -- to see if this recipe is currently craftable
   if recipe_info.job_info:get_highest_level() >= (recipe_info.recipe.level_requirement or 1) then
      -- check if it requires a workshop and that workshop exists
      if recipe_info.recipe.workshop then
         local workshop_uri = recipe_info.recipe.workshop.uri
   
         if self:_has_valid_workshop(inventory, workshop_uri) then
            return true
         else
            -- Not an exact match. Maybe a valid equivalent?
            local workshop_entity_data = radiant.entities.get_entity_data(workshop_uri, 'stonehearth:workshop')
            if workshop_entity_data then
               local equivalents = workshop_entity_data.equivalents
               if equivalents then
                  for _, equivalent in ipairs(equivalents) do
                     if self:_has_valid_workshop(inventory, equivalent) then
                        return true
                     end
                  end
               end
            end
         end

         return false
      end

      return true
   end
end

function AcePlayerJobsController:_has_valid_workshop(inventory, workshop_uri)
   local workshop_data = inventory:get_items_of_type(workshop_uri)
   return workshop_data and workshop_data.count > 0
end

function AcePlayerJobsController:remove_craft_orders_for_building(bid)
   for _, job_info in pairs(self._sv.jobs) do
      job_info:remove_craft_orders_for_building(bid)
   end
end

function AcePlayerJobsController:get_job(id, population_override)
   if not self._sv.jobs[id] then
      self:_ensure_job_id(id, population_override)
   end
   return self._sv.jobs[id]
end

function AcePlayerJobsController:_ensure_job_id(id, population_override)
   self:_ensure_job_index(population_override)

   if not self._sv.jobs[id] and self._job_index and self._job_index.jobs and self._job_index.jobs[id] then
      local info = self._job_index.jobs[id]
      self._sv.jobs[id] = radiant.create_controller('stonehearth:job_info_controller', info, self._sv.player_id)
      self.__saved_variables:mark_changed()
   end
end

--If we have kingdom data for this job, use that, instead of the default
function AcePlayerJobsController:_ensure_job_index(population_override)
   if not self._job_index then
      -- first load the general population data
      local pop = stonehearth.population:get_population(self._sv.player_id)
      local job_index_location = 'stonehearth:jobs:index'
      if pop then
         job_index_location = pop:get_job_index()
      end

      local job_index = radiant.resources.load_json(job_index_location)
      self._job_index = job_index
   end
   
   if not self._population_job_indexes then
      self._population_job_indexes = {}
   end
   if population_override and not self._population_job_indexes[population_override] then
      self._population_job_indexes[population_override] = {}
      -- then, if a population was specified, load that
      local pop = stonehearth.population:get_population(self._sv.player_id)
      if pop then
         local job_index_location = pop:get_job_index(population_override)
         -- only proceed if it's actually a different job index
         if job_index_location and job_index_location ~= pop:get_job_index() then
            local job_index = radiant.resources.load_json(job_index_location)
            self._population_job_indexes[population_override] = job_index

            -- and mix it into the regular job index
            local new_job_index = {}
            -- make sure we override any duplicate entries with our population's entry for that job
            -- create a new table since the original was the directly-loaded-from-json version
            for k, v in pairs(job_index) do
               new_job_index[k] = v
            end
            for k, v in pairs(self._job_index) do
               -- override any existing entries with these ones
               new_job_index[k] = v
            end

            self._job_index = new_job_index
         end
      end
   end
end

--If we have kingdom data for this job, use that, instead of the default
function AcePlayerJobsController:get_job_description(job_uri, population_override)
   self:_ensure_job_index(population_override)

   if self._job_index and self._job_index.jobs and self._job_index.jobs[job_uri] then
      return self._job_index.jobs[job_uri].description
   else
      return job_uri
   end
end

function AcePlayerJobsController:unlock_all_recipes_and_crops()
   for job, job_info in pairs(self._sv.jobs) do
      job_info:manually_unlock_all_recipes()
      if job == 'stonehearth:jobs:farmer' then 
         job_info:manually_unlock_all_crops()
      end
   end

   return true
end

return AcePlayerJobsController
