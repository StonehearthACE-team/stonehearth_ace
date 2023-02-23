-- ACE: implemented smart storage filter caching

local Path = _radiant.sim.Path
local Entity = _radiant.om.Entity
local FindPathToStorageContainingEntityType = radiant.class()

FindPathToStorageContainingEntityType.name = 'find path to storage containing entity type'
FindPathToStorageContainingEntityType.does = 'stonehearth:find_path_to_storage_containing_entity_type'
FindPathToStorageContainingEntityType.args = {
   filter_fn = 'function',             -- entity to find a path to
   description = 'string',             -- description of the initiating compound task (for debugging)
}
FindPathToStorageContainingEntityType.think_output = {
   destination = Entity,   -- the destination (container)
   path = Path,            -- the path to destination, from the current Entity
}
FindPathToStorageContainingEntityType.priority = 0

local function make_filter_fn(args_filter_fn)
   return function(entity)
         local storage = entity:get_component('stonehearth:storage')
         if not storage then
            return false
         end

         -- Don't look in stockpiles.  It's expensive and they can be found by the
         -- generic 'stonehearth:find_path_to_entity_type' which just looks for stuff
         -- on the ground.
         if entity:get_component('stonehearth:stockpile') then
            return false
         end

         -- Don't take items out of non-public storage (e.g.hearthling backpacks)
         if not storage:is_public() then
            return false
         end

         return storage:storage_contains_filter_fn(args_filter_fn)
      end
end

function FindPathToStorageContainingEntityType:start_thinking(ai, entity, args)
   self._description = args.description
   self._log = ai:get_log()
   ai:set_debug_progress('find path to storage containing entity type: ' .. self._description)

   local solved = function(path)
      local destination = path:get_destination()
      self:_destroy_pathfinder('solution is' .. tostring(destination))
      ai:set_think_output({
            path = path,
            destination = destination,
         })
   end

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:find_path_to_storage_containing_entity_type',
      args.filter_fn,
      make_filter_fn(args.filter_fn))

   self._filter_fn = filter_fn
   self._item_filter_fn = args.filter_fn
   self._location = ai.CURRENT.location
   self._log:debug('creating bfs pathfinder for %s (container) @ %s', self._description, self._location)
   self._pf_component = entity:add_component('stonehearth:pathfinder')

   -- many actions in our dispatch tree may be asking to find paths to items of
   -- identical types.  for example, each structure in an all wooden building will
   -- be asking for 'wood resource' materials.  rather than start one bfs pathfinder
   -- for each action in the tree, they'll all share the one managed by the
   -- 'stonehearth:pathfinder' component.  this is a massive performance boost.
   self._pathfinder = self._pf_component:find_path_to_entity_type(self._location, -- where to search from?
                                                                  filter_fn,      -- the actual filter function
                                                                  self._description, -- for those of us in meat space
                                                                  solved)         -- our solved callback
end

function FindPathToStorageContainingEntityType:stop_thinking(ai, entity, args)
   self:_destroy_pathfinder('stop_thinking')
end

function FindPathToStorageContainingEntityType:_destroy_pathfinder(reason)
   if self._pathfinder then
      self._pathfinder:destroy()
      self._pathfinder = nil
      self._log:debug('destroying bfs pathfinder for %s @ %s (reason:%s)', self._description, self._location, reason)
   end
end

return FindPathToStorageContainingEntityType
