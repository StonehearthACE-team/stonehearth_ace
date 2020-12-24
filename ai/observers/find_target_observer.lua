--[[
   ACE: have to override the whole thing because Radiant used "mixin" inheritance instead of real inheritance for the siege_find_target_observer
]]

local log = radiant.log.create_logger('combat')
local constants = require 'stonehearth.constants'
local Point3 = _radiant.csg.Point3

local FindTargetObserver = class()

local NOT_WITHIN_LEASH_PENALTY_MULTIPLIER = constants.combat.NOT_WITHIN_LEASH_PENALTY_MULTIPLIER
local FOCUS_FIRE_MAX_MULTIPLIER = constants.combat.FOCUS_FIRE_MAX_MULTIPLIER
local MIN_MENACE_FOR_COMBAT = constants.combat.MIN_MENACE_FOR_COMBAT
local MIN_DISTANCE_TO_RECALCULATE = 5

function FindTargetObserver:initialize()
   self._sv._entity = nil
   self._enable_combat = radiant.util.get_config('enable_combat', true)
end

function FindTargetObserver:create(entity)
   self._sv._entity = entity
   self._running = true
end

function FindTargetObserver:restore()
   self._running = false
   self._game_loaded_trace = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
         self._running = true
         self:_check_for_target()
         self._game_loaded_trace = nil
      end)
end

-- Ok to reference other datastores in activate, but do not call methods on them
function FindTargetObserver:activate()
   -- copy _entity out of _sv, since referencing _sv is expensive and _entity never changes
   self._entity = self._sv._entity
   assert(self._entity)

   self._sight_sensor = radiant.entities.get_sight_sensor(self._entity)

   self._sight_sensor_trace = self._sight_sensor:trace_contents('find target obs')
                                                   :on_added(function (id, target)
                                                         self:_on_sensor_contents_changed(id, target)
                                                      end)
                                                   :on_removed(function (id)
                                                         self:_on_sensor_contents_changed(id)
                                                         -- destroyed targets are handled in another code path
                                                      end)

   self._scored_targets = {}
   self._highest_scored_target = nil
   self._highest_score = -1
   self._current_target = nil
   self._last_attacker = nil
   self._last_attacked_time = 0
   self._retaliation_window = 5000
   self._task = nil
   self._is_npc = stonehearth.player:is_npc(self._entity)

   self._log = radiant.log.create_logger('combat')
                           :set_prefix('find_target_obs')
                           :set_entity(self._entity)

   -- Subscribe to events in activate so that we catch events from other post_activates that occur before our post_activate
   -- Do not push_object_changes until post_activate though
   self:_subscribe_to_events()
end

-- Must wait until post-activate to call methods on other datastores
function FindTargetObserver:post_activate()
   self:_check_for_target()
end

function FindTargetObserver:destroy()
   self:_unsubscribe_from_events()
end

function FindTargetObserver:_subscribe_to_events()
   self._aggro_table = self._entity:add_component('stonehearth:target_tables')
                                       :get_target_table('aggro')
   self._combat_state = self._entity:add_component('stonehearth:combat_state')
   self._target_table_trace = radiant.events.listen(self._aggro_table, 'stonehearth:target_table_changed', self, self._on_target_table_changed)
   self._stance_changed_trace = radiant.events.listen(self._entity, 'stonehearth:combat:stance_changed', self, self._on_stance_changed)
   self._assault_trace = radiant.events.listen(self._entity, 'stonehearth:combat:assault', self, self._on_assault)
   self._leash_contents_listener = radiant.events.listen(self._entity, 'stonehearth:combat:leash_contents_changed', self, self._on_leash_contents_changed)
   self._nonthreatening_changed = radiant.events.listen(stonehearth, 'stonehearth:combat:nonthreatening_changed', self, self._on_entity_nonthreatening_status_changed)
   self._player_id_listener = radiant.events.listen(self._entity, 'radiant:entity:player_id_changed', self, function()
         self._is_npc = stonehearth.player:is_npc(self._entity)
      end)
   
   -- ACE:
   self._avoid_hunting_listener = radiant.events.listen(self._entity, 'stonehearth_ace:avoid_hunting_changed', self, self._reconsider_all_targets)

   self:_trace_entity_location()
end

function FindTargetObserver:_unsubscribe_from_events()
   -- ACE:
   if self._avoid_hunting_listener then
      self._avoid_hunting_listener:destroy()
      self._avoid_hunting_listener = nil
   end

   if self._sight_sensor_trace then
      self._sight_sensor_trace:destroy()
      self._sight_sensor_trace = nil
   end

   if self._stance_changed_trace then
      self._stance_changed_trace:destroy()
      self._stance_changed_trace = nil
   end

   if self._assault_trace then
      self._assault_trace:destroy()
      self._assault_trace = nil
   end

   -- This unlisten may log 'unlisten stonehearth:target_table_changed on unknown sender'
   -- when the target table component is destroyed before this observer, thus forcing an unpublish
   -- before we can unlisten. This is ok.
   if self._target_table_trace then
      self._target_table_trace:destroy()
      self._target_table_trace = nil
   end

   if self._leash_contents_listener then
      self._leash_contents_listener:destroy()
      self._leash_contents_listener = nil
   end

   self:_destroy_entity_location_trace()
   self:_destroy_task()

   if self._game_loaded_trace then
      self._game_loaded_trace:destroy()
      self._game_loaded_trace = nil
   end

   if self._nonthreatening_changed then
      self._nonthreatening_changed:destroy()
      self._nonthreatening_changed = nil
   end

   if self._player_id_listener then
      self._player_id_listener:destroy()
      self._player_id_listener = nil
   end
end

function FindTargetObserver:_destroy_task()
   if self._task then
      self._task:destroy()
      self._task = nil
   end
end

function FindTargetObserver:_reconsider_all_targets()
   self:_update_all_target_scores()
   self:_check_for_target()
end

function FindTargetObserver:_update_all_target_scores()
   local location = radiant.entities.get_world_location(self._entity)
   self._scored_targets = {}

   local targets = self._aggro_table:get_entries()
   for id, entry in pairs(targets) do
      local target, aggro = entry.entity, entry.value
      local score = aggro and self:_calculate_target_cost_benefit(location, target, aggro) or 0

      self._scored_targets[id] = {
         target = target,
         score = score
      }
   end

   self:_update_highest_scored_target()
end

function FindTargetObserver:_update_target_score(id, target)
   local location = radiant.entities.get_world_location(self._entity)
   local aggro = self._aggro_table:get_value(target)
   if not aggro then
      -- target doesn't exist in aggro table
      return
   end
   local score = self:_calculate_target_cost_benefit(location, target, aggro)
   radiant.assert(score >= 0, "target %s's score is less than zero: %d")

   self._scored_targets[id] = {
      target = target,
      score = score
   }

   if target == self._highest_scored_target and score < self._highest_score then
      -- target may no longer be the highest scored target
      self:_update_highest_scored_target()
   elseif score > self._highest_score then
      -- target has become the highest scored target
      self._highest_score = score
      self._highest_scored_target = target
   end
end

function FindTargetObserver:_remove_target(id, target)
   self._scored_targets[id] = nil

   if (target and target:is_valid() and target == self._highest_scored_target) or
      (self._highest_scored_target and not self._highest_scored_target:is_valid()) then

      self:_update_highest_scored_target()
   end
end

-- ACE: also take into consideration the whether the entity is set to avoid hunting
function FindTargetObserver:_update_highest_scored_target()
   local highest_scored_target = nil
   local is_hunting = false
   local job = self._entity:get_component('stonehearth:job')
   if job and job:has_role('hunter') then
      local properties_comp = self._entity:get_component('stonehearth:properties')
      is_hunting = not (properties_comp and properties_comp:has_property('avoid_hunting'))
   end
   local highest_score = is_hunting and 0 or stonehearth.constants.combat.MIN_MENACE_FOR_COMBAT

   for id, entry in pairs(self._scored_targets) do
      local target, score = entry.target, entry.score
      if score > highest_score and target:is_valid() then
         highest_score = score
         highest_scored_target = target
      end
   end

   self._highest_scored_target = highest_scored_target
   self._highest_score = highest_score
end

function FindTargetObserver:_on_sensor_contents_changed(id, target)
   if not target then
      target = radiant.entities.get_entity(id)
   end
   if self._aggro_table:contains(target) then
      -- update score for target that just entered/left range
      self:_update_target_score(id, target)
      self:_check_for_target()
   end
end

-- should we aggregate these changes and checks into a check once per gameloop?
function FindTargetObserver:_on_target_table_changed(args)
   local operation = args[1]
   local id = args[2]
   local target = args[3]

   -- for this purpose, a nil target is not an invalid target
   local invalid_target = target and not target:is_valid()

   if operation == 'remove' or invalid_target then
      self:_remove_target(id, target)

   elseif operation == 'modify' then
      self:_update_target_score(id, target)

   elseif operation == 'clear' then
      self._scored_targets = {}
      self:_update_all_target_scores()
   end

   self:_check_for_target()
end

function FindTargetObserver:_on_stance_changed()
   self:_check_for_target()
end

function FindTargetObserver:_on_leash_contents_changed(args)
   self:_on_sensor_contents_changed(args.id, args.target)
end

function FindTargetObserver:_on_entity_nonthreatening_status_changed(args)
   local entity = args.entity
   if entity and entity:is_valid() then
      if self._aggro_table:contains(entity) then
         -- update score for target that just entered/left range
         self:_update_target_score(entity:get_id(), entity)
         self:_check_for_target()
      end
   end
end

function FindTargetObserver:_on_assault(context)
   self._last_attacker = context.attacker
   self._last_attacked_time = radiant.gamestate.now()

   local stance = stonehearth.combat:get_stance(self._entity)
   if stance == 'defensive' then
      self:_check_for_target()
   end
end

function FindTargetObserver:_on_grid_location_changed()
   local current_location = radiant.entities.get_world_location(self._entity)

   -- make sure we're not being moved off the map for suspension
   if not self._current_target or not current_location or radiant.entities.is_entity_suspended(self._entity) then
      -- do nothing, let another event initiate a target
      return
   end
   
   if self._last_entity_location and self._last_entity_location:distance_to_squared(current_location) < MIN_DISTANCE_TO_RECALCULATE then
      -- Haven't moved far enough, so skip the super expensive target recalculation.
      return
   end
   self._last_entity_location = current_location
          
   -- check if there is a better target
   self:_update_all_target_scores()
   self:_check_for_target()
end

function FindTargetObserver:_trace_entity_location()
   self._entity_location_trace = radiant.entities.trace_grid_location(self._entity, 'find target observer')
      :on_changed(function()
            self:_on_grid_location_changed()
         end)
end

function FindTargetObserver:_destroy_entity_location_trace()
   if self._entity_location_trace then
      self._entity_location_trace:destroy()
      self._entity_location_trace = nil
   end
end

function FindTargetObserver:_check_for_target()
   if not self._entity:is_valid() then
      return
   end

   if not self._running then
      return
   end

   if self:_do_not_disturb() then
      self._log:spam('do not disturb is set. skipping target check...')
      -- don't interrupt an assault in progress
      return
   end

   -- ok for new_target to be nil
   local new_target, new_score = self:_find_target()

   -- check if it's worth switching targets
   -- if new_target has a nil score, skip this check since that target is mandatory
   if new_score and new_target and
      self._current_target and self._current_target:is_valid() and
      new_target ~= self._current_target then

      local current_target_id = self._current_target:get_id()
      local entry = self._scored_targets[current_target_id]

      if entry then
         local current_score = entry.score

         local threshold = stonehearth.constants.combat.CHANGE_TARGET_THRESHOLD_PLAYER
         if self._is_npc then
            threshold = stonehearth.constants.combat.CHANGE_TARGET_THRESHOLD_NPC
         end

         if new_score < current_score * threshold then
            -- below switching threshold. primarily prevents oscillation before engaging.
            new_target = self._current_target
            new_score = nil
         end
      end

      self._log:info('switching targets from %s to %s', tostring(self._current_target), tostring(new_target))
   end

   self:_attack_target(new_target)
end

function FindTargetObserver:_do_not_disturb()
   local assaulting = stonehearth.combat:get_assaulting(self._entity)
   return assaulting
end

-- target allowed to be nil
function FindTargetObserver:_attack_target(target)
   -- make sure we set it here unconditionally even if target == self._current_target
   -- because it might be cleared by someone else
   stonehearth.combat:set_primary_target(self._entity, target)

   if target == self._current_target and self._task then
      -- we're already attacking that target, nothing to do
      assert(target == self._task:get_args().target)
      return
   end

   self._log:info('setting target to %s', tostring(target))

   if target ~= self._current_target then
      self:_destroy_task()
      self._current_target = target
   end

   if target and target:is_valid() then
      assert(not self._task)
      self._task = self._entity:add_component('stonehearth:ai')
                         :get_task_group('stonehearth:task_groups:solo:combat_unit_control')
                            :create_task('stonehearth:combat:attack_after_cooldown', { target = target })
                               :once()
                               :notify_completed(
                                 function ()
                                    self._task = nil
                                    self:_check_for_target()
                                 end
                               )
                               :start()
   end
end

function FindTargetObserver:_find_target()
   if not self._enable_combat then
      return nil, nil
   end

   local stance = stonehearth.combat:get_stance(self._entity)
   local target, score

   if stance == 'passive' then
      -- don't attack
      self._log:info('stance is passive.  returning nil target.')
      return nil, nil
   end

   if stance == 'defensive' then
      -- only attack those who attack you
      target = self:_get_retaliation_target()
   else
      assert(stance == 'aggressive')
      -- get the highest scored target
      target = self._highest_scored_target
      score = self._highest_score
   end

   self._log:info('stance is %s.  returning %s as target.', stance, tostring(target))

   -- Can we get rid of this? We needed it because the aggro observer updates the aggro table
   -- asynchronously and may not have removed a newly friendly entity yet.
   if target ~= nil and target:is_valid() then
      if stonehearth.player:are_entities_hostile(target, self._entity) then
         return target, score
      end
   end

   return nil, nil
end

function FindTargetObserver:_calculate_target_cost_benefit(entity_location, target, aggro)
   if not (target and entity_location and target:is_valid()) then
      return 0
   end

   if not self._sight_sensor:contains_contents(target:get_id()) then
      -- can't see?  probably not a candidate unless...

      -- The exception is if we're taking an indirect path to our primary target which takes
      -- us temporarily out of sight range.
      local is_primary_target = target == self._combat_state:get_primary_target(self._entity)
      if not is_primary_target then
         return 0
      end
   end

   local target_mob = target:get_component('mob')
   if not target_mob then
      return 0
   end
   
   local buff_component = target:get_component('stonehearth:buffs')
   if buff_component and buff_component:has_buff('stonehearth:buffs:hidden:nonthreatening') then
      return 0
   end

   local target_location = target_mob:get_world_grid_location()
   if not target_location then -- target not in the world, player probably disconnected
      return 0
   end
   
   -- Inlining stonehearth.combat:get_distance_outside_leash() for perf.
   local leash = self._combat_state:get_leash_data()
   local distance_outside_leash
   if leash then
      local projected_point = Point3(target_location)
      projected_point.y = leash.center.y
      local closest_point = leash.cube:get_closest_point(projected_point)
      distance_outside_leash = closest_point:distance_to(target_location)
   else
      distance_outside_leash = 0
   end
   local score = aggro - distance_outside_leash * NOT_WITHIN_LEASH_PENALTY_MULTIPLIER
   if score <= 0 then
      return 0
   end

   local distance = entity_location:distance_to(target_location)
   if distance < 4 then
      -- Below a minimum distance, being closer doesn't matter.
      -- Should probably be based on reach and speed. Keeping it simple for now.
      distance = 4
   end
   score = score / distance

   if not self._is_npc then
      -- Inline radiant.entities.get_health_percentage for perf
      local expendable_resource_component = target:get_component('stonehearth:expendable_resources')
      local health_ratio = expendable_resource_component and expendable_resource_component:get_percentage('health') or 0

      if health_ratio > 0 then
         -- cap the multiplier at 50% health so we don't over kill / over target
         score = score * math.min(1 / health_ratio, FOCUS_FIRE_MAX_MULTIPLIER)
      end
   end

   return score
end

function FindTargetObserver:_get_retaliation_target()
   local now = radiant.gamestate.now()
   if now < self._last_attacked_time + self._retaliation_window then
      return self._last_attacker
   else
      return nil
   end
end

return FindTargetObserver
