local job_lib = {}

function job_lib.unlock_recipes(player_id, recipes_by_job_alias, bulletin_titles)
   if bulletin_titles then
      for _, bulletin_title in ipairs(bulletin_titles) do
         --create a bulletin announcing the new recipes
         stonehearth.bulletin_board:post_bulletin(player_id)
               :set_sticky(true)
               :set_data({title = bulletin_title})
      end
   end
   for job_alias, recipes in pairs(recipes_by_job_alias) do
      local job_info = stonehearth.job:get_job_info(player_id, job_alias)
      for _, recipe in ipairs(recipes) do
         job_info:manually_unlock_recipe(recipe)
      end
   end
end

return job_lib