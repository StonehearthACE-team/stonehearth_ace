-- ACE: implemented smart storage filter caching

local Entity = _radiant.om.Entity
local FindReachableEntityTypeAnywhere = radiant.class()

FindReachableEntityTypeAnywhere.name = 'find reachable entity type anywhere'
FindReachableEntityTypeAnywhere.does = 'stonehearth:find_reachable_entity_type_anywhere'
FindReachableEntityTypeAnywhere.args = {
   filter_fn = 'function',             -- filter describing the kinds of entities to consider.
   description = 'string',             -- description of the initiating compound task (for debugging)
   ignore_leases = {
      default = false, -- Set to true if we should consider entities that are already leased
      type = 'boolean',
   },
   owner_player_id = {         -- optional faction override to use when checking ai lease
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   material = 'string',
}

FindReachableEntityTypeAnywhere.version = 2
FindReachableEntityTypeAnywhere.priority = 1

local NONE = 0
local STORAGE = 1
local GROUND = 2
local ALL = STORAGE + GROUND

local NO_MATERIAL = stonehearth.constants.construction.NO_MATERIAL

local log = radiant.log.create_logger('find_reachable_entity_type_anywhere')

--[[
So, why this?
Basic problem: any AI "branch" that contains more than one 'item finder'
can always incorrectly block indefinitely. In the case of building, the
first item_finder that runs looks for building chunks to work on; the
second set that runs are contained in the 'pickup_item' branch, which
looks for appropriate resources with which to build that chunk. If no
such resources are around, the parts of the branch associated with
searching the ground/storage will wait on their item_finders indefinitely.
Consequently, if you have two chunks that could have work done, one that
is stone and does NOT have resources, and the other that is wood and does
have available resources, and the AI finds the stone chunk first, it will
wait forever trying to pickup stone, and cannot backtrack to consider the
other chunk.

This serves as part of the solution: a method that looks for things, including
in storage, and does not block indefinitely while waiting for something.  We
ai:reject if we exhaust, which allows us to backtrack upstream in order to
look for other things.
]]


local function make_storage_filter_fn(args_filter_fn)
   return function(entity)
         local storage = entity:get('stonehearth:storage')
         if not storage then
            return false
         end

         -- Don't look in stockpiles.  Ground searching is done separately.
         if entity:get('stonehearth:stockpile') then
            return false
         end

         -- Don't take items out of non-public storage (e.g.hearthling backpacks)
         if not storage:is_public() then
            return false
         end

         return storage:storage_contains_filter_fn(args_filter_fn)
      end
end

function FindReachableEntityTypeAnywhere:_set_exhausted(type)
   self._exhausted = self._exhausted + type

   if self._exhausted == ALL then
      self._exhausted = NONE
      --printf('everything exhausted')
      self._ai:reject('freta exhausted everything!')
   end
end

function FindReachableEntityTypeAnywhere:start_thinking(ai, entity, args)
   self._ai = ai
   self._description = args.description
   self._filter_fn = args.filter_fn
   self._log = log
   self._location = ai.CURRENT.location
   self._exhausted = NONE

   --printf('%s freta start thinking %s', entity, args.material)
   -- This is a hotspot, and creating loggers here is expensive, so only enable this for debugging.
   -- self._log = ai:get_log()

   -- If the filter is for a no-material object, then use 'that'.
   if args.material == NO_MATERIAL then
      ai:set_think_output({})
      return
   end

   -- If we're holding, use that.
   local carried_item = ai.CURRENT.carrying
   if carried_item then
      if self._filter_fn(carried_item) then
         ai:set_think_output({})
         return
      else
         local iconic_form = carried_item:get('stonehearth:iconic_form')
         if iconic_form and self._filter_fn(iconic_form:get_root_entity()) then
            ai:set_think_output({})
            return
         end
      end
   end


   -- If we have a backpack, and it's in that, use that.
   local backpack = entity:get('stonehearth:storage')
   if backpack then
      for _, item in pairs(backpack:get_items()) do
         if self._filter_fn(item) then
            ai:set_think_output({})
            return
         else
            local iconic_form = item:get('stonehearth:iconic_form')
            if iconic_form and self._filter_fn(iconic_form:get_root_entity()) then
               ai:set_think_output({})
               return
            end
         end
      end
   end


   -- Look everywhere on the ground.
   local ground_exhausted_cb = function()
     -- printf('%s ground exhausted', entity)

      if self._ground_if == nil then
         return
      end
      self._ground_if:destroy()
      self._ground_if = nil


      self:_set_exhausted(GROUND)
   end
   local ground_found_cb = function(item, flush)
      local item_id = item:get_id()
      if ai.CURRENT.self_reserved[item_id] then
         self._log:spam('already reserved')
         return false
      end

      if not stonehearth.ai:can_acquire_ai_lease(item, entity) then
         return false
      end

      --printf('found a ground item: %s', item)
      ai:set_think_output({})

      return true
   end
   self._log:info('creating ground item finder for %s @ %s', self._description, self._location)
   self._ground_if = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
         self._location,
         args.filter_fn,
         ground_found_cb,
         {
            description = self._description .. ' (ground)',   -- for those of us in meat space
            owner_player_id = args.owner_player_id,
            exhausted_cb = ground_exhausted_cb,
         })



   -- Look everywhere in accessible storage.
   local storage_exhausted_cb = function()
      --printf('%s storage exhausted', entity)


      if self._storage_if == nil then
         --printf('...but already destroyed?')
         return
      end

      self._storage_if:destroy()
      self._storage_if = nil


      self:_set_exhausted(STORAGE)
   end

   local storage_found_cb = function(storage)

      ai:set_think_output({})

      return true
   end
   local storage_filter_fn = stonehearth.ai:filter_from_key('stonehearth:find_reachable_entity_type_anywhere',
                                                            args.filter_fn, make_storage_filter_fn(args.filter_fn))
   self._log:info('creating storage item finder for %s @ %s', self._description, self._location)
   self._storage_if = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
         self._location,
         storage_filter_fn,
         storage_found_cb,
         {
            description = self._description .. ' (storage)',   -- for those of us in meat space
            owner_player_id = args.owner_player_id,
            exhausted_cb = storage_exhausted_cb,
         })

end

function FindReachableEntityTypeAnywhere:stop_thinking(ai, entity, args)
   --printf('%s freta stop_thinking', entity)
   self:_destroy_itemfinders()
end

function FindReachableEntityTypeAnywhere:stop(ai, entity, args)
   -- Just in case....
   --printf('%s freta stop', entity)
   self:_destroy_itemfinders()
end

function FindReachableEntityTypeAnywhere:_destroy_itemfinders()
   if self._storage_if then
      self._storage_if:destroy()
      self._storage_if = nil
   end

   if self._ground_if then
      self._ground_if:destroy()
      self._ground_if = nil
   end
end

function FindReachableEntityTypeAnywhere:on_reject(ai, entity, args)
   --printf('%s freta rejecting', entity)
end


return FindReachableEntityTypeAnywhere
