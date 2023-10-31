local conversation_lib = require 'stonehearth.lib.conversation.conversation_lib'
local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local SpookyToHumanoidScript = radiant.class()

local WATCH_SPOOKY_EMOTE = { 'combat_1h_dodge' }
local SCARE_EMOTE = { 'emote_cry' }
local SPOOKY_QUESTION_EMOTE = { 'talk_surprise', 'emote_wave', 'talk_question' }
local SPOOK_EMOTE = { 'emote_roar', 'emote_anger', 'combat_1h_forehand_spin', 'talk_exclamation_irritated' }
local SPOOKED_SUBJECT = 'stonehearth_ace:icons:thought_bubble:candledark:spooked'
local SPOOKED_THOUGHT = 'stonehearth_ace:thoughts:candledark:spooked'
local SPOOKED_DEBUFF = 'stonehearth_ace:buffs:candledark:spooked'

-- Custom stages for this script
local SPOOKY_QUESTION_STAGE = 'spooky_question'
local SPOOKY_SPOOK_STAGE = 'spooky_spook'
local WATCH_SPOOKY_STAGE = 'watch_spooky'
local SCARE_STAGE = 'scare'

function SpookyToHumanoidScript:get_stages(conversation_manager)
   local stages = {
      order = {
         constants.conversation.stages.GREETING,
         constants.conversation.stages.MOVE,
         SPOOKY_QUESTION_STAGE, -- the humanoid will be curious about the spooky
         SPOOKY_SPOOK_STAGE, -- the spooky will play an animation
         WATCH_SPOOKY_STAGE,                    -- the humanoid will watch the spooky
         SCARE_STAGE                            -- the humanoid will be scared by the spooky
      },
      steps = {
         [constants.conversation.stages.GREETING] = 2,
         [constants.conversation.stages.MOVE] = 0,
         [SPOOKY_QUESTION_STAGE] = 1,
         [SPOOKY_SPOOK_STAGE] = 1,
         [WATCH_SPOOKY_STAGE] = 1,
         [SCARE_STAGE] = 1
      },
   }

   return stages
end

function SpookyToHumanoidScript:pick_subject(conversation_manager, initiator, participants)
   return 'stonehearth_ace:subjects:candledark:spooky'
end

function SpookyToHumanoidScript:set_speaker_for_stage(conversation_manager, stage_name, participants, step)
   local matching_stage = stage_name == WATCH_SPOOKY_STAGE or 
                          stage_name == SCARE_STAGE or 
                          stage_name == SPOOKY_QUESTION_STAGE
   
   if matching_stage then
      for i=1, #participants do
         conversation_manager:increment_speaker()
         local speaker = conversation_manager:get_current_speaker()
         if self:_is_humanoid(speaker) then
            break
         end
      end
      radiant.assert('no humanoid speaker found for stage %s', stage_name)
   else
      conversation_manager:increment_speaker()
   end

   return conversation_manager:get_current_speaker()
end

-- Get talk effects for this conversation that vary by stage
function SpookyToHumanoidScript:get_talk_effects(conversation_manager, entity, stage_name, initiator)

   local effects
   -- Get effects for custom stages
   if stage_name == SPOOKY_QUESTION_STAGE then
      effects = {
         animations = SPOOKY_QUESTION_EMOTE 
      }
   elseif stage_name == SPOOKY_SPOOK_STAGE then
      effects = {
         animations = SPOOK_EMOTE,
         thought_bubble_image = SPOOKED_SUBJECT,
         thought_bubble_effect = constants.conversation.THOUGHT_BUBBLE_EFFECTS[constants.sentiment.POSITIVE]
      }
   elseif stage_name == WATCH_SPOOKY_STAGE then
      effects = {
         animations = WATCH_SPOOKY_EMOTE
      }
   elseif stage_name == SCARE_STAGE then
      effects = {
         animations = SCARE_EMOTE,
         thought_bubble_image = SPOOKED_SUBJECT,
         thought_bubble_effect = constants.conversation.THOUGHT_BUBBLE_EFFECTS[constants.sentiment.NEGATIVE_DISLIKE]
      }
   else
      -- Get effects for the standard stages using conversation_lib
      local args = {}
      if stage_name == constants.conversation.stages.GREETING then
         args.is_initiator = (entity == initiator)
      elseif stage_name == constants.conversation.stages.SUBJECT then
         args.subject_matter = conversation_manager:get_subject_matter()
         local subject_data = stonehearth.conversation:add_subject(entity, args.subject_matter)
         args.sentiment_string = subject_data and subject_data.sentiment_string
      end

      effects = conversation_lib.get_talk_effects_for_stage(entity, stage_name, args)
   end

   conversation_lib.apply_overrides(entity, effects, stage_name)
   return effects
end

function SpookyToHumanoidScript:should_play_entire_animation(conversation_manager, stage_name)
   return stage_name == SPOOKY_QUESTION_STAGE or
          stage_name == WATCH_SPOOKY_STAGE or
          stage_name == SCARE_STAGE
end

-- Add thoughts to humanoid participants
function SpookyToHumanoidScript:end_conversation(conversation_manager, participants, finished_successfully)
   if finished_successfully then
      for _, participant in pairs(participants) do
         if self:_is_humanoid(participant) then
            local thought_key = SPOOKED_THOUGHT
            local buff_key = SPOOKED_DEBUFF
            radiant.entities.add_thought(participant, thought_key)
            radiant.entities.add_buff(participant, buff_key)
         end
      end
   end
end

function SpookyToHumanoidScript:_is_humanoid(entity)
   local conversation_type = radiant.entities.get_entity_data(entity, 'stonehearth:conversation_type')
   return conversation_type == constants.conversation.participant_types.HUMANOID
end

return SpookyToHumanoidScript