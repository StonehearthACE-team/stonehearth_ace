-- ACE: just overriding to give a status_text_key

local DepartVisibleArea = radiant.class()

DepartVisibleArea.name = 'depart visible area'
DepartVisibleArea.does = 'stonehearth:depart_visible_area'
DepartVisibleArea.status_text_key = 'stonehearth_ace:ai.actions.status_text.departing'
DepartVisibleArea.args = {
   give_up_after = {  -- Unused in this action.
      type = 'string',
      default = '1d',
   },
}
DepartVisibleArea.priority = 1

function DepartVisibleArea:start_thinking(ai, entity, args)
   if radiant.terrain.is_supported(ai.CURRENT.location) then
      ai:set_think_output()
   else
      self._support_check_interval = stonehearth.calendar:set_interval('wait for support', '10m', function()
            if radiant.terrain.is_supported(ai.CURRENT.location) then
               self._support_check_interval:destroy()
               self._support_check_interval = nil
               ai:set_think_output()
            end
         end)
   end
end

function DepartVisibleArea:stop_thinking(ai, entity, args)
   if self._support_check_interval then
      self._support_check_interval:destroy()
      self._support_check_interval = nil
   end
end

function DepartVisibleArea:start(ai, entity, args)
   if not radiant.terrain.is_supported(ai.CURRENT.location) then
      ai:abort('not supported by terrain when starting')
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(DepartVisibleArea)
   :execute('stonehearth:find_point_beyond_visible_region') --actually is explored region, not visible region
   :execute('stonehearth:goto_location', {location = ai.PREV.location, reason = 'time to leave the world'})
   :execute('stonehearth:run_detached_effect', {effect = 'stonehearth:effects:fursplosion_effect'})
   :execute('stonehearth:destroy_entity') --TODO: rename destroy self to kill self, make new destroy_self, update loot component and others that listen on destroy
