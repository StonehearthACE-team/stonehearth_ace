-- Based on the great Summon action and Beast Tamer controller from BrunoSupremo's 'Swamp Biome + Firefly Goblins + Beast Tamer' mod, with permission!
local rng = _radiant.math.get_default_rng()
local Entity = _radiant.om.Entity

local AttackSummon = class()

AttackSummon.name = 'attack summon'
AttackSummon.does = 'stonehearth_ace:combat:attack_summon'
AttackSummon.args = {
target = Entity
}
AttackSummon.version = 2
AttackSummon.priority = 0.8
AttackSummon.weight = 1

function AttackSummon:start_thinking(ai, entity, args)
   -- refetch every start_thinking as the set of actions may have changed
   self._attack_types = stonehearth.combat:get_combat_actions(entity, 'stonehearth_ace:combat:summon_attacks')

   self:_choose_attack_action(ai, entity, args)
end

function AttackSummon:_choose_attack_action(ai, entity, args)
   self._attack_info = stonehearth.combat:choose_attack_action(entity, self._attack_types)

   if self._attack_info then
      ai:set_think_output()
      return
   end

   -- choose_attack_action might have complex logic, so just wait 1 second and try again
   -- instead of trying to guess which coolodowns to track
   self._think_timer = stonehearth.combat:set_timer("AttackSummon waiting for cooldown", 1000, function()
      self._think_timer = nil
      self:_choose_attack_action(ai, entity, args)
      end)
end

function AttackSummon:stop_thinking(ai, entity, args)
   if self._think_timer then
      self._think_timer:destroy()
      self._think_timer = nil
   end

   self._attack_types = nil
end

function AttackSummon:run(ai, entity, args)
   local target = args.target
   local attack_info = self._attack_info
   local uris = {}

   for uri, active in pairs(attack_info.uris or {}) do
      if active then
         table.insert(uris, uri)
      end
   end

   -- Determine how many creatures to summon
   local amount = 1
   if type(attack_info.amount) == 'number' then
      amount = attack_info.amount
   elseif type(attack_info.amount) == 'table' then
      local min = attack_info.amount.min or 1
      local max = attack_info.amount.max or 2
      amount = rng:get_int(min, max)
   end

   ai:set_status_text_key(
      attack_info.custom_status_text or 'stonehearth_ace:ai.actions.status_text.summoning',
      { target = target }
   )

   if radiant.entities.is_standing_on_ladder(entity) then
      ai:abort('Cannot attack while standing on ladder')
      return
   end

   radiant.entities.turn_to_face(entity, target)

   -- Start cooldown and unprotect target (they might die)
   stonehearth.combat:start_cooldown(entity, attack_info)
   ai:unprotect_argument(target)

   local args = {
      summon_effect = attack_info.summon_effect or 'stonehearth:effects:spawn_entity',
      copy_attributes = attack_info.copy_attributes,
      link_to_summoner = attack_info.link_to_summoner ~= false
   }

   -- Create summons with staggered delays
   self._summon_timers = {}
   for i = 1, amount do
      local uri = uris[rng:get_int(1, #uris)]
      local offset = (0.1 * i + 1) - (0.1 * amount) / 2
      local delay_ms = attack_info.active_frame * 33.3 * offset

      self._summon_timers[i] = stonehearth.combat:set_timer("AttackSummon summon_delay " .. i, delay_ms, function()
         self:_create_summon(uri, entity, args)
      end)
   end

   -- Play the summoner effect
   ai:execute('stonehearth:run_effect', { effect = attack_info.effect })
end

function AttackSummon:_create_summon(uri, entity, args)
   if not args or not uri or not entity then
      return
   end

   local summon_effect = args.summon_effect
   local copy_attributes = args.copy_attributes
   local link_to_summoner = args.link_to_summoner

   local location = radiant.entities.get_world_location(entity)
   if not location then
      return
   end

   local player_id = radiant.entities.get_player_id(entity)
   local summon = radiant.entities.create_entity(uri, { owner = player_id })

   -- Copy attributes if specified
   if copy_attributes then
      local menace = radiant.entities.get_attribute(entity, "menace") or 0
      local courage = radiant.entities.get_attribute(entity, "courage") or 0
      radiant.entities.set_attribute(summon, "menace", menace + 1)
      radiant.entities.set_attribute(summon, "courage", courage + 1)
   end

   -- Place summon somweher nearby
   local placement = radiant.terrain.find_placement_point(location, 3, 5, entity, nil, true)
   if placement then
      radiant.terrain.place_entity_at_exact_location(summon, placement)
   end

   -- Run the summon's summoning effect
   radiant.effects.run_effect(summon, summon_effect)

   -- Link summon to summoner if required (if summoner dies, all summons will die too >:) 
   if link_to_summoner then
      local summon_comp = summon:add_component('stonehearth_ace:summon')
      if entity:is_valid() and summon_comp and summon_comp._link_to_summoner then
         summon_comp:_link_to_summoner(entity)
      end
   end
end

function AttackSummon:stop(ai, entity, args)
   if self._summon_timers then
      for i = 1, #self._summon_timers do
         self._summon_timers[i]:destroy()
      end
      self._summon_timers = nil
   end

   self._attack_info = nil
end

return AttackSummon