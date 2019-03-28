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

   if not self._sv.sunlight or type(self._sv.unsheltered_debuff) == 'string' or type(self._sv.unsheltered_animal_debuff) == 'string' then
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
   self._sv.frozen = json.frozen or false
   
   if type(self._sv.unsheltered_debuff) == 'string' then
      self._sv.unsheltered_debuff = { self._sv.unsheltered_debuff }
   end
   if type(self._sv.unsheltered_animal_debuff) == 'string' then
      self._sv.unsheltered_animal_debuff = { self._sv.unsheltered_animal_debuff }
   end

   self.__saved_variables:mark_changed()
end

function AceWeatherState:_apply_buff()
   local add_buff = function(entity, buff)
      local location = radiant.entities.get_world_grid_location(entity)
      if not location then
         return
      end
      if stonehearth.terrain:is_sheltered(location) then
         return
      end
      if self._sv.unsheltered_resistance_buff and radiant.entities.has_buff(entity, self._sv.unsheltered_resistance_buff) then
         return
      end
      
      radiant.entities.add_buff(entity, buff)
   end

   -- Citizen debuff
   if self._sv.unsheltered_debuff then
		for _, unsheltered_debuff in ipairs(self._sv.unsheltered_debuff) do
			self:_for_each_player_character(function(citizen)
            add_buff(citizen, unsheltered_debuff)
         end)
		end
   end

   -- Pasture animal debuff
   if self._sv.unsheltered_animal_debuff then
		for _, unsheltered_animal_debuff in ipairs(self._sv.unsheltered_animal_debuff) do
			for player_id, _ in pairs(stonehearth.player:get_non_npc_players()) do
				for _, animal in pairs(stonehearth.town:get_town(player_id):get_pasture_animals()) do
					add_buff(animal, unsheltered_animal_debuff)
				end
			end
		end
   end
end

function AceWeatherState:get_unsheltered_animal_debuffs()
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

function AceWeatherState:get_frozen()
   return self._sv.frozen
end

return AceWeatherState
