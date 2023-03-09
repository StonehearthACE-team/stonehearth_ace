local build_util = require 'lib.build_util'
local validator = radiant.validator

local ServiceCallHandler = class()

function ServiceCallHandler:get_service(session, response, name)
   validator.expect_argument_types({'string'}, name)
   if stonehearth_ace[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return stonehearth_ace[name].__saved_variables
   end
   response:reject('no such service')
end

function ServiceCallHandler:get_client_service(session, response, name)
   validator.expect_argument_types({'string'}, name)
   if stonehearth_ace[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return stonehearth_ace[name].__saved_variables
   end
   response:reject('no such service')
end

-- client call; we calculate and cache the result from the server on the client
-- so subsequent ui calls from the same client don't have to go back to the server
function ServiceCallHandler:get_all_weathers(session, response)
   if self._all_weathers then
      response:resolve({weathers = self._all_weathers})
   else
      _radiant.call_obj('stonehearth.seasons', 'get_seasons_command'):done(function(r)
         local weathers = {}
         for _, season in pairs(r) do
            for _, entry in ipairs(season.weather) do
               if not weathers[entry.uri] then
                  local weather = radiant.resources.load_json(entry.uri, true, false)
                  weathers[entry.uri] = weather
                  -- also go through any dynamic weathers to make sure they're included
                  if weather.dynamic_weather then
                     for dynamic_uri, _ in pairs(weather.dynamic_weather) do
                        if not weathers[dynamic_uri] then
                           weathers[dynamic_uri] = radiant.resources.load_json(dynamic_uri, true, false)
                        end
                     end
                  end
               end
            end
         end

         self._all_weathers = weathers
         response:resolve({weathers = weathers})
      end)
   end
end

return ServiceCallHandler
