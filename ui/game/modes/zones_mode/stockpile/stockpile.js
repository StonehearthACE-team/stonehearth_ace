var lastTabPage = 'filterTab';
var stockpileFiltersFile = null;

App.StonehearthStockpileView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'stonehearthStockpile',
   closeOnEsc: true,
   lastClickedUri: null,
   lastClickedItem: null,

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:stockpile" : {},
      "stonehearth:storage" : {
         "item_tracker" : {
            "tracking_data" : {
               "*" : {
                  "item_qualities": {},
                  // ACE: also track uri and canonical uri entity data
                  "uri" : {},
                  "canonical_uri" : {}
               },
               "stonehearth:loot:gold" : {
                  "items" : {
                     "*" : {
                        "stonehearth:stacks": {}
                     }
                  }
               }
            }
         },
         "filter_list": {}
      },
      // ACE: additional components
      'stonehearth:expendable_resources' : {},
      'stonehearth_ace:consumer': {},
      "stonehearth_ace:quest_storage" : {
         "item_tracker" : {
            "tracking_data" : {
               "*" : {
                  "item_qualities": {},
                  // ACE: also track uri and canonical uri entity data
                  "uri" : {},
                  "canonical_uri" : {}
               },
               "stonehearth:loot:gold" : {
                  "items" : {
                     "*" : {
                        "stonehearth:stacks": {}
                     }
                  }
               }
            }
         }
      },
      'stonehearth_ace:auto_craft': {
         "ingredient_tracker" : {
            "tracking_data" : {
               "*" : {
                  "item_qualities": {},
                  // ACE: also track uri and canonical uri entity data
                  "uri" : {},
                  "canonical_uri" : {}
               },
               "stonehearth:loot:gold" : {
                  "items" : {
                     "*" : {
                        "stonehearth:stacks": {}
                     }
                  }
               }
            }
         },
         "output_tracker" : {
            "tracking_data" : {
               "*" : {
                  "item_qualities": {},
                  // ACE: also track uri and canonical uri entity data
                  "uri" : {},
                  "canonical_uri" : {}
               },
               "stonehearth:loot:gold" : {
                  "items" : {
                     "*" : {
                        "stonehearth:stacks": {}
                     }
                  }
               }
            }
         }
      }
   },

   init: function() {
      var self = this;
      self._super();
   },

   // ACE: override this to give an empty object if storage component is removed (e.g., universal storage component added)
   _loadFilters: function () {
      return this.set('stockpileFiltersUnsorted', this.get('model.stonehearth:storage.filter_list') || {});
   }.observes('model.stonehearth:storage.filter_list'),

   destroy: function() {
      var self = this;
      if (self._townTrace) {
         self._townTrace.destroy();
         self._townTrace = null;
      }
      self._super();
   },

   willDestroyElement: function() {
      this._inventoryPalette.stonehearthItemPalette('destroy');
      this._inventoryPalette = null;
      this._ingredientPalette.stonehearthItemPalette('destroy');
      this._ingredientPalette = null;
      this._outputPalette.stonehearthItemPalette('destroy');
      this._outputPalette = null;

      if (this._workshopViews) {
         radiant.each(this._workshopViews, function(_, workshop) {
            $(workshop).off('stonehearth_ace:workshop:auto_craft_orders_changed');
         });
         this._workshopViews = null;
      }

      App.guiHelper.removeDynamicTooltip(this.$('#autoCraftTab'), '.recipeEnabledCheck');
      App.guiHelper.removeDynamicTooltip(this.$('#autoCraftTab'), '.ingredient');
      App.guiHelper.removeDynamicTooltip(this.$('#autoCraftTab'), '.grabbable');

      this.$().off('click', '.tab');
      this.$().off('show', '.tabPage');
      this.$().off('click', '.group').off('click', '.filterCategory');

      this.$('#enableAutoCraft').off('change');
      this.$().off('change', '.recipeEnabledCheckbox');
      this.$().off('mouseenter mouseleave mousedown', '.grabbable');

      this.allButton.off('click');

      this.noneButton.off('click');

      this.$('button.ok').off('click');
      this.$('button.warn').off('click');

      this.taxonomyGrid.togglegrid('destroy');
      this.$().find('.tooltipstered').tooltipster('destroy');

      // ACE: handle extra disposal
      if (this._updateTimer) {
         clearInterval(this._updateTimer);
      }
      this.$('#presetSearch').off('keydown').off('keyup');
      this.$().off('click', '.presetRow');

      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;
      this.taxonomyGrid = this.$('#taxonomyGrid');
      this.allButton = this.$('#all');
      this.noneButton = this.$('#none');

      this.$().on('click', '.tab', function() {
         lastTabPage = $(this).attr('tabPage');
      });

      this.$().on('show', '.tabPage', function() {
         self._updateFooterVisibility();
      });

      this.taxonomyGrid.togglegrid();

      self.$().on('click', '.group', function() {
         self._onGroupClick($(this))
      });

      self.$().on('click', '.filterCategory', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
         self._onItemClick($(this));
      });

      this.allButton.click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
         self._selectAll();
      });

      this.noneButton.click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
         self._selectNone();
      });

      this.$('button.ok').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:submenu_select'} );
         self.destroy();
      });

      this.$('button.warn').click(function() {
         radiant.call('stonehearth:destroy_entity', self.uri)
         self.destroy();
      });

      self._refreshGrids();
      
      // ACE: lots of extra features
      // *don't* allow clicking to select a stored item because it will then close the storage view
      self._inventoryPalette = self.$('#inventoryPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
         // click: function (item) {
         //       // when the player clicks an inventory item, we want to try to select and go to that item
         //       // check if this was the last clicked item; if so, and it has count > 1, lookup "next" actual item for it
         //       var uri = item.attr('uri');
         //       var item_quality = item.attr('item_quality');
         //       var tracking_data = self.get('model.stonehearth:storage.item_tracker.tracking_data');
         //       var items = self.getItemsFromUri(tracking_data, uri, item_quality);
         //       if (items.length > 0) {
         //          if (uri != self.lastClickedUri) {
         //             self.lastClickedUri = uri;
         //             self.lastClickedItem = null;
         //          }
         //          var nextItem = 0;
         //          if (self.lastClickedItem) {
         //             nextItem = (items.indexOf(self.lastClickedItem) + 1) % items.length;
         //          }
         //          self.lastClickedItem = items[nextItem];

         //          radiant.call('stonehearth:select_entity', self.lastClickedItem);
         //       }
         // }
      });

      self._ingredientPalette = self.$('#ingredientPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
         skipCategories: true
      });

      self._outputPalette = self.$('#outputPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
         skipCategories: true
      });

      // set up ingredient buffer selector
      var bufferSizes = [];
      for (var i = 1; i <= 5; i++) {
         bufferSizes.push(i + '');
      }

      self._ingredientBufferSelector = App.guiHelper.createCustomSelector('autoCraft_ingredientBuffer', bufferSizes,
         function (key, value) {
            var val = parseInt(value.key);
            if (val != NaN) {
               radiant.call_obj(self.get('model.stonehearth_ace:auto_craft').__self, 'set_ingredient_buffer_multiplier', val);
            }
         }).container;
      self._ingredientBufferSelector.addClass('flexItem');
      self.$('#ingredientBuffer').append(self._ingredientBufferSelector);

      self._workshopViews = {};


      // ACE auto-craft recipes view:

      self.$('#enableAutoCraft').on('change', function() {
         // set all recipes enabled status to the same as this checkbox
         var checked = this.checked;

         var recipes = self.get('autoCraftRecipes');
         for (var i = 0; i < recipes.length; i++) {
            Ember.set(recipes[i], 'enabled', checked);
         }

         self._setEnabledRecipes();
      });

      self.$().on('change', '.recipeEnabledCheckbox', function() {
         var key = $(this).attr('recipeKey');
         var checked = this.checked;

         var recipes = self.get('autoCraftRecipes');
         for (var i = 0; i < recipes.length; i++) {
            if (recipes[i].key == key) {
               Ember.set(recipes[i], 'enabled', checked);
               break;
            }
         }

         self._setEnabledRecipes();
      });

      // https://stackoverflow.com/questions/2072848/reorder-html-table-rows-using-drag-and-drop
      // if checked and dragged, reorder (always remain checked)
      // if unchecked and dragged, mark checked and reorder only if dragged at least above lowest checked, otherwise ignore
      self.$().on('mouseenter', '.grabbable', function(e) {
         var tr = $(e.target).closest('tr');
         $(tr).addClass('pregrabbed');
      });
      self.$().on('mouseleave', '.grabbable', function(e) {
         var tr = $(e.target).closest('tr');
         $(tr).removeClass('pregrabbed');
      });
      self.$().on('mousedown', '.grabbable', function (e) {
         var tr = $(e.target).closest('tr');
         var sy = e.pageY;
         var drag;

         if ($(e.target).is('tr')) {
            tr = $(e.target);
         }
         var index = tr.index();
         $(tr).addClass('grabbed');

         var thisKey = $(this).attr('recipeKey');
         var thisEntry = self._autoCraftRecipes[thisKey];
         var curRecipes = self.get('model.stonehearth_ace:auto_craft.enabled_recipes');
         var isChecked = false;
         for(var i = 0; i < curRecipes.length; i++)
         {
            var enabledRecipe = curRecipes[i];
            if (thisEntry.job == enabledRecipe.job && thisEntry.recipe_key == enabledRecipe.recipe_key) {
               isChecked = true;
            }
         }

         function move (e) {
            if (!drag && Math.abs(e.pageY - sy) < 10) {
               return;
            }
            drag = true;

            tr.siblings().each(function() {
               var s = $(this), i = s.index(), y = s.offset().top;

               if (e.pageY >= y && e.pageY < y + s.outerHeight()) {
                  if (i < tr.index()) {
                     s.insertAfter(tr);
                  }
                  else {
                     s.insertBefore(tr);
                  }
                  return false;
               }
            });
         }

         function up (e) {
            var newIndex = tr.index();
            if (drag && index != newIndex) {
               drag = false;
               if (!isChecked) {
                  if (newIndex < curRecipes.length) {
                     // we dragged an unchecked recipe up into the checked recipes, so check it and apply changes
                     curRecipes.splice(newIndex, 0, {
                        job: thisEntry.job,
                        recipe_key: thisEntry.recipe_key,
                     });

                     self._setEnabledRecipes(curRecipes);
                  }
                  else {
                     // we dragged an unchecked recipe, and it doesn't matter so just don't do anything
                  }
               }
               else {
                  // first remove the old one
                  var prev = curRecipes.splice(index, 1);
                  // then add the new one
                  curRecipes.splice(newIndex, 0, prev[0]);

                  self._setEnabledRecipes(curRecipes);
               }
            }
            $(document).unbind('mousemove', move).unbind('mouseup', up);
            $(tr).removeClass('grabbed');
         }

         $(document).mousemove(move).mouseup(up);
      });


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

      App.tooltipHelper.attachTooltipster(self.$('#enableAutoCraft'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.toggle_enabled'),
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.enable_description')))
      );
      App.tooltipHelper.attachTooltipster(self.$('#ingredientBuffer .list-label'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.ingredient_buffer_multiplier'),
            i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.ingredient_buffer_multiplier_description')))
      );

      App.guiHelper.createDynamicTooltip(self.$('#autoCraftTab'), '.productImg', function($el) {
         var key = $el.attr('recipeKey');
         var recipe = self._autoCraftRecipes[key];
         var jobAlias = recipe.job;
         recipe = recipe.recipe;
         var options = {
            //recipe_key: jobAlias + "|" + key,
            display_name: recipe.display_name,
            description: recipe.description,
         };
         if (recipe.product_stacks) {
            options.self = {'stonehearth:stacks': {stacks: recipe.product_stacks}};
         }
         return $(App.guiHelper.createUriTooltip(recipe.product_uri, options));
      });

      App.guiHelper.createDynamicTooltip(self.$('#autoCraftTab'), '.ingredient', function($el) {
         var kind = $el.attr('data-kind');
         if (kind == 'uri') {
            var uri = $el.attr('data-identifier');
            return $(App.guiHelper.createUriTooltip(uri));
         }
         else {
            var title = $el.attr('title');
            return $(App.tooltipHelper.createTooltip(i18n.t(title)));
         }
      });

      App.guiHelper.createDynamicTooltip(self.$('#autoCraftTab'), '.grabbable', function($el) {
         var title = 'stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.reorder_recipe';
         var description = 'stonehearth_ace:ui.game.zones_mode.stockpile.auto_craft.reorder_recipe_description';
         return $(App.tooltipHelper.createTooltip(i18n.t(title), i18n.t(description)));
      }, {delay: 1000});

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

      self._updateTimer = setInterval(() => {
         // make sure it's been updated, in case Limit Network Data gameplay setting is set
         var uri = self.get('uri');
         if (uri) {
            radiant.call('stonehearth_ace:storage_mark_changed', uri);
         }
      }, 1000);

      self._resumedTabOnInsert = false;
   },

   _resumeTabOnInsert: function() {
      var self = this;
      if (!self._resumedTabOnInsert) {
         self._resumedTabOnInsert = true;
         // Resume on last selected tab
         Ember.run.scheduleOnce('afterRender', self, '_resumeLastTab');
      }
   }.observes('model.stonehearth:storage'),

   _updateStockpileFilters: function() {
      var self = this;
      var filters = self.get('stockpileFiltersUnsorted');
      if (filters.stockpile) {
         var sortedFilters = radiant.map_to_array(filters.stockpile);
         sortedFilters.sort(function(a, b){
            var aOrd = a.ordinal ? a.ordinal : 10000;
            var bOrd = b.ordinal ? b.ordinal : 10000;
            return aOrd - bOrd;
         });
         for(var i=0; i < sortedFilters.length; ++i) {
            var group = sortedFilters[i];
            var categories = radiant.map_to_array(group.categories);
            categories.sort(function(a, b){
               var aOrd = a.ordinal ? a.ordinal : 10000;
               var bOrd = b.ordinal ? b.ordinal : 10000;
               return aOrd - bOrd;
            });
            Ember.set(group, 'categories', categories);
         }

         self.set('stockpileFilters', sortedFilters);
         Ember.run.scheduleOnce('afterRender', self, '_updateTooltips');
      }
   }.observes('stockpileFiltersUnsorted'),

   _updateTooltips: function() {
      var self = this;
      var images = self.$('.categoryImage');
      if (images) {
         images.each(function() {
            var element = $( this );
            var display_name = element.attr('display_name');
            var translated = i18n.t(display_name);
            element.attr('title', translated);
            element.tooltipster();
         });
      }
      self._refreshGrids();
   },

   _updateShowCategories: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         if (!self._inventoryPalette) {
            // When moving a crate, this function will fire, but no UI will be present.  For now, be lazy
            // and just ignore this case.
            return;
         }
         self._inventoryPalette.stonehearthItemPalette('setSkipCategories', self.get('model.stonehearth_ace:consumer') != null);
      });
   }.observes('model.uri', 'model.stonehearth_ace:consumer'),

   _updateStockedItems : function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         if (!self._inventoryPalette) {
            // When moving a crate, this function will fire, but no UI will be present.  For now, be lazy
            // and just ignore this case.
            return;
         }
         var tracker = self.get('model.stonehearth:storage.item_tracker');
         var inventoryItems = {}
         if (tracker != null) {
            // Extract quality entries.
            radiant.each(tracker.tracking_data, function (uri, uri_entry) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
                  var key = uri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key;
                  inventoryItems[key] = radiant.shallow_copy(uri_entry);
                  inventoryItems[key].count = item.count;
                  inventoryItems[key].item_quality = item_quality_key;
               });
            });
         }
         self._inventoryPalette.stonehearthItemPalette('updateItems', inventoryItems);

         // var backpackCapacity = self.get('model.stonehearth:storage.capacity');

         // if (backpackCapacity) {
         //    self.set('used_spaces', self.get('model.stonehearth:storage.num_items'));
         //    self.set('capacity', backpackCapacity);
         // }
      });
   }.observes('model.stonehearth:storage.item_tracker'),

   _updateIngredients : function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         if (!self._ingredientPalette) {
            // When moving a crate, this function will fire, but no UI will be present.  For now, be lazy
            // and just ignore this case.
            return;
         }
         var tracker = self.get('model.stonehearth_ace:auto_craft.ingredient_tracker');
         var inventoryItems = {}
         if (tracker != null) {
            // Extract quality entries.
            radiant.each(tracker.tracking_data, function (uri, uri_entry) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
                  var key = uri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key;
                  inventoryItems[key] = radiant.shallow_copy(uri_entry);
                  inventoryItems[key].count = item.count;
                  inventoryItems[key].item_quality = item_quality_key;
               });
            });
         }
         self._ingredientPalette.stonehearthItemPalette('updateItems', inventoryItems);
      });
   }.observes('model.stonehearth_ace:auto_craft.ingredient_tracker'),

   _updateOutput : function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         if (!self._outputPalette) {
            // When moving a crate, this function will fire, but no UI will be present.  For now, be lazy
            // and just ignore this case.
            return;
         }
         var tracker = self.get('model.stonehearth_ace:auto_craft.output_tracker');
         var inventoryItems = {}
         if (tracker != null) {
            // Extract quality entries.
            radiant.each(tracker.tracking_data, function (uri, uri_entry) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
                  var key = uri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key;
                  inventoryItems[key] = radiant.shallow_copy(uri_entry);
                  inventoryItems[key].count = item.count;
                  inventoryItems[key].item_quality = item_quality_key;
               });
            });
         }
         self._outputPalette.stonehearthItemPalette('updateItems', inventoryItems);
      });
   }.observes('model.stonehearth_ace:auto_craft.output_tracker'),

   _updateIngredientBufferSelector: function() {
      App.guiHelper.setListSelectorValue(this._ingredientBufferSelector, this.get('model.stonehearth_ace:auto_craft.ingredient_buffer_multiplier') + '');
   }.observes('model.stonehearth_ace:auto_craft.ingredient_buffer_multiplier'),

   _updateNumItems : function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         var capacity = self.get('model.stonehearth:storage.capacity');

         if (capacity) {
            self.set('used_spaces', self.get('model.stonehearth:storage.num_items'));
            self.set('capacity', capacity);
         }
      });
   }.observes('model.stonehearth:storage.num_items'),

   _updateOutputNumItems : function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         var capacity = self.get('model.stonehearth_ace:auto_craft.output_capacity');

         if (capacity) {
            self.set('outputUsedSpaces', self.get('model.stonehearth_ace:auto_craft.output_num_items'));
            self.set('outputCapacity', capacity);
         }
      });
   }.observes('model.stonehearth_ace:auto_craft.output_num_items'),

   _updateRecipes: function() {
      var self = this;
      var recipes = self.get('model.stonehearth_ace:auto_craft.recipes');
      if (recipes) {
         var cb = function () {
            self._autoCraftRecipes = {};
            radiant.each(recipes, function (job, jobRecipe) {
               var workshop = App.workshopManager.getWorkshop(job);
               self._workshopViews[job] = workshop;
               $(workshop).on('stonehearth_ace:workshop:auto_craft_orders_changed', () => self._updateRecipesList());

               radiant.each(jobRecipe, function (recipe_key, allowed) {
                  if (allowed) {
                     // try to get the recipe data from the workshop
                     var recipe = workshop._getOrCalculateRecipeData(recipe_key);
                     if (recipe) {
                        var jobRecipeKey = job + '.' + recipe_key;
                        self._autoCraftRecipes[jobRecipeKey] = {
                           key: jobRecipeKey,
                           recipe: recipe,
                           job: job,
                           recipe_key: recipe_key,
                        }
                     }
                  }
               });
            });

            // now we have all the recipes that we should have for this auto-crafter
            // update the recipe list with their data
            self.set('autoCraftRecipes', []);
            self._updateRecipesList();
         };

         radiant.each(recipes, function (job, jobRecipe) {
            if (!self._workshopViews[job]) {
               App.workshopManager.getWorkshop(job, cb);
               cb = null;
            }
         });

         // if we didn't need to load any workshops, then we can just update the recipes now
         if (cb != null) {
            cb();
         }
      }
      else {
         self._autoCraftRecipes = null;
      }
   }.observes('model.stonehearth_ace:auto_craft.recipes'),

   _updateRecipesList: function() {
      // enabled recipes will be an ordered array of all the available recipes with a field for whether they're enabled
      // this way we can adjust the preferred crafting priority per auto-crafter
      var self = this;
      if (!self._autoCraftRecipes) {
         return;
      }

      var enabledRecipes = self.get('model.stonehearth_ace:auto_craft.enabled_recipes');
      if (enabledRecipes) {
         var prevRecipes = {};
         var recipes = [];
         radiant.each(enabledRecipes, function(_, enabledRecipe) {
            var key = enabledRecipe.job + '.' + enabledRecipe.recipe_key;
            prevRecipes[key] = true;
            recipes.push({
               key: key,
               job: enabledRecipe.job,
               recipe_key: enabledRecipe.recipe_key,
               recipe: self._autoCraftRecipes[key].recipe,
               enabled: true,
            });
         });

         radiant.each(self._autoCraftRecipes, function(key, recipe) {
            var prevEntry = prevRecipes[key];
            if (!prevEntry) {
               recipes.push({
                  key: recipe.key,
                  job: recipe.job,
                  recipe_key: recipe.recipe_key,
                  recipe: recipe.recipe,
               });
            }
         });

         recipes.forEach(function(recipe) {
            var workshop = self._workshopViews[recipe.job];
            var hasOrder = workshop && workshop.hasAutoCraftOrder(recipe.recipe_key);
            recipe.hasOrder = hasOrder;
         });

         self.set('autoCraftRecipes', recipes);
      }
   }.observes('model.stonehearth_ace:auto_craft.enabled_recipes'),

   // either pass in a specific array of entries,
   // or if none is passed in, compile it from the current enabled entries
   _setEnabledRecipes: function(recipes) {
      var self = this;
      recipes = self._updateEnabledRecipes(recipes);

      radiant.call_obj(self.get('model.stonehearth_ace:auto_craft').__self, 'set_enabled_recipes', recipes);
   },

   _updateEnabledRecipes: function(recipes) {
      var self = this;

      var hasDisabled = false;
      var allRecipes = self.get('autoCraftRecipes');
      if (!recipes) {
         recipes = [];
         radiant.each(allRecipes, function(_, entry) {
            if (entry.enabled) {
               recipes.push({
                  job: entry.job,
                  recipe_key: entry.recipe_key,
               });
            }
            else {
               hasDisabled = true;
            }
         });
      }

      self.$('#enableAutoCraft').prop('checked', recipes.length == allRecipes.length);
      self.$('#enableAutoCraft').prop('indeterminate', hasDisabled && recipes.length > 0);

      return recipes;
   },

   _updateEnableAutoCraftCheckbox: function() {
      this._updateEnabledRecipes();
   }.observes('autoCraftRecipes'),

   _updateTabs: function() {
      var self = this;

      var filterTabElement = self.$('div[tabPage=filterTab]');
      if (!filterTabElement) {  // Too early or too late.
         return;
      }

      var stockpileId = self.get('model.player_id');
      var isOwner = stockpileId && App.stonehearthClient.getPlayerId() == stockpileId;
      if (!isOwner) {
         // Hide filter tab if client doesn't own this object
         filterTabElement.hide();
         var filterTabPage = self.$('#filterTab');
         filterTabPage.hide();

         var contentsTabElement = self.$('div[tabPage=contentsTab]');
         contentsTabElement.addClass('active');
         var contentsTabPage = self.$('#contentsTab');
         contentsTabPage.show();
      } else {
         // Show filter tab 
         filterTabElement.show();

         Ember.run.scheduleOnce('afterRender', self, '_resumeLastTab');
      }
   }.observes('model.stonehearth:unit_info'),

   _resumeLastTab: function() {
      this.$('div[tabPage]').removeClass('active');
      this.$('.tabPage').hide();

      // TODO: try to resume the last tab, but this entity might not have that tab
      // e.g., filter might be hidden, or it might be an auto-crafter (or not when the previously selected entity was)
      // in that case, default to the first tab, but don't save it as the last tab
      var tab = this.$('div[tabPage=' + lastTabPage + ']');
      if (!tab.length) {
         tab = this.$('div[tabPage]:first');
      }
      tab.addClass('active');

      var tabPage = this.$('#' + tab.attr('tabPage'));
      tabPage.show();
   },

   _updateFooterVisibility: function() {
      var self = this;
      var tab = self.$('div.active[tabPage]');
      var curTabName = tab.attr('tabPage');
      var visible = curTabName != 'filterTab' && curTabName != 'contentsTab';

      // if we're showing it, do that after render; otherwise, do it immediately
      if (visible) {
         Ember.run.scheduleOnce('afterRender', self, () => self.set('currentTabHideFooter', true));
      }
      else {
         self.set('currentTabHideFooter', false);
      }
   },

   _selectAll : function() {
      this.$('.filterCategory').addClass('on');
      // Set the filter to Nil. This makes it really ALL again.
      radiant.call('stonehearth:set_stockpile_filter', this.uri);
   },

   _selectNone : function() {
      this.$('.filterCategory').removeClass('on');
      this._setStockpileFilter();
   },

   _refreshGrids : function() {
      var self = this;
      if (!self.$('.filterCategory')) {
         return;
      }

      self.$('button.warn').css('display', self.get('model.stonehearth:stockpile') ? 'inline-block' : 'none');

      var stockpileFilter = self.get('model.stonehearth:storage.filter');

      self.$('.filterCategory').removeClass('on');

      if (stockpileFilter) {
         self.$('.filterCategory').each(function(i, element) {
            var button = $(element)
            var buttonFilter = button.attr('filter')

            if (!buttonFilter) {
               console.log('button ' + button.attr('id') + " has no filter!")
            } else {
               radiant.each(stockpileFilter, function(i, filter) {
                  if (buttonFilter == filter) {
                     button.addClass('on');
                  }
               });
            }
         });

         self._updateGroups();
      } else {
         self.allButton.prop('checked', true)
         self.noneButton.prop('checked', false);
         self.$('.group').prop('checked', true)
         self.$('.filterCategory').addClass('on');
      }

      if (this.get('model.stonehearth:storage.is_single_filter')) {
         var selectedFilter = self.$('#taxonomyGrid .filterCategory.on .categoryImage');
         var name, icon;
         if (selectedFilter.length) {
            name = selectedFilter.attr('title');
            icon = selectedFilter.attr('src');
         } else {
            name = i18n.t('stonehearth:ui.game.zones_mode.stockpile.filters.none');
            icon = '/stonehearth/ui/common/images/transparent.png';
         }
         self.$('.selectedFilter .label').text(name);
         self.$('.selectedFilter .icon')
            .attr('src', icon)
            .attr('title', name)
            .tooltipster();
         self.set('selected_filter_label', name);
      }
   }.observes('model.stonehearth:storage.filter'),

   _onGroupClick: function (element) {
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
      var checked = element.prop('checked');

      $('.filterCategory', element.closest('.row')).each(function (i, categoryChild) {
         $(categoryChild).toggleClass('on', checked);
      });

      this._setStockpileFilter();
   },

   _onItemClick : function(element) {
      element.toggleClass('on');
      if (element.hasClass('on') && this.get('model.stonehearth:storage.is_single_filter')) {
         this.$('.filterCategory').each(function () {
            if (element[0] != this) {
               $(this).removeClass('on');
            }
         });
      }

      this._setStockpileFilter();
   },

   _setStockpileFilter : function() {
      var values = [];
      $('#taxonomyGrid').find('.on').each(function(i, element) {
         var value = $(element).attr('filter');
         if (value) {
            values.push(value);
         }
      });

      radiant.call('stonehearth:set_stockpile_filter', this.uri, values)
         .done(function(response) {
         });
   },

   // As of jQuery 1.6, we should be using .prop() instead of .attr() to get and set the checked property of checkboxes:
   // http://api.jquery.com/prop
   // http://stackoverflow.com/questions/5874652/prop-vs-attr/5876747#5876747
   _updateGroups : function() {
      var self = this;

      var allGroupsOn = true;
      var noGroupsOn = true;

      self.$('.group').each(function (i, group) {
         var groupOn = true;
         $('.filterCategory', group.closest('.row')).each(function(i, sibling) {
            var category = $(sibling);
            if (category.hasClass('on')) {
               noGroupsOn = false;
            } else {
               groupOn = false;
               allGroupsOn = false;
            }
         });

         $(group).prop('checked', groupOn);
      });

      self.allButton.prop('checked', allGroupsOn);
      self.noneButton.prop('checked', noGroupsOn);
   },

   // ACE: lots of additional features
   getItemsFromUri: function (tracking_data, this_uri, this_quality) {
      var self = this;
      var items = [];

      if (this_uri) {
         radiant.each(tracking_data, function (_, uri_entry) {
            var uri = uri_entry.__self || (uri_entry.uri && uri_entry.uri.__self);
            if (this_uri == uri) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item_of_quality) {
                  if (item_quality_key == this_quality) {
                     radiant.each(item_of_quality.items, function (_, item) {
                        items.push(item);
                     });
                  }
               });
            }
         });
      }

      return items;
   },

   allowDefaultStorage: function() {
      return this.get('model.stonehearth:storage.allow_default')
   }.property('model.stonehearth:storage.allow_default'),

   showFilterTab: function() {
      return this.get('model.stonehearth:storage.show_filter')
   }.property('model.stonehearth:storage.show_filter'),

   isStorage: function() {
      return this.get('model.stonehearth:storage') != null
   }.property('model.stonehearth:storage'),

   isAutoCrafter: function() {
      return this.get('model.stonehearth_ace:auto_craft') != null
   }.property('model.stonehearth_ace:auto_craft'),

   isMechanical: function() {
      return this.get('model.stonehearth_ace:mechanical') != null
   }.property('model.stonehearth_ace:mechanical'),

   filterTabName: function() {
      if (this.get('model.stonehearth_ace:consumer')) {
         return 'stonehearth_ace:ui.game.zones_mode.stockpile.fuel_filter';
      }
      else {
         return 'stonehearth:ui.game.zones_mode.stockpile.filter';
      }
   }.property('model.stonehearth_ace:consumer'),

   contentsTabName: function() {
      if (this.get('model.stonehearth_ace:consumer')) {
         return 'stonehearth_ace:ui.game.zones_mode.stockpile.fuel_contents';
      }
      else {
         return 'stonehearth:ui.game.zones_mode.stockpile.contents';
      }
   }.property('model.stonehearth_ace:consumer'),

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

   _updateTotalFuel: function() {
      var self = this;
      var perCraft = self.get('fuelPerCraft');
      var level = self.get('fuelLevel');
      var potential = self.get('potentialFuel');

      var tooltip = self.get('fuelTooltip');
      var useIcon = self.get('fuelUseIcon');
      var noUseIcon = self.get('noFuelUseIcon');
      var extraUseIcon = self.get('extraFuelUseIcon');
      var maxIcons = self.get('maxFuelIcons');

      if (!perCraft || level == null || potential == null) {
         return;
      }
      var totalCrafts = Math.floor((level + potential) / perCraft);

      var fuelBars = '';
      if (totalCrafts < 1) {
         fuelBars = `<img class="noFuelUse" src="${noUseIcon}">`
      }
      else {
         var numIcons = totalCrafts > maxIcons ? maxIcons - 1 : totalCrafts;
         for(var i = 0; i < numIcons; i++) {
            fuelBars += `<img class="fuelUse" src="${useIcon}">`;
         }
         if (totalCrafts > maxIcons) {
            fuelBars += `<img class="extraFuelUse" src="${extraUseIcon}">`;
         }
      }
      
      self.set('fuelBars', fuelBars);

      if (self.$('#fuelLevel').hasClass('tooltipstered')) {
         self.$('#fuelLevel').tooltipster('destroy');
      }
      Ember.run.scheduleOnce('afterRender', self, function() {
         var fuelLevelDiv = self.$('#fuelLevel');
         if (fuelLevelDiv) {
            // verify that we actually have the correct values for these as they may have been updated
            perCraft = self.get('fuelPerCraft');
            var residualCrafts = Math.floor(self.get('fuelLevel') / perCraft);
            var potentialCrafts = Math.floor(self.get('potentialFuel') / perCraft);
            var totalCrafts = residualCrafts + potentialCrafts;

            var tooltipStr = i18n.t(tooltip, {num_residual: residualCrafts, num_potential: potentialCrafts, num_total: totalCrafts});
            var tt = App.tooltipHelper.createTooltip('', tooltipStr);
            fuelLevelDiv.tooltipster({
               content: $(tt)
            });
         }
      });
   }.observes('fuelPerCraft', 'fuelLevel', 'potentialFuel'),

   _updateIsConsumer: function() {
      var self = this;
      var consumer = self.get('model.stonehearth_ace:consumer');
      self.set('isConsumer', consumer != null);
      if (consumer) {
         self.set('fuelLabel', consumer.fuel_label || 'stonehearth_ace:ui.game.zones_mode.stockpile.fuel_level.label');
         self.set('fuelTooltip', consumer.fuel_tooltip || 'stonehearth_ace:ui.game.zones_mode.stockpile.fuel_level.tooltip');
         self.set('fuelUseIcon', consumer.fuel_use_icon || '/stonehearth_ace/ui/game/modes/zones_mode/stockpile/images/fuel_use.png');
         self.set('noFuelUseIcon', consumer.no_fuel_use_icon || '/stonehearth_ace/ui/game/modes/zones_mode/stockpile/images/no_fuel_use.png');
         self.set('extraFuelUseIcon', consumer.extra_fuel_use_icon || '/stonehearth_ace/ui/game/modes/zones_mode/stockpile/images/extra_fuel_use.png');
         self.set('maxFuelIcons', consumer.max_fuel_icons || 14);
         self.set('fuelPerCraft', consumer.fuel_per_use || null);
      }
   }.observes('model.stonehearth_ace:consumer'),

   _updateFuelLevel: function() {
      var self = this;
      var fuelLevel = self.get('model.stonehearth:expendable_resources.resources.fuel_level') + self.get('model.stonehearth:expendable_resources.resources.reserved_fuel_level');
      self.set('fuelLevel', fuelLevel);
   }.observes('model.stonehearth:expendable_resources.resources.fuel_level', 'model.stonehearth:expendable_resources.resources.reserved_fuel_level'),

   _updateItemsFuel : function() {
      var self = this;
      var tracker = self.get('model.stonehearth:storage.item_tracker');
      if (tracker == null || !self.get('model.stonehearth_ace:consumer')) {
         return;
      }

      var fuelLevel = 0;
      // count up fuel amount in stored items
      radiant.each(tracker.tracking_data, function (uri, uri_entry) {
         var entity_data = self._getEntityData(uri_entry);
         var fuelData = entity_data && entity_data['stonehearth_ace:fuel'];
         if (fuelData) {
            var fuelAmount = fuelData.fuel_amount || 1;
            radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
               fuelLevel += fuelAmount * item.count;
            });
         }
      });

      self.set('potentialFuel', fuelLevel);
   }.observes('model.uri', 'model.stonehearth:storage.item_tracker', 'model.stonehearth_ace:consumer'),

   _getEntityData: function(item) {
      if (item.canonical_uri && item.canonical_uri.entity_data) {
         return item.canonical_uri.entity_data;
      }

      if (item.uri.entity_data) {
         return item.uri.entity_data;
      }

      return null;
   },

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
      // preview the first 9-10 materials in the filter and add an ellipsis if there are more than 10
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
      var presetRows = self.$('.presetRow');
      if (presetRows) {
         presetRows.each(function() {
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
      }
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
