local AceImmigration = class()

function AceImmigration:_find_requirements_by_type_and_pop(available, type, num_citizens, significant_figures)
   local game_mode_json = stonehearth.game_creation:get_game_mode_json()
   local game_mode_modifier = game_mode_json.immigration_worth_multiplier or 1
   local equation = stonehearth.constants.immigration_requirements[type]
   equation = string.gsub(equation, 'num_citizens', num_citizens)
   local target = self:_evaluate_equation(equation)
   target = target * game_mode_modifier
   target = self:_simplify_to_significant_figures(target, significant_figures)

   local label = self._sv.immigration_data[type .. '_label']

   local data = {
      label = label,
      available = available, 
      target = target
   }
   local success = available >= target
   return success, data
end

return AceImmigration