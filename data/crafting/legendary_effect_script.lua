local legendary_effect = {}

function legendary_effect.post_craft(ai, crafter, workshop, recipe, all_products)
   if ai then
      if crafter and recipe and stonehearth.client_state:get_client_gameplay_setting(crafter:get_player_id(), 'stonehearth_ace', 'show_legendary_craft_notification', true) then
         legendary_effect._show_bulletin(crafter, recipe)
      end

      ai:execute('stonehearth:run_effect', { effect = 'emote_confetti' })
      ai:execute('stonehearth:run_effect', { effect = 'emote_delighted' })
   end
end

function legendary_effect._show_bulletin(crafter, recipe)
   if not crafter or not recipe then
      return
   end

   local player_id = crafter:get_player_id()
   local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
      :set_data({
         title = 'i18n(stonehearth_ace:ui.game.bulletin.legendary_craft_bulletin.title)',
         zoom_to_entity = crafter
      })
      :set_active_duration('3h')
      :add_i18n_data('crafter_custom_name', radiant.entities.get_custom_name(crafter))
      :add_i18n_data('crafter_display_name', radiant.entities.get_display_name(crafter))
      :add_i18n_data('crafter_custom_data', radiant.entities.get_custom_data(crafter))
      :add_i18n_data('recipe', recipe.recipe_name)

   return bulletin
end

return legendary_effect