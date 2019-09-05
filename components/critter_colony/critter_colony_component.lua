local CritterColonyComponent = class()

function CritterColonyComponent:initialize()
end

function CritterColonyComponent:activate()
   self._json = radiant.entities.get_json(self)
   if self._json then
      self._seasonal_buffs = self._json.seasonal_buffs
   end
end

function CritterColonyComponent:post_activate()
   if not self._json then
      self._entity:remove_component('stonehearth_ace:critter_colony')
      return
   end
   self:_create_listeners()
end

function CritterColonyComponent:_create_listeners()
   if self._seasonal_buffs then
      self._season_change_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
         self:_set_seasonal_buffs()
      end)

      self:_set_seasonal_buffs()
   end
end

function CritterColonyComponent:_set_seasonal_buffs()
   local current_season = stonehearth.seasons:get_current_season()
	local season_data = current_season and self._seasonal_buffs[current_season.id]
   for buff, setting in pairs(season_data) do
		if setting then 
			radiant.entities.add_buff(self._entity, buff)
		else
			radiant.entities.remove_buff(self._entity, buff)
		end
	end
end

function CritterColonyComponent:destroy()
	self:_destroy_listeners()
end

function CritterColonyComponent:_destroy_listeners()
	if self._season_change_listener then
      self._season_change_listener:destroy()
      self._season_change_listener = nil
   end
end

return CritterColonyComponent
