local AceTownCallHandler = class()

function AceTownCallHandler:get_current_immigration_requirements(session, response)
   local num_citizens = stonehearth.population:get_population(session.player_id):get_citizen_count()
   local game_mode_json = stonehearth.game_creation:get_game_mode_json()
   local game_mode_modifier = game_mode_json.immigration_worth_multiplier or 1
   
   local function simplify_to_significant_figures(num, figures)
      local x = figures - math.ceil(math.log10(math.abs(num)))
      return math.floor(num * (10 ^ x) + 0.5) / (10 ^ x)
   end
   local function compute_requirements(type, figures)
      local equation = stonehearth.constants.immigration_requirements[type]
      equation = string.gsub(equation, 'num_citizens', num_citizens)
      local fn = loadstring('return ' .. equation)
      local value = fn() * game_mode_modifier
      return simplify_to_significant_figures(value, figures)
   end
   return {
      food = compute_requirements('food', 2),
      net_worth = compute_requirements('net_worth', 3),
   }
end

return AceTownCallHandler
