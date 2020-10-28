App.StonehearthStockpileView.reopen({
   destroy: function() {
      if (self._townTrace) {
         self._townTrace.destroy();
         self._townTrace = null;
      }
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      radiant.call('stonehearth:get_town')
         .done(function (response) {
            self._townTrace = new StonehearthDataTrace(response.result, {})
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }

                  self._defaultStorageItems = response.default_storage;
                  self._updateDefaultStorage();
               });
         });

      App.tooltipHelper.attachTooltipster(self.$('#defaultStorageLabel'),
         $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.default_storage.tooltip')))
      );

      App.tooltipHelper.attachTooltipster(self.$('#showLoadPreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.show_load.title'),
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.show_load.description')))
      );
      App.tooltipHelper.attachTooltipster(self.$('#showSavePreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.show_save.title'),
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.show_save.description')))
      );

      var defaultStorage = self.$('#defaultStorage');
      defaultStorage.click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
         radiant.call('stonehearth_ace:set_default_storage', self.uri, defaultStorage.prop('checked'));
      });
      
      self._filterPresets = stonehearth_ace.getStorageFilterPresets();

      self.$().on('click', '.presetPreview', function(e) {
         if (self.get('inLoadMode')) {
            $(this.parentElement).find('.loadPreset').click();
         }
         else if (self.get('inSaveMode')) {
            $(this.parentElement).find('.savePreset').click();
         }
      })

      var presetSearch = self.$('#presetSearch');
      presetSearch.keydown(function(e) {
         if (e.keyCode === 27) {
            self._togglePresetsVisibility(false);
            return false;
         }
      })
      .keyup(function(e) {
         var text = presetSearch.val();
         if (e.keyCode != 13 && e.keyCode != 27) {
            // filter the results by the text
            var lowerText = text.toLowerCase();
            var customNameExists = false;
            self.$('.presetRow').each(function() {
               var thisRow = $(this);
               var name = thisRow.data('name');
               var isDefault = thisRow.hasClass('default');
               var preset = self._getPreset(name, isDefault);
               if (lowerText.length < 1 || preset.title.toLowerCase().includes(lowerText)) {
                  thisRow.show();
               }
               else {
                  // also check all the materials
                  var shouldShow = false;
                  for (var i = 0; i < preset.materials.length; i++) {
                     if (preset.materials[i].includes(lowerText)) {
                        shouldShow = true;
                        break;
                     }
                  }
                  if (shouldShow) {
                     thisRow.show();
                  }
                  else {
                     thisRow.hide();
                  }
               }
               if (!isDefault && name == text) {
                  customNameExists = true;
               }
            });
            
            self.set('saveAllowed', !customNameExists);
         }
         else if (e.keyCode == 13 && text.length > 0) {
            var existingPreset = self._customPresets[text];
            if (self.get('inSaveMode')) {
               self._showSaveOverrideConfirmation(text);
            }
            else if (self.get('inLoadMode') && existingPreset) {
               self._loadPreset(existingPreset);
            }
         }
      });
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('#presetSearch').off('keydown').off('keyup');
      this.$().off('click', '.presetRow');
      this._super();
   },

   _updateDefaultStorage: function() {
      var self = this;
      var isDefault = false;
      var defaultStorage = self.$('#defaultStorage');

      if (self._defaultStorageItems) {
         radiant.each(self._defaultStorageItems, function(id, storage) {
            if (storage == self.uri) {
               isDefault = true;
               defaultStorage.prop('checked', true);
            }
         });
      }

      if (!isDefault) {
         defaultStorage.prop('checked', false);
      }
   }.observes('model.uri'),

   isSingleFilter: function() {
      return this.get('model.stonehearth:storage.is_single_filter');
   }.property('model.stonehearth:storage.is_single_filter'),

   _loadPresets: function() {
      var self = this;

      // index all the material filters
      var filters = self.get('stockpileFiltersUnsorted');
      var filterMaterials = {};
      if (filters.stockpile) {
         radiant.each(filters.stockpile, function(k, v) {
            radiant.each(v.categories, function(name, data) {
               if (!filterMaterials[data.filter]) {
                  filterMaterials[data.filter] = data;
               }
            });
         });
      }
      self._filterMaterials = filterMaterials;

      // first add the default presets; then add the custom presets
      var presets = [];
      self._defaultPresets = {};
      self._customPresets = {};

      var defaultPresetList = self._filterPresets.default_preset_list;
      var filterListUri = self.get('model.stonehearth:storage.filter_list.__self') || defaultPresetList;
      var defaultPresets = self._filterPresets.default_presets[filterListUri] || self._filterPresets.default_presets[defaultPresetList];

      radiant.each(defaultPresets, function(name, materials) {
         var preset = self._createPresetObj(name, materials, true);
         presets.push(preset);
         self._defaultPresets[name] = preset;
      });

      var customPresets = [];
      radiant.each(self._filterPresets.custom_presets, function(name, materials) {
         if (materials.length) {
            var preset = self._createPresetObj(name, materials);
            customPresets.push(preset);
            self._customPresets[name] = preset;
         }
      });

      // sort the custom ones based on whether they have any invalid filter materials in them
      customPresets.sort((a, b) => {
         if (a.has_invalid != b.has_invalid) {
            return b.invalid_materials.length - a.invalid_materials.length;
         }
         return a.title.localeCompare(b.title);
      });

      presets = presets.concat(customPresets);

      self.set('presets', presets);
      self.$('#presetSearch').val('');
      Ember.run.scheduleOnce('afterRender', self, '_updatePresetTooltips');
   }.observes('stockpileFiltersUnsorted'),

   _getFilterPresetDescription: function(preset) {
      if (preset.invalid_materials.length > 0) {
         return i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.preset_with_invalid_description', 
               { 'good_count': preset.valid_materials.length, 'bad_count': preset.invalid_materials.length });
      }
      else {
         return i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.preset_description', 
               { 'good_count': preset.valid_materials.length });
      }
   },

   _createPresetObj: function(name, materials, isDefault) {
      var self = this;
      var preview = self._getMaterialsPreview(materials);
      var preset = {
         name: name,
         materials: materials,
         preview_materials: preview.materials,
         valid_materials: preview.valid,
         invalid_materials: preview.invalid,
         has_valid: preview.valid.length > 0,
         has_invalid: preview.invalid.length > 0,
         show_ellipsis: preview.show_ellipsis,
         default: isDefault,
         title: isDefault ? i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.default_presets.' + name) : name
      }
      return preset;
   },

   _getMaterialsPreview: function(materials) {
      var self = this;
      // preview the first 9-10 materials in the filter and add an elipsis if there are more than 10
      var maxToShow = 10;
      var content = { 'valid': [], 'invalid': [] };
      var filters = self._filterMaterials;
      var previewMaterials = [];
      materials.forEach(material => {
         var data = filters[material];
         if (data) {
            previewMaterials.push(data);
            content.valid.push(material);
         }
         else {
            content.invalid.push(material);
         }
      });

      content.materials = previewMaterials.slice(0, maxToShow);

      if (content.valid.length > maxToShow) {
         // splice out the last one to make space for an ellipsis
         content.materials.splice(maxToShow - 1, 1);
         content.show_ellipsis = true;
      }

      return content;
   },

   _updatePresetTooltips: function() {
      var self = this;
      self.$('.presetRow').each(function() {
         var name = $(this).data('name');
         var isDefault = $(this).hasClass('default');
         var preset = self._getPreset(name, isDefault);
         App.tooltipHelper.createDynamicTooltip($(this).find('.presetPreview'), function () {
            // maybe work in the crafting requirements to this tooltip (e.g., 3/4 craftable, requires [Mason] Lvl 2)
            var description = self._getFilterPresetDescription(preset);
            return $(App.tooltipHelper.createTooltip(preset.title, description));
         }, {position: 'right', offsetX: 60});

         $(this).find('.loadPreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.load_preset.title')));
            });
         });
         $(this).find('.savePreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(
                  i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.save_preset.title'),
                  i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.save_preset.description')));
            });
         });
         $(this).find('.deletePreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(
                  i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.delete_preset.title'),
                  i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.filter_presets.buttons.delete_preset.description')));
            });
         });
      });
   },

   _togglePresetsVisibility: function(mode) {
      var self = this;
      var presets = self.$('#presetSelection');
      var visibility = false;
      if (mode) {
         visibility = !self.get(mode);
         if (!visibility) {
            mode = null;
         }
      }
      if (!visibility) {
         self._hidePresets();
      }
      else {
         self._loadPresets();
         self.set('inLoadMode', mode == 'inLoadMode');
         self.set('inSaveMode', mode == 'inSaveMode');
         presets.show();
      }
   },

   _hidePresets: function() {
      var self = this;
      self.$('#presetSelection').hide();
      self.set('inLoadMode', false);
      self.set('inSaveMode', false);
   }.observes('model.uri'),

   _loadPreset: function(preset) {
      var self = this;
      var realPreset = self._getPreset(preset.name, preset.default);

      if (realPreset) {
         radiant.call('stonehearth:set_stockpile_filter', this.uri, realPreset.valid_materials)
            .done(function(response) {
            });
         self._togglePresetsVisibility(false);
      }
   },

   _getPreset: function(name, isDefault) {
      var self = this;
      if (isDefault) {
         return self._defaultPresets[name];
      }
      else {
         return self._customPresets[name];
      }
   },

   _updatePresetsConfig: function() {
      var self = this;
      stonehearth_ace.updateStorageFilterPresets(self._filterPresets.custom_presets);
   },

   _showSaveOverrideConfirmation: function(name) {
      // TODO add save override confirmation dialog
      // for now just do it! who cares, what are they gonna do about it?!
      var self = this;
      if (!name || name.length < 1) {
         return;
      }

      var filter = self.get('model.stonehearth:storage.filter');
      if (!filter || !filter.length) {
         // if it's all or none, don't save it
         return;
      }

      if (self._customPresets[name]) {
         // do confirmation and return if canceled
      }
      self._saveCustomPreset(name, filter);
   },

   _saveCustomPreset: function(name, filter) {
      var self = this;
      self._filterPresets.custom_presets[name] = filter;
      self._updatePresetsConfig();
      self._loadPresets();
      self._togglePresetsVisibility(false);
   },

   _showDeletePresetConfirmation: function(name) {
      // TODO add save override confirmation dialog
      // for now just do it! who cares, what are they gonna do about it?!
      var self = this;
      self._deleteCustomPreset(name);
   },

   _deleteCustomPreset: function(name) {
      var self = this;
      delete self._filterPresets.custom_presets[name];
      self._updatePresetsConfig();
      self._loadPresets();
   },

   actions: {
      showLoadPreset: function() {
         var self = this;
         self._togglePresetsVisibility('inLoadMode');
      },

      showSavePreset: function() {
         var self = this;
         self._togglePresetsVisibility('inSaveMode');
      },

      loadPreset: function(preset) {
         var self = this;
         self._loadPreset(preset);
      },

      savePreset: function(preset) {
         var self = this;
         self._showSaveOverrideConfirmation(preset && preset.name);
      },

      saveCurrentPreset: function() {
         var self = this;
         self._showSaveOverrideConfirmation(self.get('saveAllowed') && self.$('#presetSearch').val());
      },

      deletePreset: function(preset) {
         var self = this;
         self._showDeletePresetConfirmation(preset.name);
      }
   }
});
