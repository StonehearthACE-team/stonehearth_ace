local WeatherCheck = class()

local log = radiant.log.create_logger('weather_check')

function WeatherCheck:start(ctx, info)
   local current_weather = stonehearth.weather:get_current_weather()
   local weather = current_weather and current_weather:get_uri()
   
   if not weather then
      log:debug('could not get the weather')
      return false
   end

   if info.not_bad_weather then
      if current_weather:is_bad_weather() then
         log:debug('current weather is bad')
         return false
      end
   elseif info.bad_weather then
      if not current_weather:is_bad_weather() then
         log:debug('current weather is not bad')
         return false
      end
   end

   if info.not_cold_weather then
      if current_weather:is_cold_weather() then
         log:debug('current weather is cold')
         return false
      end
   elseif info.cold_weather then
      if not current_weather:is_cold_weather() then
         log:debug('current weather is not cold')
         return false
      end
   end

   if info.not_frozen then
      if current_weather:is_frozen() then
         log:debug('current weather is frozen')
         return false
      end
   elseif info.frozen then
      if not current_weather:is_frozen() then
         log:debug('current weather is not frozen')
         return false
      end
   end

   if info.not_warm_weather then
      if current_weather:is_warm_weather() then
         log:debug('current weather is warm')
         return false
      end
   elseif info.warm_weather then
      if not current_weather:is_warm_weather() then
         log:debug('current weather is not warm')
         return false
      end
   end

   if info.not_dark_during_daytime then
      if current_weather:is_dark_during_daytime() then
         log:debug('current weather is not dark during daytime')
         return false
      end
   elseif info.dark_during_daytime then
      if not current_weather:is_dark_during_daytime() then
         log:debug('current weather is not dark during daytime')
         return false
      end
   end

   if info.forbidden_weathers then
      for _, forbidden_weather in ipairs(info.forbidden_weathers) do
         if forbidden_weather == weather then
            log:debug('current weather is forbidden')
            return false
         end
      end
   end
   
   if info.required_weathers then
      for _, required_weather in ipairs(info.required_weathers) do
         if required_weather == weather then 
            return true
         end
      end
      log:debug('current weather is not a required weather')
      return false
   end
   
   return true
end

return WeatherCheck