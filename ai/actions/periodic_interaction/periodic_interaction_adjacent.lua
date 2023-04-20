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
   ai:set_status_text_key(pi_comp:get_current_mode_ai_status(), {target = args.item})

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

   -- if there was an ingredient that didn't get destroyed (e.g., we aborted), return it to the world
   if self._ingredient and self._ingredient:is_valid() and entity and entity:is_valid() then
      if radiant.entities.get_carrying(entity) == self._ingredient then
         radiant.entities.drop_carrying_nearby(entity)
      else
         local location = radiant.entities.get_world_grid_location(entity)
         if location then
            radiant.terrain.place_entity(self._ingredient, location)
         end
      end
   end

   if self._destroy_listener then
      self._destroy_listener:destroy()
      self._destroy_listener = nil
   end
end

function InteractWithItemAdjacent:run(ai, entity, args)
   local ingredient = radiant.entities.get_carrying(entity)
   local item = args.item
   local pi_comp = args.item:get_component('stonehearth_ace:periodic_interaction')
   if not pi_comp or not pi_comp:is_usable() or not pi_comp:is_valid_potential_user(entity) then
      if ingredient then
         -- don't be stuck carrying this (though really other actions should handle that?)
         ai:execute('stonehearth:drop_carrying_now', {})
      end

      ai:abort('not interactable!')
      return
   end

   local data = pi_comp:get_current_interaction()

   if data then
      local ingredient_quality

      if data.ingredient_uri or data.ingredient_material then
         local ingredient_uri = ingredient and ingredient:is_valid() and ingredient:get_uri()
         if ingredient_uri and ((data.ingredient_uri and data.ingredient_uri == ingredient_uri) or
            (data.ingredient_material and stonehearth.catalog:is_material(ingredient_uri, data.ingredient_material))) then
            -- carried item is the required ingredient
            ingredient_quality = radiant.entities.get_item_quality(ingredient)
         else
            if ingredient then
               -- don't be stuck carrying this (though really other actions should handle that?)
               ai:execute('stonehearth:drop_carrying_now', {})
            end

            ai:abort('missing ingredient')
            return
         end
      end

      self._ingredient = ingredient

      local effect = data.interaction_effect
      local times = data.num_interactions
      local points = data.interaction_points or {}
      local destroy_ingredient_after_num = data.destroy_ingredient_after_num or times
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

      for i, interaction in ipairs(interactions) do
         local interaction_data = interaction_points[interaction]
         if not interaction_data then
            interaction_data = radiant.shallow_copy(pi_comp:get_interaction_point(interaction) or {})
            radiant.util.merge_into_table(interaction_data, points[interaction] or {})
            interaction_points[interaction] = interaction_data
         end
         ai:set_status_text_key(interaction_data.ai_status_key or data.ai_status_key or pi_comp:get_current_mode_ai_status(), {target = args.item})
         local pt = interaction_data.point and (radiant.util.to_point3(interaction_data.point) or Point3(unpack(interaction_data.point)))
         if pt then
            ai:execute('stonehearth:go_toward_location', { destination = location + pt })
         end
         local face_pt = interaction_data.face_point and (radiant.util.to_point3(interaction_data.face_point) or Point3(unpack(interaction_data.face_point)))
         if face_pt then
            radiant.entities.turn_to_face(entity, location + face_pt)
         else
            -- otherwise, make sure we're facing the interaction entity
            radiant.entities.turn_to_face(entity, item)
         end

         if ingredient and data.drop_ingredient then
            ai:execute('stonehearth:drop_carrying_now', {})
            self:_remove_ingredient_from_world()
            ingredient = nil
         end

         local worker_effect = interaction_data.worker_effect or data.worker_effect
         if type(worker_effect) == 'table' then
            worker_effect = worker_effect[rng:get_int(1, #worker_effect)]
         end
         ai:execute('stonehearth:run_effect', { effect = worker_effect or 'fiddle' })

         if ingredient and i >= destroy_ingredient_after_num then
            self:_remove_ingredient_from_world()
            ingredient = nil
         end
      end

      -- if the ingredient still exists, destroy it now
      if self._ingredient and self._ingredient:is_valid() then
         radiant.entities.destroy_entity(self._ingredient)
      end

      self._completed_work = true
      if ingredient_quality then
         pi_comp:set_ingredient_quality(ingredient_quality)
      end
      pi_comp:set_current_interaction_completed(entity)
   end
end

function InteractWithItemAdjacent:_remove_ingredient_from_world()
   if self._ingredient and self._ingredient:is_valid() then
      local parent = radiant.entities.get_parent(self._ingredient)
      if parent then
         if radiant.entities.is_carried(self._ingredient) then
            radiant.entities.remove_carrying(parent)
         else
            radiant.entities.remove_child(parent, self._ingredient)
         end
      end
   end
end

return InteractWithItemAdjacent
