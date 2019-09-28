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
   radiant.call('radiant:get_config', 'mods.stonehearth_ace.show_job_toggle_button')
   .done(function(o) {
      var show_job_toggle_button = o['mods.stonehearth_ace.show_job_toggle_button'] != false;
      var e = {
         value: show_job_toggle_button
      };
      $(top).trigger('show_job_toggle_button_changed', e);
   });
});

App.StonehearthUnitFrameView.reopen({
   ace_components: {
      "stonehearth:party": {
          "members": {
              "*": {
                  "entity": {
                      "stonehearth:work_order": {
                          "work_order_statuses": {},
                          "work_order_refs": {}
                      }
                  }
              }
          }
      },
      "stonehearth:work_order": {
          "work_order_statuses": {},
          "work_order_refs": {}
      },
      "stonehearth_ace:titles": {},
      "stonehearth_ace:transform": {
         "progress": {}
      }
   },

   JOB_STATUS: {
      DISABLED: 'jobDisabled',
      ENABLED: 'jobEnabled',
      SOME: 'jobSomeEnabled'
   },

   init: function() {
      var self = this;
      stonehearth_ace.mergeInto(self.components, self.ace_components)

      self._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      // get rid of the default behavior, use ours (more expanded) instead
      self.$('#nametag')
         .off('click')
         .click(function() {
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

      $('#nametag.tooltipstered').tooltipster('destroy');
      self.$('#nametag').tooltipster({
            delay: 500,  // Don't trigger unless the player really wants to see it.
            content: ' ',  // Just to force the tooltip to appear. The actual content is created dynamically below, since we might not have the name yet.
            functionBefore: function (instance, proceed) {
               instance.tooltipster('content', self._getNametagTooltipText(self));
               proceed();
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
      })

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
   },

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

   willDestroyElement: function() {
      this._nameHelper.destroy();
      this._nameHelper = null;
      this.$('#info').off('mouseenter mouseleave');
      if (this._partyObserverTimer) {
         Ember.run.cancel(this._partyObserverTimer);
      }
      this._partyObserverTimer = null;
      this._super();
   },

   _showTitleSelectionList: function() {
      var self = this;

      var name_entity = self.get('name_entity');
      var result = stonehearth_ace.createTitleSelectionList(self._titles, self.get(name_entity + '.stonehearth_ace:titles.titles'), self.get('uri'), self.get('custom_name'));
      if (result) {
         result.container.css({
            height: result.titlesArr.length * 37
         })
         self.$('#topBar').append(result.container);
         result.showList();
      }
   },

   // overriding this to get rid of the activity part
   _updateUnitFrameWidth: function(considerCommands) {
      var self = this;

      //the following is some rough dynamic sizing to prevent descriptions and command buttons from overlapping
      //it has to happen after render to check the elements for the unit frame for the newly selected item, not the previous
      Ember.run.scheduleOnce('afterRender', this, function() {
         var unitFrame = this.$('#unitFrame');
         var infoDiv = this.$('#info');
         var commandButtons = this.$('#commandButtons');
         var moreCommandsIndicator = this.$('#moreCommandsIndicator');

         var width = Math.max(this.$('#descriptionDiv').width() + commandButtons.width() + 19); // + 19 to account for margins
         if (this.get('hasPortrait')) {
            width += this.$('#portrait-frame').width();
         }

         if (considerCommands == true && self._bestWidth == null) {
            self._bestWidth = Math.max(520, width);
            self._commandWidth = commandButtons.width();
            self._commandsPos = 517 - self._commandWidth;

            var diff = self._bestWidth - 520;
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
                  unitFrame.css('width', 520 + 'px');
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

         unitFrame.css('width', 520 + 'px'); //don't want it getting too bitty
      });
   }.observes('model.uri', 'model.stonehearth:unit_info', 'model.stonehearth:job'),

   _resetCommandsWidthCheck: function() {
      this.$('#unitFrame').off('mouseenter mouseleave');
      this.$('#commandButtons').css('width', '');
      delete this._bestWidth;
      delete self._commandsPos;
   }.observes('model.uri'),

   _updateCommandsWidth: function() {
      this._updateUnitFrameWidth(true);
   }.observes('model.stonehearth:commands.commands'),

	_updateEnergy: function() {
      var self = this;
      var currentEnergy = self.get('model.stonehearth:expendable_resources.resources.energy');
      self.set('currentEnergy', Math.floor(currentEnergy));

      var maxEnergy = self.get('model.stonehearth:attributes.attributes.max_energy.user_visible_value');
      self.set('maxEnergy', Math.ceil(maxEnergy));
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes.max_energy'),
	
   _updateChangeableName: function() {
      var self = this;
      var playerCheck = self.get('model.player_id') == App.stonehearthClient.getPlayerId();
      var name_entity = self.get('name_entity');
      var unit_info = self.get(name_entity + '.stonehearth:unit_info');
      
      var canChangeName = playerCheck && unit_info && !unit_info.locked;
      self.set('canChangeName', canChangeName);
      self.notifyPropertyChange('canChangeName');
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

   _canPromoteSelectedEntity: function() {
      var self = this;
      if (self.get('model.stonehearth:job') && self.get('model.player_id') == App.stonehearthClient.getPlayerId()) {
         var jobConst = App.jobConstants[self.get('model.stonehearth:job.job_uri')];
         return jobConst && jobConst.description && !jobConst.description.is_npc_job;
      }
      return false;
   },

   showPromotionTree: function() {
      var self = this;
      if (self._canPromoteSelectedEntity()) {
         // do we need to do a click sound here? the promotion tree window makes a "paper" sound when it comes up
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
         App.stonehearthClient.showPromotionTree(self.get('uri'), self.get('model.stonehearth:job.job_index'));
      }
   },

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

   _updateJobChangeable: function() {
      var self = this;
      self.set('canChangeJob', self._canPromoteSelectedEntity())
   }.observes('model.stonehearth:job'),

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
            if (catalogData.equipment_types) {
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
               if (catalogData.equipment_types) {
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

   _updateBuffs: function() {
      var self = this;
      self._buffs = [];
      var attributeMap = self.get('model.stonehearth:buffs.buffs');

      if (attributeMap) {
         radiant.each(attributeMap, function(name, buff) {
            //only push public buffs (buffs who have an is_private unset or false)
            if (buff.invisible_to_player == undefined || !buff.invisible_to_player) {
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

   _updateTransformProgress: function() {
      var self = this;
      var progress = self.get('model.stonehearth_ace:transform.progress');
      if (progress) {
         var doneSoFar = progress.progress;
         var total = progress.max_progress;
         var percentage = Math.round((doneSoFar * 100) / total);
         self.set('transformProgress', percentage);
         Ember.run.scheduleOnce('afterRender', self, function() {
            self.$('#transformProgress').css("width", percentage / 100 * this.$('#transformProgressbar').width());
         });
      }
      else {
         self.set('transformProgress', null);
      }
   }.observes('model.stonehearth_ace:transform.progress'),

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

   showJobToggle: function() {
      return this.get('jobToggleButtonSettingEnabled') && this.get('hasJob');
   }.property('jobToggleButtonSettingEnabled', 'hasJob'),

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

   actions: {
      attackWithAllParties: function() {
         for (var i = 1; i <= 4; i++) {
            this._issueAttackCommand("party_" + i);
         }
      },

      attackWithParty: function(party) {
         this._issueAttackCommand(party);
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
