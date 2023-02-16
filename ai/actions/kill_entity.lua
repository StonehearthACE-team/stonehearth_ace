local log = radiant.log.create_logger('death')

local KillEntity = radiant.class()

KillEntity.name = 'destroy entity'
KillEntity.does = 'stonehearth:kill_entity'
KillEntity.args = {
   kill_data = {
      type = 'table',
      default = stonehearth.ai.NIL,
   },
}
KillEntity.version = 3
KillEntity.priority = 1

local destroy_scheduled = {}

function KillEntity:start_thinking(ai, entity, args)
   if not entity and not entity:is_vaild() then
      ai:set_think_output()
      return
   end
   if not destroy_scheduled[entity:get_id()]  then
      log:info('%s is dying', entity)
      ai:set_think_output()
   end
end

function KillEntity:run(ai, entity, args)
   log:detail('%s in KillEntity:run()', entity)

   if entity and entity:is_valid() then
      destroy_scheduled[entity:get_id()] = entity
      -- Shouldn't destroy the entity while the AI is running
      stonehearth.calendar:set_timer("KillEntity kill", 1,
         function ()
            if entity:is_valid() then
               log:detail('Killing %s', entity)
               local id = entity:get_id()
               --TODO: move all this functionality to an observer
               radiant.entities.kill_entity(entity, args.kill_data)
               destroy_scheduled[id] = nil
            end
         end
      )
   end
end

return KillEntity
