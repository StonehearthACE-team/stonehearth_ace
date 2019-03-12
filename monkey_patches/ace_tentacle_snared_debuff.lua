local AceTentacleSnaredDebuffBuff = class()

-- override this function to add custom_data (for title)
function AceTentacleSnaredDebuffBuff:on_buff_added(entity, buff)
   self._entity = entity
   self._still_active = true
   self._uri = buff:get_uri()
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or not self._tuning.damage then
      return
   end

   local damage_tick = self._tuning.damage_tick or "30s"
   self._damage_tick_timer =  stonehearth.calendar:set_interval("Tentacle Trap Damage Timer", self._tuning.damage_tick, 
         function()
            self:_on_damage_tick()
         end)

   --Warn the player about it
   local display_name = radiant.entities.get_display_name(entity)
   local custom_name = radiant.entities.get_custom_name(entity)
   local custom_data = radiant.entities.get_custom_data(entity)
   local player_id = radiant.entities.get_player_id(entity)

   stonehearth.bulletin_board:post_bulletin(player_id)
      :set_type('alert')
      :set_data({
         title = 'i18n(stonehearth:data.gm.campaigns.titan.alert_tentacle_grab.title)',
         zoom_to_entity = entity
      })
      :add_i18n_data('entity_display_name', display_name)
      :add_i18n_data('entity_custom_name', custom_name)
      :add_i18n_data('entity_custom_data', custom_data)
      :set_sticky(true)
end

return AceTentacleSnaredDebuffBuff
