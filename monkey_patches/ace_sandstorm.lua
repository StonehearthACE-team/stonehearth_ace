local AceSandstormWeather = class()

function AceSandstormWeather:_apply_stormicle_damage_to(item)
    if stonehearth.game_creation:get_game_mode() ~= 'stonehearth:game_mode:peaceful' then
        local expendables = item:get_component('stonehearth:expendable_resources')
        local target_type = radiant.entities.get_entity_data(item, 'stonehearth:target_type')
        if expendables and expendables:get_max_value('health') and target_type and target_type.target_type == 'mob' then
            radiant.entities.add_buff(item, 'stonehearth:buffs:weather:hit_by_sandstorm')
            return
        end
    end

    if item:get_component('stonehearth:crop') then
        -- ACE: check the field type; we don't want to harm bushes or trees
        local field = item:get_component('stonehearth:crop'):get_field()
        local field_type = field:get_field_type()
        
        if field_type ~= 'bush_farm' and field_type ~= 'orchard' and field_type ~= 'treefarm' then
            if rng:get_real(0, 1) <= CROP_DESTROY_CHANCE then
                radiant.entities.kill_entity(item)
            end
        end
    end
end

return AceSandstormWeather