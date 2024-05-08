local job_lib = {}
local log = radiant.log.create_logger('job_lib')

function job_lib.unlock_recipes(player_id, recipes_by_job_alias, bulletin_titles, show_recipe_unlock_bulletins, cb_instance)
   local bulletins = {}
   if bulletin_titles then
      for _, bulletin_title in ipairs(bulletin_titles) do
         --create a bulletin announcing the new recipes
         local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
               :set_sticky(true)
               :set_data({
                  title = bulletin_title,
                  notification_closed_callback = '_on_closed',
               })
         if cb_instance then
            bulletin:set_callback_instance(cb_instance)
         end
         table.insert(bulletins, bulletin)
      end
   end
   for job_alias, recipes in pairs(recipes_by_job_alias) do
      local job_info = stonehearth.job:get_job_info(player_id, job_alias)
      local recipe_data = {}
      for _, recipe_key in ipairs(recipes) do
         job_info:manually_unlock_recipe(recipe_key)
         table.insert(recipe_data, job_info:get_recipe(recipe_key))
         log:debug('unlocking %s recipe "%s"', job_alias, recipe_key)
      end

      if show_recipe_unlock_bulletins then
         local bulletin = job_lib.show_recipe_unlock_bulletin(player_id, job_alias, job_info:get_class_name(), recipe_data)
         -- don't actually need these bulletins? don't want them to get destroyed if you close the initial bulletin, progressing/destroying an encounter
         --table.insert(bulletins, bulletin)
      end
   end

   return bulletins
end

function job_lib.show_recipe_unlock_bulletin(player_id, job_alias, job_name, recipe_data)
   local num_recipes = #recipe_data
   local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
         :set_sticky(true)
         :set_data({
            title = num_recipes > 1 and 'stonehearth_ace:data.commands.use_recipe.bulletin_title' or 'stonehearth_ace:data.commands.use_recipe.bulletin_title_single',
            unlocked_recipes = recipe_data,
         })
         :set_ui_view('StonehearthRecipeUnlockBulletinDialog')
         :add_i18n_data('job_alias', job_alias)
         :add_i18n_data('job_name', job_name)
         :add_i18n_data('recipe_count', num_recipes)
   return bulletin
end

return job_lib