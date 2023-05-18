local Entity = _radiant.om.Entity

local log = radiant.log.create_logger('drop_carrying_in_storage_action')

local DropCarryingInStorage = radiant.class()
DropCarryingInStorage.name = 'drop carrying in storage'
DropCarryingInStorage.does = 'stonehearth:drop_carrying_in_storage'
DropCarryingInStorage.args = {
   storage = Entity,
   ignore_missing = {
      type = 'boolean',
      default = false,
   },
}
DropCarryingInStorage.priority = 0

function DropCarryingInStorage:start_thinking(ai, entity, args)
   if args.storage:get_component('stonehearth:stockpile') then
      return
   end
   ai:set_think_output()
end

function DropCarryingInStorage:start(ai, entity, args)
   if not args.storage:is_valid() then
      log:error('%s is not a valid storage!', args.storage)
      ai:abort('storage is not valid')
      return
   end
	self._location_trace = radiant.entities.trace_location(args.storage, 'storage location trace')
		:on_changed(function()
				ai:abort('drop carrying in storage destination moved.')
			end)
end

function DropCarryingInStorage:stop(ai, entity, args)
	if self._location_trace then
		self._location_trace:destroy()
		self._location_trace = nil
	end
end

local ai = stonehearth.ai

return ai:create_compound_action(DropCarryingInStorage)
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.storage })
         :execute('stonehearth:drop_carrying_in_storage_adjacent', {
            storage = ai.ARGS.storage,
            ignore_missing = ai.ARGS.ignore_missing,
         })
