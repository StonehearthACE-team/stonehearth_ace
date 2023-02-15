var _selectionHasComponentInfo = false;
var _showJobToggleButton = false;

var _selectionHasComponentInfoChanged = function() {
   if (_selectionHasComponentInfo) {
      $('#componentInfoButton').show().css('display', 'inline-flex');
   }
   else {
      $('#componentInfoButton').hide();
   }
   let unitFrame = App.gameView.getView(App.StonehearthUnitFrameView);
   if (unitFrame) {
      unitFrame._updateUnitFrameWidth();
   }
};

var _showJobToggleButtonChanged = function() {
   let unitFrame = App.gameView.getView(App.StonehearthUnitFrameView);
   if (unitFrame) {
      unitFrame.set('jobToggleButtonSettingEnabled', _showJobToggleButton);
   }
};

$(top).on("selection_has_component_info_changed", function (_, e) {
   _selectionHasComponentInfo = e.has_component_info;
   _selectionHasComponentInfoChanged();
});

$(top).on("show_job_toggle_button_changed", function (_, e) {
   _showJobToggleButton = e.value;
   _showJobToggleButtonChanged();
});

$(top).on('stonehearthReady', function (cc) {
   // need to apply the setting on load as well
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_job_toggle_button', function(value) {
      $(top).trigger('show_job_toggle_button_changed', { value: value });
   });
});

$(top).on("show_bulletin_from_component", function (_, e) {
   var componentData = e.event_data && e.entity_data[e.event_data.component];
   var bulletin = componentData && componentData[e.event_data.property];
   if (bulletin) {
      App.bulletinBoard.tryShowBulletin(bulletin);
   }
});

var updateUnitFrame = function(data) {
   if (!App.gameView) {
      return;
   }
   let unitFrame = App.gameView.getView(App.StonehearthUnitFrameView);
   if (unitFrame) {
      unitFrame.set('uri', data.selected_entity);
   }
};

$(document).ready(function(){
   $(top).on("radiant_selection_changed.unit_frame", function (_, data) {
      updateUnitFrame(data);
   });
   $(top).on("radiant_toggle_lock", function(_, data) {
      if (!App.gameView) {
         return;
      }
      radiant.call('stonehearth:toggle_lock', data.entity);
   });
});

App.StonehearthUnitFrameView = App.View.extend({
   templateName: 'unitFrame',
   uriProperty: 'model',
   components: {
      "stonehearth:ai": {
         "status_text_data": {}
      },
      "stonehearth:attributes": {
         "attributes": {}
      },
      "stonehearth:building": {},
      "stonehearth:fabricator": {},
      "stonehearth:incapacitation": {
         "sm": {}
      },
      "stonehearth:item_quality": {
      },
      "stonehearth:commands": {},
      "stonehearth:job" : {
         'curr_job_controller' : {}
      },
      "stonehearth:buffs" : {
         "buffs" : {
            "*" : {}
         }
      },
      'stonehearth:expendable_resources' : {},
      "stonehearth:unit_info": {},
      "stonehearth:stacks": {},
      "stonehearth:material": {},
      "stonehearth:workshop": {
         "crafter": {},
         "crafting_progress": {},
         "order": {}
      },
      "stonehearth:pet": {},
      "stonehearth:party": {
         "members": {
            "*": {
               "entity": {
                  "stonehearth:work_order": {
                     "work_order_statuses": {},
                     "work_order_refs": {},
                  }
               }
            }
         }
      },
      "stonehearth:party_member" : {
         "party" : {
            "stonehearth:unit_info" : {}
         }
      },
      "stonehearth:siege_weapon" : {},
      "stonehearth:door": {},
      "stonehearth:iconic_form" : {
         "root_entity" : {
            "uri" : {},
            'stonehearth:item_quality': {},
            'stonehearth:traveler_gift': {},
         }
      },
      "stonehearth:traveler_gift": {},
      "stonehearth:work_order": {
         "work_order_statuses": {},
         "work_order_refs": {},
      },
      "stonehearth_ace:quest_storage": {
         "bulletin": {},
      },
      "stonehearth_ace:titles": {},
      "stonehearth_ace:transform": {
         "progress": {},
      }
   },

   allowedClasses: null,
   JOB_STATUS: {
      DISABLED: 'jobDisabled',
      ENABLED: 'jobEnabled',
      SOME: 'jobSomeEnabled'
   },

   init: function() {
      this._super();
      var self = this;
      radiant.call_obj('stonehearth.selection', 'get_selected_command')
         .done(updateUnitFrame);
   },

   _updateUnitFrameShown: function () {
      var unitFrameElement = this.$('#unitFrame');
      if (!unitFrameElement) {
         return;  // Too early or too late.
      }
      var alias = this.get('model.uri');
      // hide the unit frame for buildings because they look stupid
      if (alias && !this.get('model.stonehearth:building') && !this.get('model.stonehearth:fabricator')) {
         unitFrameElement.removeClass('hidden');
      } else {
         unitFrameElement.addClass('hidden');
      }
   }.observes('model.uri'),

   commandsEnabled: function() {
      return !this.get('model.stonehearth:commands.disabled');
   }.property('model.stonehearth:commands.disabled'),

   showButtons: function() {
      var playerId = App.stonehearthClient.getPlayerId();
      var entityPlayerId = this.get('model.player_id');
      //allow for no player id for things like berry bushes and wild plants that are not owned
      //make sure commands are not disabled
      return this.get('commandsEnabled') && (!entityPlayerId || entityPlayerId == playerId);
   }.property('model.uri'),

   _updateVisibility: function() {
      var self = this;
      var selectedEntity = this.get('uri');
      if (App.getGameMode() == 'normal' && selectedEntity) {
         this.set('visible', true);
      } else {
         this.set('visible', false);
      }
   },

   supressSelection: function(supress) {
      this._supressSelection = supress;
   },

   _updateMoodBuff: function() {
      var self = this;
      var icon = self.get('moodData.current_mood_buff.icon');

      // check if we need to display a different mood icon
      if (icon !== self._moodIcon) {
         self._moodIcon = icon;
         self.set('moodIcon', icon);
      }
   }.observes('moodData', 'model.uri'),

   _updateBuffs: function() {
      var self = this;
      self._buffs = [];
      var attributeMap = self.get('model.stonehearth:buffs.buffs');

      if (attributeMap) {
         radiant.each(attributeMap, function(name, buff) {
            //only push public buffs (buffs who have an is_private unset or false)
            if (typeof buff === 'object' && (buff.invisible_to_player == undefined || !buff.invisible_to_player)) {
               var this_buff = radiant.shallow_copy(buff);
               // only show stacks if greater than 1
               if (this_buff.stacks > 1) {
                  this_buff.hasStacks = true;
               }
               self._buffs.push(this_buff);
            }
         });
      }

      self._buffs.sort(function(a, b){
         var aUri = a.uri;
         var bUri = b.uri;
         return (aUri && bUri) ? aUri.localeCompare(bUri) : -1;
      });

      var positiveBuffs = [];
      var negativeBuffs = [];
      radiant.each(self._buffs, function(_, buff) {
         if (buff.axis == 'debuff') {
            negativeBuffs.push(buff);
         }
         else {
            positiveBuffs.push(buff);
         }
      });

      self.set('positiveBuffs', positiveBuffs);
      self.set('negativeBuffs', negativeBuffs);
      //self.set('buffs', self._buffs);
   }.observes('model.stonehearth:buffs'),

   didInsertElement: function() {
      var self = this;

      this._super();

      self.$("#portrait").tooltipster();

      this.$('#nametag').click(function() {
         if ($(this).hasClass('clickable')) {
            var isPet = self.get('model.stonehearth:pet');
            if (isPet) {
               App.stonehearthClient.showPetCharacterSheet(self.get('uri'));
            }
            else {
               var name = self.get('custom_name');
               self.$('#nameInput').val(name)
                  .width(self.$('#nametag').outerWidth() - 16)  // 16 is the total padding and border of #nameInput
                  .show()
                  .focus()
                  .select();
            }
         }
      })
      .on('contextmenu', function(e) {
         self._showTitleSelectionList();
         return false;
      });

      this.$('#nametag').tooltipster({
         delay: 500,  // Don't trigger unless the player really wants to see it.
         content: ' ',  // Just to force the tooltip to appear. The actual content is created dynamically below, since we might not have the name yet.
         functionBefore: function (instance, proceed) {
            instance.tooltipster('content', self._getNametagTooltipText(self));
            proceed();
         }
      });

      this.$('#portrait').click(function (){
        radiant.call('stonehearth:camera_look_at_entity', self.get('uri'));
      });

      //Setup tooltips for the combat commands
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#defendLocation'),
                                                      'stonehearth:ui.game.unit_frame.defend_location.display_name',
                                                      'stonehearth:ui.game.unit_frame.defend_location.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackLocationOrEntity'),
                                                      'stonehearth:ui.game.unit_frame.attack_target.display_name',
                                                      'stonehearth:ui.game.unit_frame.attack_target.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#moveToLocation'),
                                                      'stonehearth:ui.game.unit_frame.move_unit.display_name',
                                                      'stonehearth:ui.game.unit_frame.move_unit.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#partyButton'),
                                                      'stonehearth:ui.game.unit_frame.manage_party.display_name',
                                                      'stonehearth:ui.game.unit_frame.manage_party.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#cancelCombatButton'),
                                                      'stonehearth:ui.game.unit_frame.cancel_order.display_name',
                                                      'stonehearth:ui.game.unit_frame.cancel_order.description');

      radiant.call('stonehearth_ace:get_game_mode_json')
         .done(function(response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self._game_mode_json = response.game_mode_json;
            if (self._game_mode_json) {
               self._updateHealth();
            }
         });

      self.$('#nameInput')
         .keydown(function(e) {
            if (e.keyCode === 27 && self.$('#nameInput').is(":visible")) {
               self.$('#nameInput').hide();
               return false;
            }
         });

      self._nameHelper = new StonehearthInputHelper(self.$('#nameInput'), function (value) {
         // Ignore name input if player does not own the entity
         if (!radiant.isOwnedByAnotherPlayer(self.get('model'), App.stonehearthClient.getPlayerId())) {
            // get uri based on name_entity
            var name_entity = self.get('name_entity');
            var uri = self.get(name_entity + '.__self');
            radiant.call('stonehearth:set_custom_name', uri, value); // false for skip setting custom name
         }

         self.$('#nameInput').hide();
      });
      self.$('#nameInput').blur(function() {
         self.$('#nameInput').hide();
      });

      self.$('#lockTitle').click(function() {
         // toggle title lock for this entity
         var name_entity = self.get('name_entity');
         var uri = self.get(name_entity + '.__self');
         radiant.call('stonehearth_ace:lock_title', uri, !self.get(name_entity + '.stonehearth:unit_info.title_locked'))
      });

      App.tooltipHelper.createDynamicTooltip(self.$('#lockTitle'), function () {
         var name_entity = self.get('name_entity');
         var locked = self.get(name_entity + '.stonehearth:unit_info.title_locked');
         if (locked == null) {
            return;
         }

         var sLocked = locked ? 'unlock' : 'lock';
         return $(App.tooltipHelper.createTooltip(i18n.t(`stonehearth_ace:ui.game.unit_frame.${sLocked}_title.title`),
               i18n.t(`stonehearth_ace:ui.game.unit_frame.${sLocked}_title.description`)));
      });

      var div = $("#componentInfoButton");
      App.hotkeyManager.makeTooltipWithHotkeys(div,
            i18n.t('stonehearth_ace:ui.game.unit_frame.toggle_component_info.tooltip_title'),
            i18n.t('stonehearth_ace:ui.game.unit_frame.toggle_component_info.tooltip_description'));
      div.on('click', self.toggleComponentInfo);

      div = self.$('#descriptionDiv');
      div.on('click', function() {
         self.showPromotionTree();
      });

      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackAllParties'),
            'stonehearth_ace:ui.game.unit_frame.attack_with_all_parties.display_name',
            'stonehearth_ace:ui.game.unit_frame.attack_with_all_parties.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackParty1'),
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_1.display_name',
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_1.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackParty2'),
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_2.display_name',
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_2.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackParty3'),
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_3.display_name',
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_3.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#attackParty4'),
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_4.display_name',
            'stonehearth_ace:ui.game.unit_frame.attack_with_party_4.description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#cancelAttack'),
            'stonehearth_ace:ui.game.unit_frame.cancel_attack.display_name',
            'stonehearth_ace:ui.game.unit_frame.cancel_attack.description');

      App.tooltipHelper.createDynamicTooltip(self.$('#jobToggleDiv'), function () {
         var status = self.get('jobEnabledStatus');
         if (!status) {
            return;
         }

         var title, tooltip;
         switch (status) {
            case self.JOB_STATUS.DISABLED:
               title = 'toggle_on';
               tooltip = 'toggledOff';
               break;

            case self.JOB_STATUS.ENABLED:
               title = 'toggle_off';
               tooltip = 'toggledOn';
               break;

            case self.JOB_STATUS.SOME:
               title = 'toggle_on';
               tooltip = 'toggledSome';
               break;
         }

         if (title && tooltip) {
            title = i18n.t('stonehearth_ace:ui.game.unit_frame.job_toggle.' + title);
            tooltip = i18n.t('stonehearth_ace:ui.game.unit_frame.job_toggle.' + tooltip);

            return $(App.tooltipHelper.createTooltip(title, tooltip));
         }
      });

      _selectionHasComponentInfoChanged();
      _showJobToggleButtonChanged();

      this._updateUnitFrameShown();
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('.name').off('click');
      this.$('#portrait').off('click');

      if (self._moodTrace) {
         self._moodTrace.destroy();
         self._moodTrace = null;
      }

      this._nameHelper.destroy();
      this._nameHelper = null;
      this.$('#info').off('mouseenter mouseleave');
      if (this._partyObserverTimer) {
         Ember.run.cancel(this._partyObserverTimer);
      }
      this._partyObserverTimer = null;

      this._super();
   },

   commands: function() {
      // Hide commands if this is another player's entity, unless the command is
      // set to be visible to all players
      var playerId = App.stonehearthClient.getPlayerId();
      var entityPlayerId = this.get('model.player_id');
      var filterFn = null;
      var playerIdValid = !entityPlayerId || entityPlayerId == playerId || entityPlayerId == 'critters' || entityPlayerId == 'animals';
      if (!playerIdValid) {
         filterFn = function(key, value) {
            if (!value.visible_to_all_players) {
               return false;
            }
         };
      }
      var commands = radiant.map_to_array(this.get('model.stonehearth:commands.commands'), filterFn);
      commands.sort(function(a, b){
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      });
      return commands;
   }.property('model.stonehearth:commands.commands'),

   showJobToggle: function() {
      return this.get('jobToggleButtonSettingEnabled') && this.get('hasJob');
   }.property('jobToggleButtonSettingEnabled', 'hasJob'),

   showPromotionTree: function() {
      var self = this;
      if (self._canPromoteSelectedEntity()) {
         // do we need to do a click sound here? the promotion tree window makes a "paper" sound when it comes up
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
         App.stonehearthClient.showPromotionTree(self.get('uri'), self.get('model.stonehearth:job.job_index'));
      }
   },

   _canPromoteSelectedEntity: function() {
      var self = this;
      if (self.get('model.stonehearth:job') && self.get('model.player_id') == App.stonehearthClient.getPlayerId()) {
         var jobConst = App.jobConstants[self.get('model.stonehearth:job.job_uri')];
         return jobConst && jobConst.description && !jobConst.description.is_npc_job;
      }
      return false;
   },

   _updatePromotionTooltip: function() {
      var self = this;
      var div = self.$('#descriptionDiv');
      
      // not sure why this happens...?
      if (!div || div.length < 1) {
         return;
      }

      if (div.hasClass('tooltipstered')) {
         div.tooltipster('destroy');
      }
      if (self._canPromoteSelectedEntity()) {
         div.attr('hotkey_action', 'ui:show_promotion_tree');
         App.hotkeyManager.makeTooltipWithHotkeys(div,
            i18n.t('stonehearth_ace:ui.game.unit_frame.show_promotion_tree.tooltip_title'),
            i18n.t('stonehearth_ace:ui.game.unit_frame.show_promotion_tree.tooltip_description'));
      }
   }.observes('model.uri'),

   _updateJobChangeable: function() {
      var self = this;
      self.set('canChangeJob', self._canPromoteSelectedEntity())
   }.observes('model.stonehearth:job'),

   _getNametagTooltipText: function(self) {
      var text = self.get('model.stonehearth:unit_info.current_title.description');
      var title;
      if (text) {
         text = i18n.t(text);
         title = self.$('#nametag').text().trim();
      }
      else {
         text = self.$('#nametag').text().trim();
      }

      return $(App.tooltipHelper.createTooltip(title || "", text, ""));
   },

   _showTitleSelectionList: function() {
      var self = this;
      var name_entity = self.get('name_entity');

      // make sure they don't have title locked
      if (self.get(name_entity + '.stonehearth:unit_info.title_locked')) {
         return;
      }

      var result = stonehearth_ace.createTitleSelectionList(self._titles, self.get(name_entity + '.stonehearth_ace:titles.titles'), self.get('uri'), self.get('custom_name'));
      if (result) {
         result.container.css({
            height: result.titlesArr.length * 37
         })
         self.$('#topBar').append(result.container);
         result.showList();
      }
   },

   _updateChangeableName: function() {
      var self = this;
      var playerCheck = self.get('model.player_id') == App.stonehearthClient.getPlayerId();
      var name_entity = self.get('name_entity');
      var unit_info = self.get(name_entity + '.stonehearth:unit_info');
      
      var canChangeName = playerCheck && unit_info && unit_info.custom_name && !unit_info.locked;
      self.set('canChangeName', canChangeName);
      self.notifyPropertyChange('canChangeName');

      var titleLockClass = null;
      // first check if titles are even an option for this entity
      if (playerCheck && unit_info && self.get(name_entity + '.stonehearth_ace:titles')) {
         titleLockClass = unit_info.title_locked ? 'locked' : 'unlocked';
      }
      self.set('titleLockClass', titleLockClass);
      self.notifyPropertyChange('titleLockClass');

      self.$('#nameInput').hide();
   }.observes('name_entity'),

   nameTagClass: function() {
      var canChangeName = this.get('canChangeName') ? 'clickable' : 'noHover';
      var isHostile = this.get('isHostile') ? ' hostile' : '';
      return canChangeName + isHostile;
   }.property('canChangeName', 'isHostile'),

   toggleComponentInfo: function() {
      $(top).trigger('component_info_toggled', {});
   },

   // ACE: make sure uri matches when updating ui elements
   _modelUpdated: function() {
      var self = this;
      var uri = self.get('uri');
      self.set('moodData', null);
      if (uri && self._uri != uri) {
         self._uri = uri;
         radiant.call('stonehearth:get_mood_datastore', uri)
            .done(function (response) {
               if (self.isDestroying || self.isDestroyed || self._uri != uri) {
                  return;
               }
               if (self._moodTrace) {
                  self._moodTrace.destroy();
               }
               self._moodTrace = new RadiantTrace(response.mood_datastore, { current_mood_buff: {} })
                  .progress(function (data) {
                     if (self.isDestroying || self.isDestroyed || self._uri != uri) {
                        return;
                     }
                     self.set('moodData', data);
                  })
            });
      }
   }.observes('model.uri'),

   // ACE: get rid of the activity part and collapse/expand based on total commands
   _updateUnitFrameWidth: function(considerCommands) {
      var self = this;

      //the following is some rough dynamic sizing to prevent descriptions and command buttons from overlapping
      //it has to happen after render to check the elements for the unit frame for the newly selected item, not the previous
      Ember.run.scheduleOnce('afterRender', this, function() {
         var unitFrame = this.$('#unitFrame');
         if (unitFrame) {
            var maxWidth = 560;
            var infoDiv = this.$('#info');
            var commandButtons = this.$('#commandButtons');
            var moreCommandsIndicator = this.$('#moreCommandsIndicator');

            var width = Math.max(this.$('#descriptionDiv').width() + commandButtons.width() + 19); // + 19 to account for margins
            if (this.get('hasPortrait')) {
               width += this.$('#portrait-frame').width();
            }

            if (considerCommands == true && self._bestWidth == null) {
               self._bestWidth = Math.max(maxWidth, width);
               self._commandWidth = commandButtons.width();
               self._commandsPos = maxWidth - 3 - self._commandWidth;

               var diff = self._bestWidth - maxWidth;
               if (diff > 0) {
                  self._bestWidth += 12;
                  self._commandsPos += diff;
                  // if it's wider than we want, we need to trim the command buttons to fit
                  infoDiv.hover(function(e) {
                     unitFrame.css('width', self._bestWidth + 'px');
                     commandButtons.css('width', self._commandWidth + 'px');
                     moreCommandsIndicator.hide();
                  },
                  function(e) {
                     unitFrame.css('width', maxWidth + 'px');
                     commandButtons.css('width', (self._commandWidth - diff) + 'px');
                     moreCommandsIndicator.show();
                  });

                  commandButtons.css('width', (self._commandWidth - diff) + 'px');
                  moreCommandsIndicator.show();
               }
               else {
                  moreCommandsIndicator.hide();
                  if (width < self._bestWidth) {
                     self._commandsPos += Math.max(-12, width - self._bestWidth);
                  }
               }
               commandButtons.css('left', (self._commandsPos + 12) + 'px');
            }

            unitFrame.css('width', maxWidth + 'px'); //don't want it getting too bitty
         }
      });
   }.observes('model.uri', 'model.stonehearth:unit_info', 'job_uri'),

   _resetCommandsWidthCheck: function() {
      this.$('#info').off('mouseenter mouseleave');
      this.$('#commandButtons').css('width', '');
      delete this._bestWidth;
      delete this._commandsPos;
   }.observes('model.uri'),

   _updateCommandsWidth: function() {
      this._resetCommandsWidthCheck();
      this._updateUnitFrameWidth(true);
   }.observes('groupedCommands'),

   // ACE: group commands to conserve space when an entity has more than two commands
   _updateCommandGroups: function() {
      // Hide commands if this is another player's entity, unless the command is
      // set to be visible to all players
      var self = this;
      var playerId = App.stonehearthClient.getPlayerId();
      var entityPlayerId = self.get('model.player_id');
      var filterFn = null;
      var playerIdValid = !entityPlayerId || entityPlayerId == playerId || entityPlayerId == 'critters' || entityPlayerId == 'animals';
      if (!playerIdValid) {
         filterFn = function(key, value) {
            if (!value.visible_to_all_players) {
               return false;
            }
         };
      }
      var commands = radiant.map_to_array(self.get('model.stonehearth:commands.commands'), filterFn);
      var totalCommands = commands.length;
      var groups = {};
      commands.forEach(command => {
         var group = command.group;
         if (group) {
            if (!groups[group]) {
               groups[group] = [];
            }
            groups[group].push(command);
         }
      });

      var sortFn = function(a, b){
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      };
      
      var groupedCommands = [];
      radiant.each(groups, function(group, groupCommands) {
         if (groupCommands.length > 1 && totalCommands > 2) {
            // if there's more than one command in the group, and there's at least one other command (or more than two commands in the group), add the group instead
            var groupData = stonehearth_ace.getCommandGroup(group);
            if (groupData) {
               var groupData = radiant.shallow_copy(groupData);
               groupData.groupName = group;
               groupData.commands = groupCommands;

               groupCommands.forEach(command => {
                  var index = $.inArray(command, commands);
                  if (index >= 0) {
                     commands.splice(index, 1);
                  }
               });

               groupCommands.sort(sortFn);
               groupedCommands.push(groupData);
            }
         }
      });
      //$.merge(groupedCommands, commands);
      // now make a grouping container for each individual command
      commands.forEach(command => {
         var groupContainer = {
            ordinal: command.ordinal,
            commands: [command]
         }
         groupedCommands.push(groupContainer);
      });

      groupedCommands.sort(sortFn);
      
      self.set('groupedCommands', groupedCommands);
   }.observes('model.stonehearth:commands.commands'),

   _updateMaterial: function() {
      var self = this;
      var hasCharacterSheet = false;
      var alias = this.get('model.uri');
      if (alias) {
         var catalogData = App.catalog.getCatalogData(alias);
         if (catalogData) {
            var materials = null;
            if (catalogData.materials){
               if ((typeof catalogData.materials) === 'string') {
                  materials = catalogData.materials.split(' ');
               } else {
                  materials = catalogData.materials;
               }
            } else {
               materials = [];
            }
            if (materials.indexOf('human') >= 0) {
               hasCharacterSheet = true;
               self._moodIcon = null;
            }

            self.set('itemIcon', catalogData.icon);
         }
      }

      var self = this;
      var isPet = false;
      var petComponent = self.get('model.stonehearth:pet');
      if (petComponent) {
         hasCharacterSheet = true;
         isPet = true;
         self._moodIcon = null;
         self._updatePortrait();
         self.set('itemIcon', null);
      }

      self.set('isPet', isPet);
      self.set('hasCharacterSheet', hasCharacterSheet);
   }.observes('model.stonehearth:pet', 'model.stonehearth:unit_info'),

   _hasPortrait: function() {
      if (this.get('model.stonehearth:job')) {
         return true;
      }
      //Parties have icons too
      if (this.get('model.stonehearth:party')) {
         return true;
      }
      var isPet = this.get('model.stonehearth:pet');

      if (isPet && isPet.is_pet) {
         return true;
      }
      return false;
   },

   _updatePortrait: function() {
      if (!this.$()) {
         return;
      }
      var uri = this.uri;

      if (uri && this._hasPortrait()) {
         var portrait_url = '';
         if (this.get('model.stonehearth:party')) {
            portrait_url = this.get('model.stonehearth:unit_info.icon');
         } else {
            portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
         }
         //this.set('portraitSrc', portrait_url);
         this.set('hasPortrait', true);
         this.$('#portrait-frame').removeClass('hidden');
         this.$('#portrait').css('background-image', 'url(' + portrait_url + ')');
      } else {
         this.set('hasPortrait', false);
         this.set('portraitSrc', "");
         this.$('#portrait').css('background-image', '');
         this.$('#portrait-frame').addClass('hidden');
      }

      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:unit_info', 'job_uri'),   // ACE: prevent it from refreshing every time they get exp

   _jobUriChanged: function() {
      var job_uri = this.get('model.stonehearth:job.job_uri');
      if (job_uri != this.get('job_uri')) {
         this.set('job_uri', job_uri);
      }
   }.observes('model.stonehearth:job.job_uri'),

   _updateDisplayNameAndDescription: function() {
      var self = this;
      var alias = self.get('model.uri');
      self.set('entityWithNonworkerJob', false);

      var description = self.get('model.stonehearth:unit_info.description');
      if (self.get('model.stonehearth:job') && !self.get('model.stonehearth:job.curr_job_controller.no_levels') && self.get('model.stonehearth:job.curr_job_name') !== '') {
         self.set('entityWithNonworkerJob', true);
         self.$('#Lvl').text( i18n.t('stonehearth:ui.game.unit_frame.Lvl'));
      }

      // prefer the unit info for this entity, unless custom_name or custom_data is specified for root entity
      var unit_info_property = 'model.stonehearth:unit_info';
      var root_unit_info_property = 'model.stonehearth:iconic_form.root_entity.stonehearth:unit_info';
      var unit_info = self.get(unit_info_property);
      var root_unit_info = self.get(root_unit_info_property);
      var name_entity = 'model';
      if (root_unit_info && (root_unit_info.custom_name || root_unit_info.custom_data)) {
         unit_info = root_unit_info;
         unit_info_property = root_unit_info_property;
         name_entity = 'model.stonehearth:iconic_form.root_entity';
      }

      var display_name = unit_info && unit_info.display_name;
      var custom_name = unit_info && unit_info.custom_name;
      if (alias) {
         var catalogData = App.catalog.getCatalogData(alias);
         if (!catalogData) {
            console.log("no catalog data found for " + alias);
         } else {
            if (custom_name && custom_name.substring(0, 5) == 'i18n(') {
               custom_name = i18n.t(catalogData.display_name);
               self.set(unit_info_property + '.custom_name', custom_name);
            }

            if (!display_name) {
               display_name = catalogData.display_name;
            }

            if (!description) {
               description = catalogData.description;
            }
         }
      }

      self.set('name_entity', name_entity);
      self.notifyPropertyChange('name_entity');
      self.set('custom_name', custom_name);
      self.set('display_name', display_name);
      self.notifyPropertyChange('display_name');
      self.set('description', description);
      self.notifyPropertyChange('description');
   }.observes('model.uri', 'model.stonehearth:unit_info', 'model.stonehearth:iconic_form.root_entity.stonehearth:unit_info'),

   _loadAvailableTitles: function() {
      // when the selection changes, load up the appropriate titles json
      var self = this;
      self._titles = {};
      var name_entity = self.get('name_entity');
      var json = self.get(name_entity + '.stonehearth_ace:titles.titles_json');
      if (json) {
         stonehearth_ace.loadAvailableTitles(json, function(data){
            self._titles = data;
         });
      }
   }.observes('name_entity'),

   _updateJobDescription: function() {
      // Force the unit info description to update again after curr job name changes.
      // This used to work (or I never noticed.) but now the timing is such that the description change comes in before the job name. -yshan 1/19/2016
      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:job.curr_job_name'),

   _updateItemStacks: function() {
      // Force the unit info description to update again after item stacks changes.
      this._updateDisplayNameAndDescription();
   }.observes('model.stonehearth:stacks'),

   // override the base to just hide the combatButtonDiv instead of all the combatControls
   _updateCombatTools: function() {
      var isCombatClass = this.get('model.stonehearth:job.curr_job_controller.is_combat_class');
      var playerId = this.get('model.player_id');
      var currPlayerId = App.stonehearthClient.getPlayerId();
      var isPlayerOwner = playerId == currPlayerId;
      var combatControlsElement = this.$('#combatButtonDiv');
      if (combatControlsElement) {
         if (isPlayerOwner && (isCombatClass || this.get('model.stonehearth:party'))) {
            combatControlsElement.show();
         } else {
            combatControlsElement.hide();
         }
      }
   }.observes('model.stonehearth:job.curr_job_controller', 'model.stonehearth:party'),

   // override this to only call these functions if the combat command buttons are visible (e.g., player could be using hotkey)
   _callCombatCommand: function(command) {
      if (this.$('#combatButtonDiv').is(':visible')) {
         App.stonehearthClient.giveCombatCommand(command, this.get('uri'));
      }
   },

   _updateEquipment: function () {
      var self = this;
      if (!self.$('#equipmentPane')) return;
      self.$('#equipmentPane').find('.tooltipstered').tooltipster('destroy');

      if (self.get('model.stonehearth:iconic_form') && self.get('model.stonehearth:iconic_form').root_entity) {
         var playerId = self.get('model.player_id');
         var currPlayerId = App.stonehearthClient.getPlayerId();
         var isPlayerOwner = playerId == currPlayerId;
         var equipmentPiece = self.get('model.stonehearth:iconic_form').root_entity.uri.components['stonehearth:equipment_piece'];
         if(equipmentPiece && isPlayerOwner && (equipmentPiece.required_job_level || equipmentPiece.roles)) {
            if (equipmentPiece.roles) {
               //this._collectClasses(equipmentPiece.roles);
               var classArray = stonehearth_ace.findRelevantClassesArray(equipmentPiece.roles);
               self.set('allowedClasses', classArray);
            }
            if (equipmentPiece.required_job_level) {
               self.$('#levelRequirement').text( i18n.t('stonehearth:ui.game.unit_frame.level')  + equipmentPiece.required_job_level);
            } else {
               self.$('#levelRequirement').text('');
            }

            var catalogData = App.catalog.getCatalogData(self.get('model.stonehearth:iconic_form').root_entity.uri.__self);
            var equipmentTypes = [];
            if (catalogData && catalogData.equipment_types) {
               equipmentTypes = stonehearth_ace.getEquipmentTypesArray(catalogData.equipment_types);
            }
            self.set('equipmentTypes', equipmentTypes);

            //Make tooltips
            App.tooltipHelper.createDynamicTooltip(self.$('#equipmentPane'), function () {
               var tooltipString = i18n.t('stonehearth:ui.game.unit_frame.no_requirements');
               if (equipmentPiece.roles) {
                  tooltipString = i18n.t('stonehearth:ui.game.unit_frame.equipment_description',
                                         { class_list: radiant.getClassString(self.get('allowedClasses')) });
               }
               if (equipmentPiece.required_job_level) {
                  tooltipString += i18n.t('stonehearth:ui.game.unit_frame.level_description', { level_req: equipmentPiece.required_job_level });
               }
               if (catalogData && catalogData.equipment_types) {
                  tooltipString += '<br>' + i18n.t('stonehearth_ace:ui.game.unit_frame.equipment_types_description',
                                                   { i18n_data: { types: stonehearth_ace.getEquipmentTypesString(self.get('equipmentTypes')) } });
               }
               return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth:ui.game.unit_frame.class_lv_title'), tooltipString));
            });

            self.$('#equipmentPane').show();
         } else {
            self.$('#equipmentPane').hide();
         }
      } else {
         self.$('#equipmentPane').hide();
      }
   }.observes('model.stonehearth:iconic_form.root_entity.uri'),

   _updateSiege: function() {
      var self = this;
      self.set('siegeNumUses', self.get('model.stonehearth:siege_weapon.num_uses'));
      self.set('siegeMaxUses', self.get('model.stonehearth:siege_weapon.max_uses'));
   }.observes('model.stonehearth:siege_weapon.num_uses'),

   _updateItemLimit: function() {
      var self = this;
      var uri = self._getRootUri();
      var setItemLimitInfo = function(info) {
         var itemName = info && ("i18n(stonehearth:ui.game.unit_frame.placement_tags." + info.placement_tag + ")");
         self.set('placementTag', itemName);
         self.set('numPlaced', info && info.num_placed);
         self.set('maxPlaceable', info && info.max_placeable);
      };
      if (uri) {
         radiant.call('stonehearth:check_can_place_item', uri, self._getItemQuality())
            .done(function(response) {
               setItemLimitInfo(response);
            })
            .fail(function(response) {
               setItemLimitInfo(response);
            });
      } else {
         setItemLimitInfo(null);
      }
   }.observes('model.stonehearth:siege_weapon', 'mode.stonehearth:iconic_form.root_entity.components.stonehearth:siege_weapon'),

   _updateDoorLock: function() {
      var self = this;
      var isLocked = self.get('model.stonehearth:door.locked');
      var str = isLocked ? 'locked' : 'unlocked';
      self.set('hasLock', isLocked != null);
      self.set('doorLockIcon', '/stonehearth/ui/game/unit_frame/images/door_' + str + '.png');
      self.set('doorLockedText', str);
   }.observes('model.stonehearth:door.locked'),

   _updatePartyBanner: function() {
      var image_uri = this.get('model.stonehearth:party_member.party.stonehearth:unit_info.icon');
      if (this.$('#partyButton')) {
         if (image_uri) {
            this.$('#partyButton').css('background-image', 'url(' + image_uri + ')');
            this.$('#partyButton').show();
         } else {
            //TODO: is this the best way to figure out if we don't have a party?
            this.$('#partyButton').hide();
         }
      }
   }.observes('model.stonehearth:party_member.party.stonehearth:unit_info'),

   _updateHealth: function() {
      var self = this;
      var currentHealth = self.get('model.stonehearth:expendable_resources.resources.health');
      if (currentHealth == null) {
         return;
      }

      self.set('currentHealth', Math.floor(currentHealth));

      var maxHealth = self.get('model.stonehearth:attributes.attributes.max_health.user_visible_value');
      var maxHealableHealth;

      if (self._game_mode_json) {
         // if we have a game mode, consider the max_percent_health_redux and the effective_max_health_percent attribute
         var maxRedux = self._game_mode_json.max_percent_health_redux || 0;
         var effMaxHealthPercent = self.get('model.stonehearth:attributes.attributes.effective_max_health_percent.user_visible_value') || 100;
         var modifier = Math.max(effMaxHealthPercent, 100 - maxRedux) * 0.01;
         maxHealableHealth = Math.ceil(maxHealth * modifier);
      }
      maxHealth = Math.ceil(maxHealth);
      var hasDiffMaxHealth = maxHealableHealth && maxHealableHealth != maxHealth;
      
      self.set('maxHealth', maxHealth);
      self.set('maxHealableHealth', hasDiffMaxHealth ? maxHealableHealth : null);

      if (self.$('#healthBubble').hasClass('tooltipstered')) {
         self.$('#healthBubble').tooltipster('destroy');
      }
      if (hasDiffMaxHealth) {
         Ember.run.scheduleOnce('afterRender', self, function() {
            var healthBubble = self.$('#healthBubble');
            if (healthBubble) {
               var tooltipString = i18n.t('stonehearth_ace:ui.game.unit_frame.max_healable_health.tooltip_description', {max_health: maxHealableHealth});
               var maxHealthTooltip = App.tooltipHelper.createTooltip(
                  i18n.t('stonehearth_ace:ui.game.unit_frame.max_healable_health.tooltip_title'),
                  tooltipString);
               healthBubble.tooltipster({
                  content: $(maxHealthTooltip)
               });
            }
         });
      }
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes.max_health'),

   _updateRescue: function() {
      var self = this;

      var curState = self.get('model.stonehearth:incapacitation.sm.current_state');

      self.set('needsRescue', Boolean(curState) && (curState == 'awaiting_rescue' || curState == 'rescuing'));
   }.observes('model.stonehearth:incapacitation.sm'),

   _updateCraftingProgress: function() {
      var self = this;
      var progress = self.get('model.stonehearth:workshop.crafting_progress');
      if (progress) {
         var doneSoFar = progress.game_seconds_done;
         var total = progress.game_seconds_total;
         var percentage = Math.round((doneSoFar * 100) / total);
         self.set('progress', percentage);
         Ember.run.scheduleOnce('afterRender', self, function() {
            self.$('#progress').css("width", percentage / 100 * this.$('#progressbar').width());
         });
      }
   }.observes('model.stonehearth:workshop.crafting_progress'),

   _clearItemQualityIndicator: function() {
      var self = this;
      if (self.$('#qualityGem')) {
         if (self.$('#qualityGem').hasClass('tooltipstered')) {
            self.$('#qualityGem').tooltipster('destroy');
         }
         self.$('#qualityGem').removeClass();
      }
      if (self.$('#nametag')) {
         self.$('#nametag').removeClass();
      }
      self.set('qualityItemCreationDescription', null);
   },

   _applyQuality: function() {
      var self = this;

      self._clearItemQualityIndicator();

      var itemQuality = self._getItemQuality();
      
      if (itemQuality > 1) {
         var qualityLvl = 'quality-' + itemQuality;

         var craftedKey = 'stonehearth:ui.game.unit_frame.crafted_by';
         if (self.get('model.stonehearth:item_quality.author_type') == 'place') {
            craftedKey = 'stonehearth:ui.game.unit_frame.crafted_in';
         }

         var authorName = self._getItemAuthor();
         if (authorName) {
            self.set('qualityItemCreationDescription', i18n.t(
               craftedKey,
               { author_name: authorName }));
         }
         self.$('#qualityGem').addClass(qualityLvl + '-icon');
         self.$('#nametag').addClass(qualityLvl);

         var qualityTooltip = App.tooltipHelper.createTooltip(i18n.t('stonehearth:ui.game.unit_frame.quality.' + qualityLvl));
         self.$('#qualityGem').tooltipster({
            content: self.$(qualityTooltip)
         });
      }
   }.observes('model.stonehearth:item_quality'),

   _applyGifter: function() {
      var self = this;

      self.set('gifterDescription', null)
      var gifterName = self._getGifterName()
      if (gifterName) {
         self.set('gifterDescription', i18n.t(
            'stonehearth:ui.game.unit_frame.traveler.gifted_by',
            { gifter_name: gifterName }));
      }
   }.observes('model.stonehearth:traveler_gift'),

   _updateAppeal: function() {
      var self = this;

      // First, get a client-side approximation so we avoid flicker in most cases.
      var uri = self.get('model.uri');
      var catalogData = App.catalog.getCatalogData(uri);
      if (catalogData && catalogData.appeal) {
         var appeal = catalogData.appeal;
         var itemQuality = self._getItemQuality();
         if (itemQuality) {
            appeal = radiant.applyItemQualityBonus('appeal', appeal, itemQuality);
         }
         self.set('appeal', appeal);
      } else {
         self.set('appeal', null);
      }

      // Then, for server objects, ask the server to give us the truth, the full truth, and nothing but the truth.
      // This matters e.g. for plants that are affected by the Vitality town bonus.
      var address = self.get('model.__self');
      if (address && !address.startsWith('object://tmp/')) {
         radiant.call('stonehearth:get_appeal_command', address)
            .done(function (response) {
               self.set('appeal', response.result);
            });
      }
   }.observes('model.uri'),

   _updateEnergy: function() {
      var self = this;
      var currentEnergy = self.get('model.stonehearth:expendable_resources.resources.energy');
      self.set('currentEnergy', Math.floor(currentEnergy));

      var maxEnergy = self.get('model.stonehearth:attributes.attributes.max_energy.user_visible_value');
      self.set('maxEnergy', Math.ceil(maxEnergy));
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes.max_energy'),

   _updateTransformProgress: function() {
      var self = this;
      var progress = self.get('model.stonehearth_ace:transform.progress');
      if (progress) {
         var doneSoFar = progress.progress;
         var total = progress.max_progress;
         var percentage = Math.round((doneSoFar * 100) / total);
         self.set('transformProgress', percentage);
         Ember.run.scheduleOnce('afterRender', self, function() {
            var transformProgress = self.$('#transformProgress')
            if (transformProgress) {
               transformProgress.css("width", percentage / 100 * this.$('#transformProgressbar').width());
            }
         });
      }
      else {
         self.set('transformProgress', null);
      }
   }.observes('model.stonehearth_ace:transform.progress'),

   _updateTransformProgressText: function() {
      var self = this;
      self.set('transformProgressText', self.get('model.stonehearth_ace:transform.progress_text') || 'stonehearth_ace:ui.game.unit_frame.transform.progress.transforming');
   }.observes('model.stonehearth_ace:transform'),

   _hostilityObserver: function () {
      var self = this;
      var playerID = self.get('model.player_id');
      var thisPlayerID = App.stonehearthClient.getPlayerId();
      if (playerID && playerID != thisPlayerID) {
         radiant.call('stonehearth_ace:are_player_ids_hostile', playerID, thisPlayerID)
               .done(function (e) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self.set('isHostile', e.are_hostile);
                  self.set('canAttack', e.are_hostile && self.get('model.stonehearth:expendable_resources.resources.health'));
               });
      }
      else {
         self.set('isHostile', false);
         self.set('canAttack', false);
      }
   }.observes('model.player_id'),

   _issueAttackCommand: function (party_id) {
      var self = this;
      radiant.call_obj('stonehearth.unit_control', 'get_party_by_population_name', party_id)
         .done(function (response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            if (response.result) {
               radiant.call_obj('stonehearth.combat_server_commands', 'party_attack_target_entity', response.result, self.get('uri'));
            }
         });
   },

   _updateJobToggleButton: function () {
      var self = this;
      var jobOn = false;
      var jobOff = false;

      var members = self._getCitizenMembers();
      radiant.each(members, function (i, member) {
         var isEnabled = self._isJobEnabled(member);
         if (isEnabled != null) {
            if (isEnabled) {
               jobOn = true;
            }
            else {
               jobOff = true;
            }
         }
      });

      if (!jobOn && !jobOff) {
         self.set('hasJob', false);
      }
      else {
         self.set('hasJob', true);

         if (!jobOn) {
            // only job off
            self.set('jobEnabledStatus', self.JOB_STATUS.DISABLED);
         }
         else if (!jobOff) {
            // only job on
            self.set('jobEnabledStatus', self.JOB_STATUS.ENABLED);
         }
         else {
            // both job on and off
            self.set('jobEnabledStatus', self.JOB_STATUS.SOME);
         }
      }
   },

   _getCitizenMembers: function(){
      var self = this;
      var members = [];

      if (App.stonehearthClient.getPlayerId() != self.get('model.player_id')) {
         return members;
      }

      // if it's a party, we'll need to process through each party member
      var party = self.get('model.stonehearth:party');
      if (party) {
         radiant.each(self.get('model.stonehearth:party.members'), function (k, v) {
            members.push({
               "id": radiant.getEntityId(v.entity),
               "stonehearth:work_order": v.entity["stonehearth:work_order"]
            });
         });
      }
      else {
         members.push({
            "id": radiant.getEntityId(self.get('model')),
            "stonehearth:work_order": self.get("model.stonehearth:work_order")
         });
      }

      return members;
   },

   _isJobEnabled: function (entity) {
      var wo = entity["stonehearth:work_order"];
      if (wo) {
         var workOrders = wo.work_order_statuses;
         var workOrderRefs = wo.work_order_refs;
         if (!workOrders || !workOrderRefs) {
            return null;
         }
         return workOrderRefs['job'] && workOrders['job'] != 'disabled';
      }
      return null;
   },

   _partyObserver: function(){
      var self = this;
      Ember.run.once(self, '_partyTimerCheck');
   }.observes('model.stonehearth:party', 'model.stonehearth:party.members'),

   _partyTimerCheck: function(){
      var self = this;
      var party = self.get('model.stonehearth:party');
      if (party && party.members) {
         // we have a party; if we don't have a party cache, create it
         // since we're just now getting the party cache, we just selected a party, so we're already updating
         // through the normal observer; otherwise, compare to existing cache and if different, update

         let newCache = {};
         radiant.each(party.members, function (i, member) {
            newCache[i] = self._isJobEnabled(member.entity);
         });

         if (self._partyMembersJobEnabledCache) {
            // check if the new cache is different from the old cache
            let diff = false;
            if (self._partyMembersJobEnabledCache.length != newCache.length) {
                  diff = true;
            }
            else {
               radiant.each(newCache, function (i, member) {
                  if (self._partyMembersJobEnabledCache[i] !== member) {
                     diff = true;
                  }
               });
            }

            if (diff) {
               self._partyMembersJobEnabledCache = newCache;
               self._updateJobToggleButton();
            }
         }
         else {
            self._partyMembersJobEnabledCache = newCache;
         }

         // check again in 100ms to see if the party members job status has changed
         self._partyObserverTimer = Ember.run.later(self, '_partyObserver', 100);
      }
      else {
         if (self._partyObserverTimer) {
            Ember.run.cancel(self._partyObserverTimer);
         }
         self._partyObserverTimer = null;
         self._partyMembersJobEnabledCache = null;
      }
   },

   _updateObserver: function(){
      var self = this;
      Ember.run.once(self, '_updateJobToggleButton');
   }.observes('model.stonehearth:work_order', 'model.stonehearth:party.members'),

   _getRootUri: function() {
      var iconic = this.get('model.stonehearth:iconic_form.root_entity.uri.__self');
      return iconic || this.get('model.uri');
   },

   _getItemQuality: function() {
      return this.get('model.stonehearth:item_quality.quality') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:item_quality.quality');
   },

   _getItemAuthor: function() {
      return this.get('model.stonehearth:item_quality.author_name') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:item_quality.author_name');
   },

   _getGifterName: function() {
      return this.get('model.stonehearth:traveler_gift.gifter_name') || this.get('model.stonehearth:iconic_form.root_entity.stonehearth:traveler_gift.gifter_name');
   },

   actions: {
      selectParty: function() {
         radiant.call_obj('stonehearth.party_editor', 'select_party_for_entity_command', this.get('uri'))
            .fail(function(response){
               console.error(response);
            });
      },
      moveToLocation: function() {
         this._callCombatCommand('place_move_target_command');
      },
      attackTarget: function() {
         this._callCombatCommand('place_attack_target_command');
      },
      defendLocation: function() {
         this._callCombatCommand('place_hold_location_command');
      },
      cancelOrders: function() {
         radiant.call_obj('stonehearth.combat_commands', 'cancel_order_on_entity', this.get('uri'))
            .done(function(response){
               //TODO: pick a better sound?
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
            });
      },
      toggleRescueTarget: function() {
         radiant.call_obj('stonehearth.population', 'toggle_rescue_command', this.get('uri'));
      },
      attackWithAllParties: function() {
         for (var i = 1; i <= 4; i++) {
            this._issueAttackCommand("party_" + i);
         }
      },
      attackWithParty: function(party) {
         this._issueAttackCommand(party);
      },
      cancelAttack: function() {
         radiant.call('stonehearth_ace:cancel_combat_order_on_target', this.get('uri'));
      },
      toggleJob: function () {
         var self = this;
 
         if (self.get('model.player_id') == App.stonehearthClient.getPlayerId()) {
            var members = self._getCitizenMembers();
            var popUri = App.population.getUri();

            var enable = self.get('jobEnabledStatus') != self.JOB_STATUS.ENABLED;

            radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:action_click' });
            radiant.each(members, function (i, member) {
               radiant.call_obj(popUri, 'change_work_order_command', 'job', member.id, enable);
            });
         }
      },
   }
});

App.StonehearthCommandButtonView = App.View.extend({
   classNames: ['inlineBlock'],

   didInsertElement: function () {
      var hkaction = this.content.hotkey_action;
      this.$('div').attr('hotkey_action', hkaction);
      this._super();
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('div'), this.content.display_name, this.content.description);
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
   },

   actions: {
      doCommand: function(command) {
         App.stonehearthClient.doCommand(this.get("parentView.uri"), this.get("parentView.model.player_id"), command, this.get("parentView.model"));
      }
   }
});
