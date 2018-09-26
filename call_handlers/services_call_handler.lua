local build_util = require 'lib.build_util'
local validator = radiant.validator

local ServiceCallHandler = class()

function ServiceCallHandler:get_service(session, request, name)
   validator.expect_argument_types({'string'}, name)
   if stonehearth_ace[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return stonehearth_ace[name].__saved_variables
   end
   request:reject('no such service')
end

function ServiceCallHandler:get_client_service(session, request, name)
   validator.expect_argument_types({'string'}, name)
   if stonehearth_ace[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return stonehearth_ace[name].__saved_variables
   end
   request:reject('no such service')
end

return ServiceCallHandler
