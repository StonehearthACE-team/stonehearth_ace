-- Based on the Beast Tamer controller from BrunoSupremo's 'Swamp Biome + Firefly Goblins + Beast Tamer' mod, with permission!
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local RootsScript = class()

function RootsScript:start(entity, location, info)
   if entity and entity:is_valid() then
      if not location then 
         return 
      end

      local all_targets = self:get_closeby_targets(entity, location, info)

      for i, current_target in ipairs(all_targets) do
         radiant.entities.add_buff(current_target, info.root_buff)

         if info.max_health_based_duration then
            local hp_timer = radiant.entities.get_attribute(current_target, "max_health")
            hp_timer = math.ceil( math.max(50 - math.sqrt(hp_timer)/2, 5) ) .. "m+5m"
            -- some example ranges:
            -- 100hp = 45m, 200hp = 42m, 500hp = 38m
            -- 1000hp = 34m, 2000hp = 27m, 5000hp = 15m
            stonehearth.calendar:set_timer("roots on target "..i, hp_timer, function()
               radiant.entities.remove_buff(current_target, info.root_buff)
            end)
         else
            local duration = info.duration or '30m'
            stonehearth.calendar:set_timer("roots on target "..i, duration, function()
               radiant.entities.remove_buff(current_target, info.root_buff)
            end)
         end
	   end
   end
end

function RootsScript:get_closeby_targets(entity, location, info)
	local cube = Cube3(location):inflated(Point3(11, 6, 11))
	local all_entities = radiant.terrain.get_entities_in_cube(cube)
	local all_targets = {}
	local not_menacing = {}
	local limit = info.num_targets or 1

	for _, target in pairs(all_entities) do
		local is_hostile = stonehearth.player:are_entities_hostile(target, entity)
		if is_hostile and radiant.entities.has_free_will(target) then
			if radiant.entities.get_attribute(target, "menace")>1 then
				table.insert(all_targets, target)
				limit = limit -1
				if limit <1 then
					break
				end
			else
				table.insert(not_menacing, target)
			end
		end
	end
	if #all_targets < 1 then
		return not_menacing
	end

	return all_targets
end

return RootsScript