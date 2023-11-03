local conversation_lib = require 'stonehearth.lib.conversation.conversation_lib'
local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local SpookyToAnimalScript = radiant.class()

local WATCH_PET_EMOTE = 'emote_watch_pet'
local HEART_ICON = 'stonehearth:icons:thought_bubble:heart'

-- Custom stages for this script
local WATCH_ANIMAL_STAGE = 'watch_animal'
local AFFECTION_STAGE = 'affection'

function SpookyToAnimalScript:get_stages(conversation_manager)
   local stages = {
      order = {
         constants.conversation.stages.MOVE,
         constants.conversation.stages.SUBJECT, -- the spooky will talk about a subject with a sentiment colored bubble
         constants.conversation.stages.BRIDGE,
         constants.conversation.stages.GENERIC, -- the animal will play a randomly chosen generic animation
         WATCH_ANIMAL_STAGE,                    -- the spooky will watch the animal
         AFFECTION_STAGE                        -- the spooky will show affection with an animation and heart thought bubble
      },
      steps = {
         [constants.conversation.stages.MOVE] = 0,
         [constants.conversation.stages.SUBJECT] = 1,
         [constants.conversation.stages.BRIDGE] = { min = 0, max = 1 },
         [constants.conversation.stages.GENERIC] = 1,
         [WATCH_ANIMAL_STAGE] = 1,
         [AFFECTION_STAGE] = 1
      },
   }

   return stages
end

-- Pick a random active from a participant with the subject_matter component
function SpookyToAnimalScript:pick_subject(conversation_manager, initiator, participants)
   local subject_matter = constants.conversation.DEFAULT_SUBJECT
   for _, participant in ipairs(participants) do
      local smc = participant:get_component('stonehearth:subject_matter')
      local active_subject = smc and smc:get_random_active()
      if active_subject then
         subject_matter = active_subject.subject
         break
      end
   end

   return subject_matter
end

function SpookyToAnimalScript:set_speaker_for_stage(conversation_manager, stage_name, participants, step)
   local matching_stage = stage_name == WATCH_ANIMAL_STAGE or 
                          stage_name == AFFECTION_STAGE or 
                          stage_name == constants.conversation.stages.SUBJECT or
                          stage_name == constants.conversation.stages.BRIDGE
   
   if matching_stage then
      for i=1, #participants do
         conversation_manager:increment_speaker()
         local speaker = conversation_manager:get_current_speaker()
         if self:_is_spooky(speaker) then
            break
         end
      end
      radiant.assert('no spooky speaker found for stage %s', stage_name)
   else
      conversation_manager:increment_speaker()
   end

   return conversation_manager:get_current_speaker()
end

-- Get talk effects for this conversation that vary by stage
function SpookyToAnimalScript:get_talk_effects(conversation_manager, entity, stage_name, initiator)

   local effects
   -- Get effects for custom stages
   if stage_name == WATCH_ANIMAL_STAGE then
      effects = {
         animations = { WATCH_PET_EMOTE }
      }
   elseif stage_name == AFFECTION_STAGE then
      effects = conversation_lib.get_talk_effects_for_stage(entity, constants.conversation.stages.GENERIC, {
         sentiment_string = constants.sentiment.POSITIVE,
      })
      effects.thought_bubble_image = HEART_ICON
   else
      -- Get effects for the standard stages using conversation_lib
      local args = {}
      if stage_name == constants.conversation.stages.SUBJECT then
         args.subject_matter = conversation_manager:get_subject_matter()
         local subject_data = stonehearth.conversation:add_subject(entity, args.subject_matter)
         args.sentiment_string = subject_data and subject_data.sentiment_string
      elseif stage_name == constants.conversation.stages.GENERIC then
         args.hide_thought_bubble = true
      end

      effects = conversation_lib.get_talk_effects_for_stage(entity, stage_name, args)
   end

   conversation_lib.apply_overrides(entity, effects, stage_name)
   return effects
end

-- Play the entire animation for the subject and affection stages
function SpookyToAnimalScript:should_play_entire_animation(conversation_manager, stage_name)
   return stage_name == constants.conversation.stages.SUBJECT or
          stage_name == WATCH_ANIMAL_STAGE or
          stage_name == AFFECTION_STAGE
end

function SpookyToAnimalScript:_is_spooky(entity)
   local conversation_type = radiant.entities.get_entity_data(entity, 'stonehearth:conversation_type')
   return conversation_type == constants.conversation.participant_types.SPOOKY
end

function SpookyToAnimalScript:_get_species_name(entity)
   local data = radiant.entities.get_entity_data(entity, 'stonehearth:species')
   return data and data.display_name
end
return SpookyToAnimalScript