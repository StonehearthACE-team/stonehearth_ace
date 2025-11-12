local AceCityTierAchieved = class()

function AceCityTierAchieved:_open_herald_dialog()
   local bulletin = self._sv.bulletin
   if not bulletin then
      local player_id = self._sv.ctx.player_id
      local info = self._sv._info
      self._sv._town_name = stonehearth.town:get_town(player_id):get_town_name()
      self:_set_herald_dialog_data()
      bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
                                    :set_ui_view('StonehearthDialogTreeBulletinDialog')
                                    :set_callback_instance(self)
                                    :set_type(info.bulletin_type or 'town_lvlup')
                                    :set_sticky(true)
                                    :set_keep_open(true)
                                    :set_close_on_handle(false)
                                    :add_i18n_data('town_name', self._sv._town_name)
      self._sv.bulletin = bulletin
   end
   bulletin:set_data(self._sv.bulletin_data)
   self.__saved_variables:mark_changed()
end

return AceCityTierAchieved
