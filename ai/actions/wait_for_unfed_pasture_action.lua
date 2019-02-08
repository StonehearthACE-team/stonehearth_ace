local Entity = _radiant.om.Entity

local WaitForUnfedPasture = radiant.class()
WaitForUnfedPasture.name = 'wait for unfed pasture'
WaitForUnfedPasture.does = 'stonehearth:wait_for_unfed_pasture'
WaitForUnfedPasture.args = {
   pasture = Entity,        -- the stockpile that needs stuff
}

WaitForUnfedPasture.think_output = {
   filter_fn = 'function',
}

WaitForUnfedPasture.priority = 0

--[[
    Ace version:
    Changed the logic so it will retrieve animal feed based on material tags rather than specific uris.
    This allows us to add more fodder types.    
]]

local function make_filter_fn(material, owner)
   return function(item)
         if not radiant.entities.is_material(item, material) then
            -- not the right material?  bail.
            return false
         end
         if owner ~= '' and radiant.entities.get_player_id(item) ~= owner then
            -- not owned by the right person?  also bail!
            return false
         end
         return true
      end
end

function WaitForUnfedPasture:start_thinking(ai, entity, args)
   self._ai = ai
   self._log = ai:get_log()
   self._pasture_component = args.pasture:get_component('stonehearth:shepherd_pasture')
   self._ready = false

   self._on_feed_changed_listener = radiant.events.listen(args.pasture, 'stonehearth:shepherd_pasture:feed_changed', self, self._on_feed_changed)
   self:_on_feed_changed(args.pasture, self._pasture_component:needs_feed())  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function WaitForUnfedPasture:_on_feed_changed(pasture, needs_feed)
   if not pasture or not pasture:is_valid() then
      self._log:warning('pasture destroyed')
      return
   end

   if needs_feed and not self._ready then
      self._ready = true
      local material = self._pasture_component:get_animal_feed_material()
      local owner = radiant.entities.get_player_id(pasture)
      local filter_fn = stonehearth.ai:filter_from_key('stonehearth:wait_for_unfed_pasture', material, make_filter_fn(material, owner))
      self._ai:set_think_output({
         filter_fn = filter_fn
      })
   elseif not needs_feed and self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

function WaitForUnfedPasture:stop_thinking(ai, entity)
   if self._on_feed_changed_listener then
      self._on_feed_changed_listener:destroy()
      self._on_feed_changed_listener = nil
   end
end

return WaitForUnfedPasture
