local log = radiant.log.create_logger('transform_stunted')

local transform_stunted = {}

function transform_stunted.transform(entity, options, finish_cb)
   log:debug('setting %s to stunted', entity)
   entity:add_component('stonehearth:properties'):add_property('stonehearth_ace:stunted')
end

return transform_stunted
