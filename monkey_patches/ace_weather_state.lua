local WeatherState = require 'stonehearth.services.server.weather.weather_state'
local AceWeatherState = class()

AceWeatherState._old_create = WeatherState.create
function AceWeatherState:create(uri)
   self:_old_create(uri)
   self:_load_ace_values()
end

AceWeatherState._old_restore = WeatherState.restore
function AceWeatherState:restore()
   self:_old_restore()

   if not self._sv.sunlight then
      self:_load_ace_values()
   end
end

AceWeatherState._old_start = WeatherState.start
function AceWeatherState:start(instigating_player_id)
   self:_old_start()

   radiant.events.trigger(radiant, 'stonehearth_ace:weather_state_started', self)
end

function AceWeatherState:_load_ace_values()
   local json = radiant.resources.load_json(self._sv.uri, true, true)
   self._sv._base_sunlight = json.sunlight or 1
   self._sv.sunlight = self._sv._base_sunlight
   self._sv._base_precipitation = json.precipitation or 0
   self._sv.precipitation = self._sv._base_precipitation
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

function AceWeatherState:set_precipitation(value)
   self._sv.precipitation = value
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_precipitation()
   return self._sv.precipitation
end

function AceWeatherState:get_base_precipitation()
   return self._sv._base_precipitation
end

return AceWeatherState
