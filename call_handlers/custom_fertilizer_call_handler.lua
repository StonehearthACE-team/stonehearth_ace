local validator = radiant.validator
local CustomFertilizerCallHandler = class()

function CustomFertilizerCallHandler:set_growth_rate_multiplier_from_fertilizer(session, response, args)
   validator.expect_argument_types({'Entity'}, args and args.crop)
   
   local fertilizer_data = args and args.fertilizer_data
   local growth_rate_multiplier = fertilizer_data.growth_rate_multiplier
   if growth_rate_multiplier then
      local growing_comp = args.crop:get_component('stonehearth:growing')
      if growing_comp then
         growing_comp:modify_custom_growth_rate_multiplier(growth_rate_multiplier)
      end
   end
end

return CustomFertilizerCallHandler