local WhiteoutWeather = class()

local START_TIME = '9:30'

function WhiteoutWeather:initialize()
   self._sv._start_timer = nil
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
end

function WhiteoutWeather:destroy()  
   if self._sv._start_timer then
      self._sv._start_timer:destroy()
      self._sv._start_timer = nil
   end
	if self._sv.alert_bulletin then
      self._sv.alert_bulletin:destroy()
      self._sv.alert_bulletin = nil
   end
end

return WhiteoutWeather
