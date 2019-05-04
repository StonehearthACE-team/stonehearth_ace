var _selectionHasComponentInfo = false;

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

$(top).on("selection_has_component_info_changed", function (_, e) {
   _selectionHasComponentInfo = e.has_component_info;
   _selectionHasComponentInfoChanged();
});

App.StonehearthUnitFrameView.reopen({
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
      "stonehearth:commands": {
          "commands": {}
      },
      "stonehearth:job": {
          'curr_job_controller': {}
      },
      "stonehearth:buffs": {
          "buffs": {
              "*": {}
          }
      },
      'stonehearth:expendable_resources': {},
      "stonehearth:unit_info": {},
      "stonehearth:stacks": {},
      "stonehearth:material": {},
      "stonehearth:workshop": {
          "crafter": {},
          "crafting_progress": {},
          "order": {}
      },
      "stonehearth:happiness": {
          "current_mood_buff": {}
      },
      "stonehearth:pet": {},
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
      "stonehearth:party_member": {
          "party": {
              "stonehearth:unit_info": {}
          }
      },
      "stonehearth:siege_weapon": {},
      "stonehearth:door": {},
      "stonehearth:iconic_form": {
          "root_entity": {
              "uri": {},
              'stonehearth:item_quality': {},
              "stonehearth:unit_info": {},
              "stonehearth_ace:titles": {}
          }
      },
      "stonehearth:work_order": {
          "work_order_statuses": {},
          "work_order_refs": {}
      },
      "stonehearth_ace:titles": {}
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

      _selectionHasComponentInfoChanged();
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
   _updateUnitFrameWidth: function() {
      //the following is some rough dynamic sizing to prevent descriptions and command buttons from overlapping
      //it has to happen after render to check the elements for the unit frame for the newly selected item, not the previous
      Ember.run.scheduleOnce('afterRender', this, function() {
         var width = Math.max(this.$('#descriptionDiv').width() + this.$('#commandButtons').width() + 30, // + 30 to account for margins
                              this.$('#topBar').width());
         if (this.get('hasPortrait')) {
            width += this.$('#portrait-frame').width();
         }

         this.$('#unitFrame').css('width', Math.max(500, width) + 'px'); //don't want it getting too bitty
      });
   }.observes('model.uri', 'model.stonehearth:commands.commands', 'model.stonehearth:unit_info', 'model.stonehearth:job'),

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
         App.stonehearthClient.showPromotionTree(self.get('uri'));
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
   }.observes('model.stonehearth:iconic_form.root_entity.uri')
});
