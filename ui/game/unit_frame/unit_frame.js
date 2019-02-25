var _selectionHasComponentInfo = false;

var _selectionHasComponentInfoChanged = function() {
   if (_selectionHasComponentInfo) {
      $('#componentInfoButton').show().css('display', 'inline-flex');
   }
   else {
      $('#componentInfoButton').hide();
   }
};

$(top).on("selection_has_component_info_changed", function (_, e) {
   _selectionHasComponentInfo = e.has_component_info;
   _selectionHasComponentInfoChanged();
});

$(top).on('stonehearthReady', function (cc) {
   if (!App.gameView) {
      return;
   }
   var unitFrameExtras = App.gameView.getView(App.UnitFrameExtrasView);
   if (!unitFrameExtras) {
      App.gameView.addView(App.UnitFrameExtrasView, {});
   }
});

App.UnitFrameExtrasView = App.View.extend({
   templateName: 'unitFrameExtras'
});

App.StonehearthUnitFrameView.reopen({
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
                  self.$('#nameInput').val(i18n.t(self.get('display_name'), { self: self.get('model') }))
                     .width(self.$('#nametag').outerWidth() - 16)  // 16 is the total padding and border of #nameInput
                     .show()
                     .focus()
                     .select();
               }
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
            radiant.call('stonehearth:set_custom_name', self.uri, value); // false for skip setting custom name
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

   willDestroyElement: function() {
      this._nameHelper.destroy();
      this._super();
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

   _updateChangeableName: function() {
      var self = this;
      var playerCheck = self.get('model.player_id') == App.stonehearthClient.getPlayerId();
      var unit_info = self.get('model.stonehearth:unit_info');
      var canChangeName = playerCheck && unit_info && !unit_info.locked;
      self.set('canChangeName', canChangeName);
      self.notifyPropertyChange('canChangeName');
      self.$('#nameInput').hide();
   }.observes('model.uri', 'model.stonehearth:unit_info'),

   toggleComponentInfo: function() {
      $(top).trigger('component_info_toggled', {});
   },

   _canPromoteSelectedEntity: function() {
      var self = this;
      return self.get('model.stonehearth:job') && self.get('model.player_id') == App.stonehearthClient.getPlayerId();
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
      var alias = this.get('model.uri');
      this.set('entityWithNonworkerJob', false);

      var description = this.get('model.stonehearth:unit_info.description');
      if (this.get('model.stonehearth:job') && !this.get('model.stonehearth:job.curr_job_controller.no_levels') && this.get('model.stonehearth:job.curr_job_name') !== '') {
         this.set('entityWithNonworkerJob', true);
         this.$('#Lvl').text( i18n.t('stonehearth:ui.game.unit_frame.Lvl'));
      }

      var display_name = this.get('model.stonehearth:unit_info.display_name');
      var custom_name = this.get('model.stonehearth:unit_info.custom_name');
      if (alias) {
         var catalogData = App.catalog.getCatalogData(alias);
         if (!catalogData) {
            console.log("no catalog data found for " + alias);
         } else {
            if (!display_name || !custom_name) {
               display_name = catalogData.display_name;
            }

            if (!description) {
               description = catalogData.description;
            }
         }
      }

      this.set('display_name', display_name);
      this.notifyPropertyChange('display_name');
      this.set('description', description);
      this.notifyPropertyChange('description');
   }.observes('model.uri'),

   _updateJobChangeable: function() {
      var self = this;
      self.set('canChangeJob', self.get('model.stonehearth:job') && self.get('model.player_id') == App.stonehearthClient.getPlayerId())
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
               var classArray = radiant.findRelevantClassesArray(equipmentPiece.roles);
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
