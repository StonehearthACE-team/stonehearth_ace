local BiomeUnlocks = class()

function BiomeUnlocks:start(ctx, data)
	local biome = stonehearth.world_generation:get_biome_alias()
	local herbalist = stonehearth.job:get_job_info(ctx.player_id, 'stonehearth:jobs:herbalist')
	
	if not herbalist then 
		herbalist = stonehearth.job:get_job_info(ctx.player_id, 'stonehearth_ace:mountain_folk:jobs:grower')
	end
		
	if herbalist and biome == 'stonehearth:biome:temperate' then
		herbalist:manually_unlock_recipe('refinement_seeds:oak_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:juniper_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:pine_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:brightbell_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:silkweed_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:frostsnap_seeds_recipe')
	elseif herbalist and biome == 'stonehearth:biome:desert' then
		herbalist:manually_unlock_recipe('refinement_seeds:cactus_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:acacia_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:cactus_flower_seeds_recipe')
	elseif herbalist and biome == 'stonehearth:biome:arctic' then
		herbalist:manually_unlock_recipe('refinement_seeds:arctic_pine_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:arctic_juniper_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:violet_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:snow_poppy_seeds_recipe')
	elseif herbalist and biome == 'stonehearth_ace:biome:highlands' then
		herbalist:manually_unlock_recipe('refinement_seeds:birch_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:yew_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:highland_pine_tree_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:moonbell_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:cotton_seeds_recipe')
		herbalist:manually_unlock_recipe('refinement_seeds:marblesprout_seeds_recipe')
	end
end

return BiomeUnlocks