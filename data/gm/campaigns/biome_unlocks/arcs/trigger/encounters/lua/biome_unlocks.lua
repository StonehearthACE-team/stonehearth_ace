local BiomeUnlocks = class()

function BiomeUnlocks:start(ctx, data)
	local biome = stonehearth.world_generation:get_biome_alias()
	local biome_recipes_json = radiant.resources.load_json('stonehearth_ace:data:biome_recipes')
	for job_alias, biome_recipes in pairs(biome_recipes_json) do

		local job_info = stonehearth.job:get_job_info(ctx.player_id, job_alias)

		if job_info then
			if biome_recipes.always then
				if biome_recipes.always.disabled then
					for recipe_key, value in pairs(biome_recipes.always.disabled.recipes) do
						if value then
							job_info:manually_lock_recipe(recipe_key)
						end
					end
					for category_key, value in pairs(biome_recipes.always.disabled.categories) do
						if value then
							job_info:manually_lock_recipe_category(category_key)
						end
					end
				end
				if biome_recipes.always.enabled then
					for recipe_key, value in pairs(biome_recipes.always.enabled.recipes) do
						if value then
							job_info:manually_unlock_recipe(recipe_key)
						end
					end
				end
			end

			local biome_recipes_data = biome_recipes[biome]

			if biome_recipes_data then
				if biome_recipes_data.disabled then
					for recipe_key, value in pairs(biome_recipes_data.disabled.recipes) do
						if value then
							job_info:manually_lock_recipe(recipe_key)
						end
					end
					for category_key, value in pairs(biome_recipes_data.disabled.categories) do
						if value then
							job_info:manually_lock_recipe_category(category_key)
						end
					end
				end
				if biome_recipes_data.enabled then
					for recipe_key, value in pairs(biome_recipes_data.enabled.recipes) do
						if value then
							job_info:manually_unlock_recipe(recipe_key)
						end
					end
				end
			end
		end
	end
end

return BiomeUnlocks