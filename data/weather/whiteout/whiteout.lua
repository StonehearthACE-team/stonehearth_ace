local WhiteoutWeather = class()

local START_TIME = '9:30'
local END_TIME = '20:15'
local UPDATE_INTERVAL = '25m'

function WhiteoutWeather:initialize()
   self._sv._start_timer = nil
   self._sv._end_timer = nil
   self._sv._update_timer = nil
	self._sv.alert_bulletin = nil
end

function WhiteoutWeather:start()
   self._sv._start_timer = stonehearth.calendar:set_persistent_alarm(START_TIME, radiant.bind(self, '_start_whiteout'))
end

function WhiteoutWeather:stop()
   if self._sv._start_timer then
      self._sv._start_timer:destroy()
      self._sv._start_timer = nil
   end
end

function WhiteoutWeather:_start_whiteout()
   self._sv._start_timer:destroy()
   self._sv._start_timer = nil	
	
	local bulletin_data = {
      title = "i18n(stonehearth_ace:data.weather.whiteout.bulletin_name)",
      notification_closed_callback = '_on_closed'
   }
	
	local players = stonehearth.player:get_non_npc_players()
   for player_id in pairs(players) do
		self._sv.alert_bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
            :set_callback_instance(self)
				:set_type("alert")
            :set_sticky(true)
            :set_data(bulletin_data)
   end
	
	self._sv._update_timer = stonehearth.calendar:set_persistent_interval('whiteout update', UPDATE_INTERVAL, radiant.bind(self, '_update'))
	self._sv._end_timer = stonehearth.calendar:set_persistent_alarm(END_TIME, radiant.bind(self, '_end_whiteout'))
end

function WhiteoutWeather:_update()
	local add_buff = function(entity)
      local location = radiant.entities.get_world_grid_location(entity)
      if not location then
         return
      end
      if stonehearth.terrain:is_sheltered(location) then
         return
      end
      
      radiant.entities.add_buff(entity, "stonehearth_ace:buffs:weather:whiteout")
   end

   self:_for_each_player_character(function(citizen)
       add_buff(citizen)
   end)

	self:_for_common_npc_character(function(npc)
      add_buff(npc)
   end)
end

function WhiteoutWeather:_for_each_player_character(fn)
   local pops = stonehearth.population:get_all_populations()
   for _, pop in pairs(pops) do
      if not pop:is_npc() then
         for _, citizen in pop:get_citizens():each() do
            fn(citizen)
         end
      end
   end
end

function WhiteoutWeather:_for_common_npc_character(fn)
   local pops = stonehearth.population:get_all_populations()
   for player_id, pop in pairs(pops) do
		if stonehearth.constants.weather.kingdoms_affected_by_weather[player_id] then
         for _, citizen in pop:get_citizens():each() do
            fn(citizen)
			end
		end
	end
end

function WhiteoutWeather:_end_whiteout()
	self._sv._end_timer:destroy()
   self._sv._end_timer = nil
	self._sv._update_timer:destroy()
	self._sv._update_timer = nil
	local bulletin = self._sv.alert_bulletin
   if bulletin then
      stonehearth.bulletin_board:remove_bulletin(bulletin)
      self._sv.alert_bulletin = nil
   end
end

function WhiteoutWeather:destroy()  
   if self._sv._start_timer then
      self._sv._start_timer:destroy()
      self._sv._start_timer = nil
   end
   if self._sv._end_timer then
      self._sv._end_timer:destroy()
      self._sv._end_timer = nil
   end
   if self._sv._update_interval then
      self._sv._update_interval:destroy()
      self._sv._update_interval = nil
   end
	if self._sv.alert_bulletin then
      self._sv.alert_bulletin:destroy()
      self._sv.alert_bulletin = nil
   end
end

return WhiteoutWeather
