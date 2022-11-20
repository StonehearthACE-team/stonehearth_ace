local WaitForGlobalEventEncounter = class()

function WaitForGlobalEventEncounter:initialize()
   self._sv.source = nil
   self._sv.ctx = nil
   self._sv.event = nil
   self._sv.is_repeatable = false
   self._log = radiant.log.create_logger('game_master.encounters.wait_for_global_event')
end

function WaitForGlobalEventEncounter:activate()
   if self._sv.source then
      self:_listen_for_event()
   end
end

function WaitForGlobalEventEncounter:start(ctx, info)
   local event = info.event
   local source = info.source and self:_get_source(info.source)

   assert(event and source)
   
   self._sv.is_repeatable = info.repeatable or false
   
   self._sv.ctx = ctx
   self._sv.source = source
   self._sv.event = event
   self.__saved_variables:mark_changed()

   self:_listen_for_event()
end

function WaitForGlobalEventEncounter:_get_source(source)
   -- try to resolve the source globally; e.g., 'stonehearth' or 'stonehearth_ace.mercantile'
   -- defaults to 'radiant'
   local default = radiant
   local fn = string.format('return function() return %s end', source)
   local f, error = loadstring(fn)
   if f == nil then
      -- parse error?  no problem!
      return default
   end

   local success, result = pcall(function()
         local fetch = f()
         return fetch()
      end)
   if not success then
      return default
   end

   return result
end

function WaitForGlobalEventEncounter:_listen_for_event()
   local event = self._sv.event
   local source = self._sv.source

   self._log:debug('listening for "%s" event on "%s"', event, tostring(source))
   self._listener = radiant.events.listen(source, event, function()
         local ctx = self._sv.ctx
         -- save location of the source when event occured
         ctx.source_location = type(source) == 'userdata' and radiant.entities.get_world_grid_location(source) or nil
         self._log:debug('"%s" event on "%s" triggered!', tostring(source), event)
         self:_on_event_triggered(ctx)
      end)
end

function WaitForGlobalEventEncounter:_on_event_triggered(ctx)
   if not self._listener and not self._listeners then
      return  -- Repeatable events may be queued after we've been destroyed.
   end
   if self._sv.is_repeatable then
      ctx.arc:spawn_encounter(ctx, ctx.encounter:get_out_edge())
   else
      -- if event is triggered, remove source so we don't relisten on activate
      self._sv.source = nil
      self.__saved_variables:mark_changed()
      ctx.arc:trigger_next_encounter(ctx)
   end
end

function WaitForGlobalEventEncounter:stop()
   if self._listener then
      self._listener:destroy()
      self._listener = nil
   end
   if self._listeners then
      for _,listener in pairs(self._listeners) do
         listener:destroy()
      end
      self._listeners = nil
   end
end

function WaitForGlobalEventEncounter:destroy()
   self:stop()
end

return WaitForGlobalEventEncounter

--[[
<StonehearthEditor>
{
   "type" : "encounter",
   "encounter_type" : "wait_for_global_event",

   "in_edge"  : "<in edge>",
   "out_edge" : "<out edge>",

   "wait_for_global_event_info" :  {
      "mod_root": "stonehearth_ace",
      "source" : "radiant",
      "event"  : "radiant:entity:pre_destroy"
   }
}
</StonehearthEditor>
<StonehearthEditorSchema>
{
   "$schema": "http://json-schema.org/draft-04/schema#",
   "id": "http://stonehearth.net/schemas/encounters/wait_for_global_event.json",
   "title": "An encounter that waits for an event on an entity (or entitites) before triggering its out edges.",
   "allOf": [
      { "$ref": "encounter.json" },
      {
         "type": "object",
         "properties": {
            "encounter_type": { "enum": ["wait_for_global_event"] },
            "wait_for_global_event_info": {
               "type": "object",
               "mod_root": "stonehearth_ace",
               "properties": {
                  "source": { "type": "string" },
                  "event": { "type": "string" },
                  "repeatable": { "type": "boolean", "description": "If true, continues to listen and trigger out edges until destroyed." }
               },
               "required": ["event"],
               "additionalProperties": false
            }
         },
         "required": ["type", "encounter_type", "in_edge", "wait_for_global_event_info"]
      }
   ]
}
</StonehearthEditorSchema>
]]
