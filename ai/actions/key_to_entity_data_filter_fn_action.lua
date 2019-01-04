local KeyToEntityDataFilter = radiant.class()

KeyToEntityDataFilter.name = 'entity data key to filter fn'
KeyToEntityDataFilter.does = 'stonehearth:key_to_entity_data_filter_fn'
KeyToEntityDataFilter.args = {
   key = 'string',            -- the key for the entity_data to look for
   owner = {                 -- must also be owned by (optional)
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
KeyToEntityDataFilter.think_output = {
   filter_fn = 'function',    -- a function which checks for that key
   description = 'string',    -- a description of the filter
}
KeyToEntityDataFilter.priority = 0

local ALL_FILTER_FNS = {}

function KeyToEntityDataFilter:start_thinking(ai, entity, args)
   local key = args.key

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:key_to_entity_data_filter_fn', key, function(item)
         if args.owner and args.owner ~= item:get_player_id() then
            return false
         end
         return radiant.entities.get_entity_data(item, key) ~= nil
      end)

   ai:set_think_output({
         filter_fn = filter_fn,
         description = string.format('"%s" ed', args.key),
      })
end

return KeyToEntityDataFilter
