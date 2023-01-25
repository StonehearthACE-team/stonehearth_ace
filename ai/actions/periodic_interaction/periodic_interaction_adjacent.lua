local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local InteractWithItemAdjacent = radiant.class()

local log = radiant.log.create_logger('periodic_interaction_adjacent')

InteractWithItemAdjacent.name = 'periodic interaction adjacent'
InteractWithItemAdjacent.does = 'stonehearth_ace:periodic_interaction_adjacent'
InteractWithItemAdjacent.args = {
   item = Entity,      -- the entity to interact with
}
InteractWithItemAdjacent.priority = 0

function InteractWithItemAdjacent:start(ai, entity, args)
   local pi_comp = args.item:get_component('stonehearth_ace:periodic_interaction')
   ai:set_status_text_key(pi_comp:get_current_mode_ai_status())

   self._completed_work = false

   self._destroy_listener = radiant.events.listen_once(args.item, 'radiant:entity:pre_destroy', function()
      if not self._completed_work then
         ai:abort()
      end
   end)
end

function InteractWithItemAdjacent:stop(ai, entity, args)
   local pi_comp = args.item and args.item:is_valid() and args.item:get_component('stonehearth_ace:periodic_interaction')
   if pi_comp then
      pi_comp:set_interaction_effect()
   end

   if self._destroy_listener then
      self._destroy_listener:destroy()
      self._destroy_listener = nil
   end
end

function InteractWithItemAdjacent:run(ai, entity, args)
   local item = args.item
   local pi_comp = args.item:get_component('stonehearth_ace:periodic_interaction')
   if not pi_comp or not pi_comp:is_usable() then
      ai:abort('not interactable!')
      return
   end

   local data = pi_comp:get_current_interaction()

   if data then
      local effect = data.interaction_effect
      local times = data.num_interactions
      local points = data.interaction_points
      local interaction_points = {}
      
      local interactions = {}
      local selector = WeightedSet(rng)
      local total_interactions = 0
      for point, point_data in pairs(points) do
         selector:add(point, point_data.weight or 1)
         total_interactions = total_interactions + 1
      end

      for i = 1, times do
         if total_interactions > 1 then
            local prev = interactions[i - 1]
            local cur
            repeat
               cur = selector:choose_random()
            until prev ~= cur
            table.insert(interactions, cur)
         else
            table.insert(interactions, 1)
         end
      end

      if effect then
         pi_comp:set_interaction_effect(effect)
      end

      local location = radiant.entities.get_world_grid_location(item)

      for _, interaction in ipairs(interactions) do
         local interaction_data = interaction_points[interaction]
         if not interaction_data then
            interaction_data = radiant.shallow_copy(pi_comp:get_interaction_point(interaction) or {})
            radiant.util.merge_into_table(interaction_data, points[interaction])
            interaction_points[interaction] = interaction_data
         end
         ai:set_status_text_key(interaction_data.ai_status_key or data.ai_status_key or pi_comp:get_current_mode_ai_status())
         local pt = interaction_data.point and (radiant.util.to_point3(interaction_data.point) or Point3(unpack(interaction_data.point))) or Point3.zero
         local face_pt = interaction_data.face_point and (radiant.util.to_point3(interaction_data.face_point) or Point3(unpack(interaction_data.face_point)))
         ai:execute('stonehearth:go_toward_location', { destination = location + pt })
         if face_pt then
            radiant.entities.turn_to_face(entity, location + face_pt)
         end
         local worker_effect = interaction_data.worker_effect or data.worker_effect
         if type(worker_effect) == 'table' then
            worker_effect = worker_effect[rng:get_int(1, #worker_effect)]
         end
         ai:execute('stonehearth:run_effect', { effect = worker_effect or 'fiddle' })
      end
      
      self._completed_work = true
      pi_comp:set_current_interaction_completed(entity)
   end
end

return InteractWithItemAdjacent
