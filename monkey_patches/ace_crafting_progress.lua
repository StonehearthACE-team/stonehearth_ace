local CraftingProgress = radiant.mods.require('stonehearth.components.workshop.crafting_progress')
local AceCraftingProgress = radiant.class()

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

   self._sv.workshop_modifier = 1
   self._sv.game_seconds_total_raw = game_seconds

   self._sv.game_seconds_total = radiant.math.round(game_seconds)
end

AceCraftingProgress._old_get_duration = CraftingProgress.get_duration
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

   return self:_old_get_duration()
end

return AceCraftingProgress
