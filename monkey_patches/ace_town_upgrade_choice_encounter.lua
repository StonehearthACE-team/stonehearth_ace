local AceTownUpgradeChoiceEncounter = class()

function AceTownUpgradeChoiceEncounter:start(ctx, info)
   self._sv.ctx = ctx
   self._sv._info = info

   local opt_view = 'StonehearthTownUpgradeChoiceEncounterBulletinDialog'
   self._sv.bulletin_data = info
   self._sv.bulletin_data.on_selection_finished = '_on_selection_finished'
   self._sv.bulletin_data.title = 'i18n(stonehearth:ui.game.bulletin.town_upgrade_choice.title)'
   self._sv.bulletin_data.dialog_title = 'i18n(stonehearth:ui.game.bulletin.town_upgrade_choice.title)'

   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
                                    :set_callback_instance(self)
                                    :set_sticky(true)
                                    :set_close_on_handle(false)
                                    :set_type(info.bulletin_type or 'town_lvlup')

   self._sv.bulletin:set_data(self._sv.bulletin_data)
                    :set_ui_view(opt_view)
   self.__saved_variables:mark_changed()
end

return AceTownUpgradeChoiceEncounter
