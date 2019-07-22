--[[
   this action does the same thing as stonehearth:reserve_entity
   but only if there is no condition specified or if the condition resolves to true
   if the condition resolves to false, no reservation is necessary, and none will be attempted
   but this way the potential reservation can be done smoothly in a compound action
]]

local Entity = _radiant.om.Entity
local ReserveEntityIfCondition = radiant.class()

ReserveEntityIfCondition.name = 'reserve entity'
ReserveEntityIfCondition.does = 'stonehearth_ace:reserve_entity_if_condition'
ReserveEntityIfCondition.args = {
   entity = Entity,           -- entity to reserve
   reserve_from_self = {
      type = 'boolean',
      default = true,
   },
   owner_player_id = {      -- faction to lease the entity under
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   condition = 'function'
}
ReserveEntityIfCondition.priority = 0

local log = radiant.log.create_logger('reserve_entity')

function ReserveEntityIfCondition:start_thinking(ai, entity, args)
   self._log = log
   -- This is a hotspot, and creating loggers here is expensive, so only enable this for debugging.
   -- self._log = ai:get_log()

   local to_reserve = args.entity

   local result = args.condition and args.condition(to_reserve)
   if result == false then
      self._wants_lease = false
      ai:set_think_output()
      return
   end

   self._wants_lease = true

   -- NOT acquiring the lease here is a huge perf bottleneck with backpacks.  many
   -- many entities end up contending for the same resources with lots of rejects and
   -- aborts (the aborts are the ones that are killing us). if we end up not taking this
   -- that through the ai, though, we don't want to block anyone else.  take a short-lived
   -- lease which will automatically expire  -- tony
   self._temp_lease = stonehearth.ai:acquire_ai_lease(to_reserve, entity, 1000, args.owner_player_id)
   if not self._temp_lease then
      -- *** UPDATE ***
      -- we now call :reject() to implement the 'Maybe one day...' case mentioned
      -- below.  This comment preserved for posterity... - tony
      --
      -- [blockquote]
      -- the code used to just return here.  after all, if we're going to abort
      -- on start, can't we just not call set_think_output() and let some other
      -- branch of whatever activity is requesting the reservation take over?
      -- well, sometimes this is the *only* branch available, and by never calling
      -- set_think_output() we hang this entire sub-activity.  in many cases, if
      -- only we let everyone above us in the action tree think again, they could
      -- find something much more suitable (e.g. there are many MANY logs in the world
      -- that a worker could pickup, but the pathfinder looking for them happened to
      -- pick one *JUST* before a reservation got slapped on it.  if we ask it to look
      -- again, it will simply skip over that one and likely find one that's not reserved)
      --
      -- so what are we to do?  if we call set_thinking_output() immediately, start()
      -- is almost certainly going to abort().  if we never call set_think_output(), we
      -- have to wait for some other influence to kick our parent and start it thinking
      -- again.  ideally the ai system would have a call which meant "yo bro, i don't
      -- know how we got here but this just isn't going to work.  you need to back way
      -- up and start over".  Then if every unit in a frame had entered that state, the
      -- frame would simply start_thinking() over.  Maybe one day I will implement this,
      -- but we JUST stabilized the AI system and I don't want to wreak havoc on it yet
      -- again. -- tony
      -- [/blockquote]
      --
      local reason = string.format('%s cannot acquire ai lease on %s.', tostring(entity), tostring(to_reserve))
      self._log:debug('rejecting: ' .. reason)
      ai:reject(reason)
      return
   end

   -- see if we should mark the item as reserved in CURRENT.  this is to prevent an
   -- entity from visiting the same item multiple times in an action.  for example,
   -- the action which loops looking for things to pickup should not be able to find
   -- the same item in different loop iterations.  we need to store this information in
   -- CURRENT, as the actual reservation isn't taken until :start(). - tony
   if args.reserve_from_self then
      -- xxx: should we call reject here if already self reserved?  hmmm. - tony
      ai.CURRENT.self_reserved[to_reserve:get_id()] = to_reserve
   end

   self._log:debug('no one holds lease yet.')
   ai:set_debug_progress('temp-reserved ' .. tostring(to_reserve))
   ai:set_think_output()
end

function ReserveEntityIfCondition:start(ai, entity, args)
   local target = args.entity

   -- only try to get a permanent lease if we tried for a temp lease
   if self._wants_lease then
      self._log:debug('trying to acquire lease...')
      self._permanent_lease = stonehearth.ai:acquire_ai_lease(target, entity, nil, args.owner_player_id)
      if not self._permanent_lease then
         ai:abort(string.format('could not reserve %s (%s has it).', tostring(target), tostring(stonehearth.ai:get_ai_lease_owner(target, args.owner_player_id))))
         return
      end
      ai:set_debug_progress('reserved ' .. tostring(args.entity))
      self._log:debug('got lease!')
   end
end

function ReserveEntityIfCondition:stop_thinking(ai, entity, args)
   -- if we didn't actually acquire the lease in `start`, go ahead and let go of it
   -- now so someone else who wants to grab it can get it (otherwise, we need to wait
   -- for the timeout we set in `start_thinking` to expire!)
   if self._temp_lease then
      self._temp_lease:destroy()
      self._temp_lease = nil
   end
   if not self._permanent_lease then
      ai:set_debug_progress('stopped thinking; no lease held')
   end
end

function ReserveEntityIfCondition:stop(ai, entity, args)
   if self._permanent_lease then
      self._permanent_lease:destroy()
      self._permanent_lease = nil
      ai:set_debug_progress('stopped; no lease held')
   end
end

return ReserveEntityIfCondition
