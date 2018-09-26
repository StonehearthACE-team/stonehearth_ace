local USE_EFFORT = radiant.util.get_config('use_effort_crafting', false)

local CraftingProgress = radiant.mods.require('stonehearth.components.workshop.crafting_progress')
local AceCraftingProgress = radiant.class()

-- Paul: only chanced the parameters and the second line of the function
function AceCraftingProgress:create(order, crafter)
   local recipe = order:get_recipe()
   crafter = crafter or order:get_current_crafter()
   local crafter_component = crafter:get_component('stonehearth:crafter')
   --The recipes may call for different effects (based on the workbench type)
   local effect = recipe.work_effect
   if not effect then
      effect = crafter_component:get_work_effect()
   end

   local game_seconds
   -- TODO: once progress-bar crafting is in, remove config and check for recipe.effort instead
   if USE_EFFORT and recipe.effort then
      local game_time_per_effort = stonehearth.calendar:parse_duration(stonehearth.constants.crafting.GAME_TIME_PER_EFFORT)
      game_seconds = (game_time_per_effort * recipe.effort) / crafter_component:get_work_rate()
   else
      -- For mod and save compatibility
      local secs_per_work_unit = stonehearth.calendar:parse_duration(
         stonehearth.constants.crafting.secs_per_work_unit.effect[effect] or
         stonehearth.constants.crafting.secs_per_work_unit.DEFAULT)
      game_seconds = secs_per_work_unit * recipe.work_units
   end

   self._sv.game_seconds_total = radiant.math.round(game_seconds)
end

return AceCraftingProgress
