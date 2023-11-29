local AceBuildLadderAdjacent = class()

function AceBuildLadderAdjacent:run(ai, entity, args)
   local ladder_builder_entity = args.ladder_builder_entity

   local builder = ladder_builder_entity:get_component('stonehearth:ladder_dst_proxy')
                                          :get_ladder_builder()

   if builder:is_ladder_finished('build') then
      -- if the ladder's already finished, there's nothing to do
      ai:abort('ladder is already finished.')
      return
   end

   local ladder = builder:get_ladder()

   local ladder_component = ladder:add_component('stonehearth:ladder')
   local location = radiant.entities.get_world_grid_location(entity)
   local direction

   local top = ladder_component:get_top()
   -- we ran to it, we're adjacent to it
   -- if we're next to the top, build down, otherwise build up
   if location:is_adjacent_to(top) or location == top then
      direction = 'down'
   else
      direction = 'up'
   end

   radiant.entities.turn_to_face(entity, ladder)

   local job_component = entity:get_component('stonehearth:job')
   local has_build_faster_perk = false
   if job_component then
      has_build_faster_perk = job_component:curr_job_has_perk('increased_construction_rate')
   end
   local num_times_fabricated = 0

   while not builder:is_ladder_finished('build') do
      if num_times_fabricated == 0 or not has_build_faster_perk then
         ai:execute('stonehearth:run_effect', { effect = 'work' })
      end
      builder:grow_ladder(direction, 2)
      num_times_fabricated = num_times_fabricated + 1
   end
end

return AceBuildLadderAdjacent
