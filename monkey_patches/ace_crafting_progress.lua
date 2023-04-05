local CraftingProgress = radiant.mods.require('stonehearth.components.workshop.crafting_progress')
local AceCraftingProgress = radiant.class()

AceCraftingProgress._ace_old_destroy = CraftingProgress.__user_destroy
function AceCraftingProgress:destroy()
   self:destroy_working_ingredient()
   self:_ace_old_destroy()
end

function AceCraftingProgress:destroy_working_ingredient()
   if self._sv._working_ingredient then
      radiant.entities.destroy_entity(self._sv._working_ingredient)
      self._sv._working_ingredient = nil
   end
end

-- Paul: changed the parameters and the second line of the function
-- also added workshop crafting modifier logic
function AceCraftingProgress:create(order, crafter)
   local recipe = order:get_recipe()
   crafter = crafter or order:get_current_crafter()
   local crafter_component = crafter:get_component('stonehearth:crafter')
   self._sv.crafter_id = crafter:get_id()

   --The recipes may call for different effects (based on the workbench type)
   local effect = recipe.work_effect
   if not effect then
      effect = crafter_component:get_work_effect()
   end

   local game_seconds
   if recipe.effort then
      -- 1 effort = 1 in-game minute of crafting time
      local game_time_per_effort = stonehearth.calendar:parse_duration(stonehearth.constants.crafting.GAME_TIME_PER_EFFORT)
      game_seconds = (game_time_per_effort * recipe.effort) / crafter_component:get_work_rate()
   else
      -- If no effort specified, use work units, which correspond to the number of times to play the work animation
      local secs_per_work_unit = stonehearth.calendar:parse_duration(
         stonehearth.constants.crafting.secs_per_work_unit.effect[effect] or
         stonehearth.constants.crafting.secs_per_work_unit.DEFAULT)
      game_seconds = secs_per_work_unit * recipe.work_units
   end

   self._sv.working_ingredient_uri = recipe.working_ingredient

   self._sv.workshop_modifier = 1
   self._sv.game_seconds_total_raw = game_seconds

   self._sv.game_seconds_total = radiant.math.round(game_seconds)
end

AceCraftingProgress._ace_old_get_duration = CraftingProgress.get_duration
function AceCraftingProgress:get_duration()
   local crafter = radiant.entities.get_entity(self._sv.crafter_id)
   if crafter then
      local workshop = crafter:get_component('stonehearth:crafter'):get_current_workshop()
      if workshop then
         local workshop_modifier = workshop:get_component('stonehearth:workshop'):get_crafting_time_modifier()
         if workshop_modifier ~= self._sv.workshop_modifier then
            self._sv.workshop_modifier = workshop_modifier
            self._sv.game_seconds_total = radiant.math.round(self._sv.game_seconds_total_raw * workshop_modifier)
         end
      end
   end

   return self:_ace_old_get_duration()
end

AceCraftingProgress._ace_old_crafting_started = CraftingProgress.crafting_started
function AceCraftingProgress:crafting_started()
   -- if a working ingredient uri was specified, create that entity and replace the existing ingredients with it
   if self._sv.working_ingredient_uri and not self._sv._working_ingredient then
      local crafter = radiant.entities.get_entity(self._sv.crafter_id)
      local workshop = crafter and crafter:get_component('stonehearth:crafter'):get_current_workshop()
      local entity_container = workshop and workshop:get_component('entity_container')

      if entity_container then
         -- first remove/hide all other ingredients from the workshop
         for id, child in entity_container:each_child() do
            child:get_component('render_info'):set_visible(false)
         end

         local working_ingredient = radiant.entities.create_entity(self._sv.working_ingredient_uri, {owner = workshop})
         local container_entity_data = radiant.entities.get_entity_data(workshop, 'stonehearth:table')
         local offset = container_entity_data and container_entity_data.drop_offset and radiant.util.to_point3(container_entity_data.drop_offset)
         radiant.entities.add_child(workshop, working_ingredient)
         if offset then
            working_ingredient:add_component('mob'):move_to(offset)
         end
         self._sv._working_ingredient = working_ingredient
      end
   end

   self:_ace_old_crafting_started()
end

return AceCraftingProgress
