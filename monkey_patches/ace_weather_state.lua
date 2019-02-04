local WeatherState = require 'stonehearth.services.server.weather.weather_state'
local AceWeatherState = class()

AceWeatherState._old_create = WeatherState.create
function AceWeatherState:create(uri)
   self:_old_create(uri)
   self:_load_base_sunlight()
end

AceWeatherState._old_restore = WeatherState.restore
function AceWeatherState:restore()
   self:_old_restore()

   if not self._sv.sunlight then
      self:_load_base_sunlight()
   end
end

AceWeatherState._old_start = WeatherState.start
function AceWeatherState:start(instigating_player_id)
   self:_old_start()

   radiant.events.trigger(radiant, 'stonehearth_ace:weather_state_started', self)
end

function AceWeatherState:_load_base_sunlight()
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
