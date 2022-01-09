local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local unlock_seed_rewards = {}

local log = radiant.log.create_logger('unlock_seed_rewards_script')

-- returns true if the interaction should now be considered complete
function unlock_seed_rewards.process_reward(entity, user, stage, script_data, is_completed)
   log:debug('processing reward: %s, %s, %s, %s, %s', tostring(entity), tostring(user), tostring(stage), radiant.util.table_tostring(script_data), tostring(is_completed))

   if not entity or not entity:is_valid() or not user or not user:is_valid() then
      return false
   end
   
   local player_id = user:get_player_id()
   local kingdom = stonehearth.population:get_population(player_id)
                                          :get_kingdom()
   local farmer_job_info = stonehearth.job:get_job_info(player_id, 'stonehearth:jobs:farmer')
   local all_herbalist_crops = farmer_job_info:get_all_herbalist_crops()
   local unlocked_crops = farmer_job_info:get_manually_unlocked()
   local initial_crops = radiant.resources.load_json('stonehearth:farmer:initial_crops').crops_by_kingdom[kingdom]

   -- based on script_data settings and user job level, create a list of eligible native/exotic crops
   -- roll X to unlock, then unlock them
   local job_comp = user:get_component('stonehearth:job')
   local level = job_comp:get_current_job_level()

   -- determine which crops are native to this biome; all others are exotic; ignore all hidden ones
   local biome = stonehearth.world_generation:get_biome_alias()
   local biome_data = radiant.resources.load_json(biome)
   local all_native_crops = biome_data.native_crops or {}
   local native_crops = {}
   local exotic_crops = {}
   local native_chance = 0
   local exotic_chance = 0
   local total_possible = 0

   for crop, crop_data in pairs(all_herbalist_crops) do
      if crop_data.category == script_data.crop_category and not unlocked_crops[crop] and not initial_crops[crop] then
         if not crop_data.hidden then
            total_possible = total_possible + 1
            local crop_level = crop_data.level or 1
            if level + 1 >= crop_level then
               local diff = (level + 1 - crop_level)
               local chance = diff * diff / 2 + 1
               if all_native_crops[crop] then
                  native_chance = native_chance + chance
                  table.insert(native_crops, {crop = crop, chance = chance})
               else
                  exotic_chance = exotic_chance + chance
                  table.insert(exotic_crops, {crop = crop, chance = chance})
               end
            end
         end
      end
   end

   -- determine a weight multiplier for native and exotic crops to match the script data
   local script_none = script_data.none or 0
   local script_native = script_data.native or 0
   local script_exotic = script_data.exotic or 0
   local script_total = script_none + script_native + script_exotic
   local native_mult = native_chance > 0 and script_native / (script_total * native_chance) or 0
   local exotic_mult = exotic_chance > 0 and script_exotic / (script_total * exotic_chance) or 0

   if script_data.convert_to_none then
      if script_data.convert_to_none.native and native_chance == 0 then
         script_none = script_none + script_native
      end

      if script_data.convert_to_none.exotic and exotic_chance == 0 then
         script_none = script_none + script_exotic
      end
   end

   local crops = WeightedSet(rng)
   if script_none > 0 then
      crops:add('none', script_none / script_total)
   end
   if native_mult > 0 then
      for _, native_crop in ipairs(native_crops) do
         crops:add(native_crop.crop, native_crop.chance * native_mult)
      end
   end
   if exotic_mult > 0 then
      for _, exotic_crop in ipairs(exotic_crops) do
         crops:add(exotic_crop.crop, exotic_crop.chance * exotic_mult)
      end
   end

   local crop = crops:choose_random()

   if crop ~= 'none' then
      -- got something to unlock so unlock it
      farmer_job_info:manually_unlock_crop(crop, true)

      local crop_info = all_herbalist_crops[crop]
      if crop_info then
         local bulletin_title = 'stonehearth_ace:jobs.herbalist.unlock_last_crop.bulletin_title'
         if total_possible > 1 then
            bulletin_title = 'stonehearth_ace:jobs.herbalist.unlock_crop.bulletin_title'
         end
         stonehearth.bulletin_board:post_bulletin(player_id)
                  :set_sticky(true)
                  :set_data({title = bulletin_title})
                  :add_i18n_data('job_name', job_comp:get_curr_job_name())
                  :add_i18n_data('crop_name', crop_info.display_name)
                  :add_i18n_data('icon', crop_info.icon)
      end

      -- return true because we want to complete the interaction, since we unlocked a crop
      return true
   end

   return false
end

return unlock_seed_rewards
