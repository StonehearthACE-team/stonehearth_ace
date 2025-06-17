local log = radiant.log.create_logger('transform_stunted')

local transform_stunted = {}

function transform_stunted.transform(entity, tf, ts, options)
   if not options or not options.script_stunt_stage then
      log:debug('no stunting options for %s, returning. Options received: %s', entity, radiant.util.table_tostring(options))
      return
   end
   
   if options.script_stunt_stage == 'now' then
      log:debug('setting %s to stunted', entity)
      entity:add_component('stonehearth:properties'):add_property('stonehearth_ace:stunted')
   else
      local transform_component = entity:get_component('stonehearth_ace:transform')
      if transform_component then
         if options.script_stunt_stage == 'cancel' then
            log:debug('cancelling queued stunting for %s', entity)
            transform_component:store_component_data('stonehearth:evolve', nil)
         else
            log:debug('queueing stunting for %s, on %s stage', entity, tostring(options.script_stunt_stage))
            transform_component:store_component_data('stonehearth:evolve', { stunt_stage = tostring(options.script_stunt_stage) })
         end
      end
      transform_component:reconsider_commands()
   end
end

return transform_stunted
