local Entity = _radiant.om.Entity
local ComponentToFilterFn = radiant.class()

ComponentToFilterFn.name = 'component to filter fn'
ComponentToFilterFn.does = 'stonehearth_ace:component_to_filter_fn'
ComponentToFilterFn.args = {
   component = 'string',
   owner = {                 -- must also be owned by
      type = 'string',
      default = '',
   },
   iconic_only = {
      type = 'boolean',
      default = false
   }
}
ComponentToFilterFn.think_output = {
   filter_fn = 'function',   -- a function which checks component
   description = 'string',    -- a description of the filter
}
ComponentToFilterFn.version = 2
ComponentToFilterFn.priority = 1

local function create_filter_fn(owner, component, iconic_only)
   if not iconic_only then
      return function(item)
            if owner ~= '' and item:get_player_id() ~= owner then
               -- not owned by the right person
               return false
            end
            return item:get_component(component) ~= nil
         end
   end

   return function(item)
         if owner ~= '' and item:get_player_id() ~= owner then
            -- not owned by the right person
            return false
         end
         local root, iconic = entity_forms_lib.get_forms(item)
         if root and iconic then
            -- if this is an object with entity forms

            -- if we found the iconic forms item, we can check for if it matches
            -- DO NOT pick up items that are the root.
            if item == iconic then
               -- else if we are looking for the root's component and it matches, then good.
               if root:get_component(component) ~= nil then
                  return true
               end
            end
         elseif item:get_component(component) ~= nil then
            return true
         end
         return false
      end
end

function ComponentToFilterFn:start_thinking(ai, entity, args)
   local key = string.format('component:%s owner:%s iconic:%s', args.component, args.owner, tostring(args.iconic_only))

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:component_to_filter_fn', key, create_filter_fn(args.owner, args.component, args.iconic_only))

   ai:set_debug_progress('component key: ' .. key)

   ai:set_think_output({
         filter_fn = filter_fn,
         description = string.format('component is "%s"', args.component),
      })
end

return ComponentToFilterFn
