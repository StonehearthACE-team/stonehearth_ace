--[[
   Instead of immediately calling 'radiant:client:save_game', save functions point here first so that any pre-save
   actions necessary can be performed. This is a way to use _sv for storing large amounts of data and only perform
   mark_changed() right before saving.

   DEPRECATED: this functionality is not actively in use as pre-save calls were causing instability
   persistence data saving is now handled through regular scheduling
]]
local log = radiant.log.create_logger('pre_save')

local PreSaveCallHandler = class()

local _queued_calls = {}

function PreSaveCallHandler:ace_pre_save_command(session, response)
   stonehearth_ace.persistence:save_town_data()

   response:resolve({})
end

function PreSaveCallHandler:perform_pre_save_calls_command(session, response)
   if #_queued_calls > 0 then
      response:reject({})
   else
      local calls = radiant.resources.load_json('stonehearth_ace:data:pre_save_calls') or {}
      for call, details in pairs(calls) do
         table.insert(_queued_calls, {call = call, args = details.args})
      end

      self:_perform_next_queued_call(response)
   end
end

function PreSaveCallHandler:_perform_next_queued_call(response)
   local call = table.remove(_queued_calls)
   if not call then
      response:resolve({})
   else
      _radiant.call(call.call, call.args)
         :done(function(result)
            self:_perform_next_queued_call(response)
         end)
   end
end

-- client call
function PreSaveCallHandler:save_game_command(session, response, save_id, args)
   _radiant.call('stonehearth_ace:perform_pre_save_calls_command')
      :done(function(result)
         response:resolve({})
         --[[
         log:debug('calling radiant:client:save_game for id %s with timestamp: %s (%s)', save_id, args.timestamp, type(args.timestamp))
         _radiant.call('radiant:client:save_game', save_id, args)
            :done(function(r)
               response:resolve(r)
            end)
            :fail(function(r)
               response:reject(r)
            end)
            ]]
      end)
end

return PreSaveCallHandler