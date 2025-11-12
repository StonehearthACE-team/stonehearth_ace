local AceImmigration = class()

function AceImmigration:start(ctx, data)
   self._sv.player_id = ctx.player_id
   self._sv.immigration_data = data
   self._sv.ctx = ctx

   --Show a bulletin with food/net worth stats
   local message, success = self:_compose_town_report()
   local data = {
      title = self._sv.immigration_data.update_title,
      message = message
   }

   if success then
      data.conclusion = self._sv.immigration_data.conclusion_positive
      data.accepted_callback = "_on_accepted"
      data.declined_callback = "_on_declined"
   else
      data.conclusion = self._sv.immigration_data.conclusion_negative
      data.ok_callback = "_on_declined"
   end

   self._sv.immigration_bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
      :set_ui_view('StonehearthImmigrationReportDialog')
      :set_callback_instance(self)
      :set_type('new_citizen')
      :set_sticky(true)
      :set_data(data)

   --Make sure it times out if we don't get to it
   local wait_duration = self._sv.immigration_data.expiration_timeout
   self:_create_timer(wait_duration)
end

function AceImmigration:_find_requirements_by_type_and_pop(available, type, num_citizens, significant_figures)
   local game_mode_json = stonehearth.game_creation:get_game_mode_json()
   local game_mode_modifier = game_mode_json.immigration_worth_multiplier or 1
   local equation = stonehearth.constants.immigration_requirements[type]
   equation = string.gsub(equation, 'num_citizens', num_citizens)
   local target = self:_evaluate_equation(equation)
   target = target * game_mode_modifier
   target = self:_simplify_to_significant_figures(target, significant_figures)

   local label = self._sv.immigration_data[type .. '_label']

   local data = {
      label = label,
      available = available, 
      target = target
   }
   local success = available >= target
   return success, data
end

return AceImmigration