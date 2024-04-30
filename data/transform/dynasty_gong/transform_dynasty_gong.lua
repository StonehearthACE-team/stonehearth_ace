local transform_dynasty_gong = {}

function transform_dynasty_gong.transform(entity, options, finish_cb)
   local stop_fn = function()
      radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = entity:get_player_id(), track = '' })
      end

   radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = entity:get_player_id(), track = 'dynasty' })
   stonehearth.calendar:set_timer('Dynasty_gong_stop', '12h', stop_fn)
end

function transform_dynasty_gong.destroy()
   radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = entity:get_player_id(), track = '' })
end

return transform_dynasty_gong
