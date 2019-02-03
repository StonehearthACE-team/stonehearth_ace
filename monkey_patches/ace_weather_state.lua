local WeatherState = require 'stonehearth.services.server.weather.weather_state'
local AceWeatherState = class()

AceWeatherState._old_create = WeatherState.create
function AceWeatherState:create(uri)
   self:_old_create(uri)

   local json = radiant.resources.load_json(self._sv.uri, true, true)
   self._sv._base_sunlight = json.sunlight or 1
   self._sv.sunlight = self._sv._base_sunlight
   self.__saved_variables:mark_changed()
end

function AceWeatherState:set_sunlight(value)
   self._sv.sunlight = value
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_sunlight()
   return self._sv.sunlight
end

function AceWeatherState:get_base_sunlight()
   return self._sv._base_sunlight
end

return AceWeatherState
