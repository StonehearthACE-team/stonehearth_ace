local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local AceDigAdjacent = class()
local log = radiant.log.create_logger('mining')

function AceDigAdjacent:_mine_block(ai, entity, mining_zone, block)
   if not mining_zone:is_valid() then
      return false
   end

   local worker_location = radiant.entities.get_world_grid_location(entity)

   radiant.entities.turn_to_face(entity, block)
   ai:execute('stonehearth:run_effect', { effect = 'mine' })

   -- check after yielding
   if not mining_zone:is_valid() then
      return false
   end

   -- The reserved region may include support blocks. We must release it before looking
   -- for the next block to mine so that they will be included as candidates.
   -- Also release it on any failure conditions.
   self:_release_blocks(mining_zone)

   -- any time we yield, check to make sure we're still in the same location
   if radiant.entities.get_world_grid_location(entity) ~= worker_location then
      return false
   end

   local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
   local loot = mining_zone_component:mine_point(block)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local items = radiant.entities.spawn_items(loot, worker_location, 1, 3, { owner = work_player_id })

   -- apply quality to mined items if relevant
   self:_apply_quality(entity, mining_zone, items)

   local inventory = stonehearth.inventory:get_inventory(work_player_id)
   if inventory then
      for _, item in pairs(items) do
         inventory:add_item_if_not_full(item)
      end
   end
   -- for the autotest
   radiant.events.trigger(entity, 'stonehearth:mined_location', { location = block })

   return true
end

-- not using mining_zone, but maybe someone wants to override this function to take that into account
-- e.g., higher/lower chances based on altitude
function AceDigAdjacent:_apply_quality(entity, mining_zone, items)
   local quality_chances = self:_get_quality_chances(entity, mining_zone)
   if quality_chances then
      item_quality_lib.apply_random_qualities(items, quality_chances, true)
   end
end

function AceDigAdjacent:_get_quality_chances(entity, mining_zone)
   local buffs_component = entity:get_component('stonehearth:buffs')
   local mining_quality_buffs = buffs_component and buffs_component:get_buffs_by_category('stonehearth_ace:buffs:mining_quality')
   if mining_quality_buffs then
      local qualities = {}
      local quality_chances = {}
      for _, buff in pairs(mining_quality_buffs) do
         local quality_tbl = buff:get_json().mining_quality
         for _, quality_chance in ipairs(quality_tbl) do
            local this_quality = qualities[quality_chance[1]]
            if not this_quality then
               this_quality = {quality_chance[1], quality_chance[2]}
               qualities[quality_chance[1]] = this_quality
               table.insert(quality_chances, this_quality)
            else
               this_quality[2] = this_quality[2] + quality_chance[2]
            end
         end
      end

      table.sort(quality_chances, function(a, b) return a.quality > b.quality end)

      return quality_chances
   end
end

return AceDigAdjacent
