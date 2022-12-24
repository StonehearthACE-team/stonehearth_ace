local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
local weather_constants = constants.weather

local DynamicWeather = class()

local START_TIME = '9:30'

function DynamicWeather:initialize()
   self._sv._change_timer = nil
   self._target_weather = nil
end

function DynamicWeather:destroy()  
   self:_destroy_change_timer()
end

function DynamicWeather:_destroy_change_timer()
   if self._sv._change_timer then
      self._sv._change_timer:destroy()
      self._sv._change_timer = nil
   end
end

function DynamicWeather:start()
   self._target_weather = self:decide_for_change()

   if self._target_weather then
      self._sv._change_timer = stonehearth.calendar:set_persistent_alarm(self:decide_change_time(), radiant.bind(self, '_change_dynamic_weather'))
   end
end

function DynamicWeather:stop()
   self:_destroy_change_timer()
end

function DynamicWeather:decide_for_change()
   local current_weather = stonehearth.weather:get_current_weather()
   local current_weather_uri = current_weather and current_weather:get_uri()
   local dynamic_weather_data = current_weather_uri and weather_constants.DYNAMIC_WEATHER[current_weather_uri]

   if dynamic_weather_data and rng:get_real(0, 1) <= dynamic_weather_data.chance then
      return dynamic_weather_data.change_to
   end

   return false
end

function DynamicWeather:decide_change_time()
   return rng:get_int(10, 18) .. ':' .. rng:get_int(10, 59)
end

function DynamicWeather:_change_dynamic_weather()
   self:_destroy_change_timer()	
	
	stonehearth.weather:_switch_to(self._target_weather)
end

return DynamicWeather
