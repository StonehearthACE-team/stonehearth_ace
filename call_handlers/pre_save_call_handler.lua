--[[
   Instead of immediately calling 'radiant:client:save_game', save functions point here first so that any pre-save
   actions necessary can be performed. This is a way to use _sv for storing large amounts of data and only perform
   mark_changed() right before saving.
]]
local log = radiant.log.create_logger('pre_save')

local PreSaveCallHandler = class()

local _pre_save_calls = {}
local _queued_calls = {}

function PreSaveCallHandler:register_pre_save_calls_command(session, response)
   local calls = radiant.resources.load_json('stonehearth_ace:data:pre_save_calls') or {}
   for call, args in pairs(calls) do
      _pre_save_calls[call] = {args = args.args}
   end
end

function PreSaveCallHandler:ace_pre_save_command(session, response)
   stonehearth_ace.connection:saved_variables_mark_changed()
   stonehearth_ace.mechanical:saved_variables_mark_changed()
   stonehearth_ace.vine:saved_variables_mark_changed()

   response:resolve({})
end

function PreSaveCallHandler:perform_pre_save_calls_command(session, response)
   log:debug('perform_pre_save_calls_command: #_queued_calls = %s', #_queued_calls)
   if #_queued_calls > 0 then
      response:reject({})
   else
      for call, details in pairs(_pre_save_calls) do
         table.insert(_queued_calls, {call = call, args = details.args})
      end

      self:_perform_next_queued_call(response)
   end
end

function PreSaveCallHandler:_perform_next_queued_call(response)
   local call = table.remove(_queued_calls)
   if not call then
      log:debug('resolving pre_save_calls')
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
   log:debug('calling perform_pre_save_calls_command...')
   _radiant.call('stonehearth_ace:perform_pre_save_calls_command')
      :done(function(result)
         log:debug('calling radiant:client:save_game with save_id [%s] and args [%s]', save_id, radiant.util.table_tostring(args))
         _radiant.call('radiant:client:save_game', save_id, args)
            :done(function(result)
               response:resolve({})
            end)
            :fail(function(result)
               response:reject({})
            end)
      end)
end

return PreSaveCallHandler