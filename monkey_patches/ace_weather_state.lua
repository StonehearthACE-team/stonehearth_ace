local WeatherState = require 'stonehearth.services.server.weather.weather_state'
local AceWeatherState = class()

AceWeatherState._ace_old_create = WeatherState.create
function AceWeatherState:create(uri)
   self:_ace_old_create(uri)
   self:_load_ace_values()
end

AceWeatherState._ace_old_restore = WeatherState.restore
function AceWeatherState:restore()
   self:_ace_old_restore()

   if not self._sv.sunlight then
      self:_load_ace_values()
   end
end

AceWeatherState._ace_old_start = WeatherState.start
function AceWeatherState:start(instigating_player_id)
   self:_ace_old_start()

   radiant.events.trigger(radiant, 'stonehearth_ace:weather_state_started', self)
end

function AceWeatherState:_load_ace_values()
   local json = radiant.resources.load_json(self._sv.uri, true, true)
   self._sv._base_sunlight = json.sunlight or 1
   self._sv.sunlight = self._sv._base_sunlight
   self._sv._base_humidity = json.humidity or 0
   self._sv.humidity = self._sv._base_humidity
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_unsheltered_animal_debuff()
   return self._sv.unsheltered_animal_debuff
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

function AceWeatherState:set_humidity(value)
   self._sv.humidity = value
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_humidity()
   return self._sv.humidity
end

function AceWeatherState:get_base_humidity()
   return self._sv._base_humidity
end

return AceWeatherState
