local log = radiant.log.create_logger('game_master.encounters.dialog_tree')
local AceDialogTreeEncounter = class()

function AceDialogTreeEncounter:_transition_to_node(name)
   local ctx = self._sv.ctx
   local info = self._sv._info

   local node = self._sv.dialog_tree[name]
   if not node then
      log:error('no dialog tree node named \"%s\"', name)
      ctx.arc:terminate(ctx)
      return
   end

   local bulletin = self._sv.bulletin
   if not bulletin then
      local player_id = ctx.player_id
      bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
                                    :set_ui_view('StonehearthDialogTreeBulletinDialog')
                                    :set_callback_instance(self)
                                    :set_type(info.bulletin_type or 'quest')
                                    :set_sticky(true)
                                    :set_keep_open(true)
                                    :set_close_on_handle(false)

      if self._sv._i18n_data then
         for i18n_var_name, i18n_var_path in pairs(self._sv._i18n_data) do
            local i18n_var = ctx:get(i18n_var_path) or i18n_var_path
            if i18n_var then
               bulletin:add_i18n_data(i18n_var_name, i18n_var)
            end
         end
      end

      self._sv.bulletin = bulletin
   end

   local bulletin_data = radiant.deep_copy(node.bulletin)
   bulletin_data.zoom_to_entity = node.bulletin.zoom_to_entity and ctx:get(node.bulletin.zoom_to_entity) or nil
   bulletin:set_data(bulletin_data)
end

return AceDialogTreeEncounter
