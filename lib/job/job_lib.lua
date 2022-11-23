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

function job_lib.apply_recipe_list(player_id, list_alias, bulletin_titles, optional_list_source)
   if bulletin_titles then
      for _, bulletin_title in ipairs(bulletin_titles) do
         --create a bulletin announcing the new recipes
         stonehearth.bulletin_board:post_bulletin(player_id)
               :set_sticky(true)
               :set_data({title = bulletin_title})
      end
   end
   optional_list_source = optional_list_source or 'stonehearth_ace:data:recipe_lists'
   -- local biome = stonehearth.world_generation:get_biome_alias()
   local recipe_lists_json = radiant.resources.load_json(optional_list_source)
   if recipe_lists_json and recipe_lists_json[list_alias] then
      if recipe_lists_json[list_alias].crafting then
         for job_alias, job_entry in pairs(recipe_lists_json[list_alias].crafting) do
            local job_info = stonehearth.job:get_job_info(player_id, job_alias)
            if job_info then
               if job_entry.categories then
                  for category_key, value in pairs(job_entry.categories) do
                     if value == false then
                        job_info:manually_lock_recipe_category(category_key, true)
                     end
                  end
               end
               if job_entry.recipes then
                  for recipe_key, value in pairs(job_entry.recipes) do
                     if value == false then
                        job_info:manually_lock_recipe(recipe_key, true)
                     elseif value == true then
                        job_info:manually_unlock_recipe(recipe_key, true)
                     end
                  end
               end
            end
         end
      end
      if recipe_lists_json[list_alias].farming then
         for job_alias, job_entry in pairs(recipe_lists_json[list_alias].farming) do
            -- only farmers maintain a crop list, though it's used by other jobs (they all reference the farmer job info controller though)
            if job_alias == 'stonehearth:jobs:farmer' then
               local job_info = stonehearth.job:get_job_info(player_id, job_alias)
               if job_info then
                  if job_entry.crops then
                     for crop_key, value in pairs(job_entry.crops) do
                        if value == true then
                           job_info:manually_unlock_crop(crop_key, true)
                        end
                     end
                  end
               end
            end
         end
      end
   end
end

return job_lib