var _playerMercantileControllerUri = null;

// The view that shows all your active merchants, market stalls, and mercantile preferences
App.StonehearthAceMerchantileView = App.View.extend({
   templateName: 'mercantile',
   classNames: ['flex', 'fullScreen', 'exclusive'],
   closeOnEsc: true,

   uriProperty: 'model',
   components: {
      'active_merchants': {
         '*': {
            // 'stonehearth_ace:merchant': {
            //    'stall': {
            //       'stonehearth:unit_info': {},
            //    }
            // },
            'stonehearth:unit_info': {},
         }},
   },

   init: function() {
      var self = this;
      this._super();

      var self = this;
      self._activeMerchants = {};
      if (_playerMercantileControllerUri) {
         self.set('uri', _playerMercantileControllerUri);
      }
      else {
         self.set('numMerchants', '');
         radiant.call_obj('stonehearth_ace.mercantile', 'get_player_controller_command')
            .done(function (response) {
               _playerMercantileControllerUri = response.controller;
               self.set('uri', _playerMercantileControllerUri);
            });
      }
   },

   destroy: function() {
      this._destroyMerchantTraces();
      this._super();
   },

   _destroyMerchantTraces: function(exceptTheseMerchants) {
      var keptTraces = {};
      var tracesRemoved = false;
      if (this._merchantTraces) {
         radiant.each(this._merchantTraces, function(id, trace) {
            if (exceptTheseMerchants && exceptTheseMerchants[id] != null) {
               keptTraces[id] = trace;
            }
            else {
               trace.destroy();
               tracesRemoved = true;
            }
         });
      }
      this._merchantTraces = keptTraces;
      return tracesRemoved;
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      this.$().draggable({ handle: '.title' });

      this.$('#activeTab').show();

      var tooltip = $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_title'),
            i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_description')));
      self.$('#numMerchants').tooltipster({delay: 1000, content: tooltip});

      self.$('#merchants').on('click', '.shop', function() {
         var merchantDiv = $(this).parent();
         if (merchantDiv) {
            var id = merchantDiv.attr('merchant-id');
            var merchant = id && self._activeMerchants[id];
            if (merchant) {
               $(top).trigger('stonehearth_ace_show_shop', {entity: merchant.entity});
            }
         }
      });
      
      self.$('#merchants').on('click', '.stallPortrait', function() {
         var merchantDiv = $(this).parent();
         if (merchantDiv) {
            var id = merchantDiv.attr('merchant-id');
            var merchant = id && self._activeMerchants[id];
            if (merchant) {
               radiant.call('stonehearth:select_entity', merchant.stall_entity);
               radiant.call('stonehearth:camera_look_at_entity', merchant.stall_entity);
            }
         }
      });

      self.$('#merchants').on('click', '.merchantPortrait', function() {
         var merchantDiv = $(this).parent();
         if (merchantDiv) {
            var id = merchantDiv.attr('merchant-id');
            var merchant = id && self._activeMerchants[id];
            if (merchant) {
               radiant.call('stonehearth:select_entity', merchant.entity);
               radiant.call('stonehearth:camera_look_at_entity', merchant.entity);
            }
         }
      });

      self._setupCategories();
   },

   willDestroyElement: function() {
      var self = this;
      this.$('#merchants').off('click', '.shop');
      this.$('#merchants').off('click', '.stall');
      this.$('#merchants').off('click', '.portrait');
      this.$('#mercantile').find('.tooltipstered').tooltipster('destroy');

      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.name'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.stall'));

      this._super();
   },

   _updateNumMerchants: function() {
      var self = this;
      var maxDailyMerchants = self.get('model.max_daily_merchants');
      var limitedByStalls = self.get('model.limited_by_stalls');
      var numStalls = self.get('model.num_stalls');
      var numMerchants = null;

      if (maxDailyMerchants == 0) {
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_none');
      }
      else if (maxDailyMerchants <= 1) {
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_one');
      }
      else if (maxDailyMerchants == App.constants.mercantile.max) {
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_max', {num_merchants: maxDailyMerchants});
      }
      else if (maxDailyMerchants > 1 && limitedByStalls) {
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_limited',
               {
                  num_merchants: Math.ceil(maxDailyMerchants),
                  num_stalls: numStalls,
               });
      }
      else if (maxDailyMerchants == Math.floor(maxDailyMerchants)) {
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_exact', {num_merchants: maxDailyMerchants});
      }
      else {
         // show the integer range
         numMerchants = i18n.t('stonehearth_ace:ui.game.mercantile.active.info.num_merchants_range',
               {
                  num_merchants: `${Math.floor(maxDailyMerchants)}-${Math.ceil(maxDailyMerchants)}`,
               });
      }

      self.set('numMerchants', numMerchants);
   }.observes('model.max_daily_merchants', 'model.limited_by_stalls', 'model.num_stalls'),

   _updateAvailableStalls: function() {
      var self = this;
      var tier_stalls = self.get('model.tier_stalls');
      var exclusive_stalls = self.get('model.exclusive_stalls');
      var merchants = self.get('merchants');
      if (!tier_stalls || !exclusive_stalls || !merchants) {
         return;
      }

      var availableStalls = {};

      radiant.each(tier_stalls, function(tier, num) {
         var realTier = tier + 1;   // lua is 1-indexed
         availableStalls[realTier] = {
            id: realTier,
            display_name: i18n.t(`stonehearth_ace:ui.game.mercantile.active.stalls.tier${realTier}_display_name`),
            description: i18n.t(`stonehearth_ace:ui.game.mercantile.active.stalls.tier${realTier}_description`),
            tier_class: `tier${realTier}`,
            num: num,
            total: num,
         };
      });
      radiant.each(exclusive_stalls, function(uri, num) {
         var catalogData = App.catalog.getCatalogData(uri);
         if (catalogData && catalogData.icon) {
            availableStalls[uri] = {
               id: uri,
               display_name: i18n.t(catalogData.display_name),
               description: i18n.t(catalogData.description),
               tier_class: 'exclusive',
               icon: catalogData.icon,
               num: num,
               total: num,
            };
         }
      });

      radiant.each(merchants, function(_, merchant) {
         if (merchant.has_stall) {
            var tier = merchant.stall_tier;
            if (tier) {
               var available = availableStalls[tier];
               if (available != null) {
                  available.num--;
               }
            }
            else {
               var available = availableStalls[merchant.stall_uri];
               if (available != null) {
                  available.num--;
               }
            }
         }
      });

      var availableStallsArr = [];
      radiant.each(availableStalls, function(_, stall) {
         if (stall.num == 0) {
            stall.num_class = 'limited';
         }
         else if (stall.num == stall.total) {
            stall.num_class = 'max';
         }
         availableStallsArr.push(stall);
      });

      self._availableStalls = availableStalls;
      if (availableStallsArr.length > 0) {
         self.set('availableStalls', availableStallsArr);
         self.set('hasAvailableStalls', true);
         self._updateStallTooltips();
      }
      else {
         self.set('hasAvailableStalls', false);
         self.set('availableStalls', null);
      }
   }.observes('model.tier_stalls', 'model.exclusive_stalls', 'merchants'),

   _updateActiveMerchants: function() {
      var self = this;

      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.name'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.stall'));

      var active_merchants = self.get('model.active_merchants');
      var merchants = self._activeMerchants;
      if (!merchants) {
         merchants = {};
         self._activeMerchants = merchants;
      }
      var eMerchants = self.get('merchants');
      if (!eMerchants) {
         self.set('merchants', radiant.map_to_array(self._activeMerchants));
         eMerchants = self.get('merchants');
      }

      self._destroyMerchantTraces(active_merchants);

      if (active_merchants) {
         var components = {
            'stall': {
               'stonehearth:unit_info': {},
               'stonehearth_ace:market_stall': {},
            }
         };

         var removedMerchants = {};
         radiant.each(merchants, function(id, merchant) {
            removedMerchants[id] = true;
         });
         radiant.each(active_merchants, function(id, merchant) {
            delete removedMerchants[id];
            // the individual merchants need to be traced to track their stall usage
            if (self._merchantTraces[id] != null) {
               
            }
            else {
               // name information
               var unit_info = merchant['stonehearth:unit_info'];
               var display_name = self._getDisplayName(merchant);
               var description = unit_info && unit_info.description;
               if (!description) {
                  var catalogData = merchant.uri && App.catalog.getCatalogData(merchant.uri);
                  description = catalogData && catalogData.description;
               }

               var thisMerchant = {
                  id: id,
                  entity: merchant.__self,
                  display_name: display_name,
                  description: i18n.t(catalogData.description, {self: merchant}),
               };
               merchants[id] = thisMerchant;
               eMerchants.pushObject(thisMerchant);
               self._updatePortrait(thisMerchant);

               self._merchantTraces[id] = new StonehearthDataTrace(merchant['stonehearth_ace:merchant'], components)
                  .progress(function (response) {
                     if (self.isDestroyed || self.isDestroying) {
                        return;
                     }
                     
                     var m = self._activeMerchants[id];
                     if (m) {
                        var merchant_data = response;
                        var stallData = self._getStallData(merchant_data) || {};
                        var changedStall = stallData.stall_entity != m.stall_entity;

                        var merchantData = stonehearth_ace.getMerchantData(merchant_data.merchant);

                        Ember.set(m, 'stall_entity', stallData.stall_entity);
                        Ember.set(m, 'stall_uri', stallData.stall_uri);
                        Ember.set(m, 'stall_name', stallData.stall_name);
                        Ember.set(m, 'stall_icon', stallData.stall_icon);
                        Ember.set(m, 'stall_tier', stallData.stall_tier);
                        Ember.set(m, 'has_stall', stallData.has_stall);
                        Ember.set(m, 'is_exclusive', merchantData.is_exclusive);

                        if (changedStall) {
                           if (stallData.stall_entity) {
                              // don't bother if it was changed to null, since handlebars will remove the element
                              self._updateStallPortrait(m);
                           }
                           self._updateAvailableStalls();
                        }
                     }
                  });
            }
         });

         // removed merchants must be removed from the list
         radiant.each(removedMerchants, function(id, merchant) {
            delete merchants[id];
            eMerchants.removeObject(merchant);
         });
      }
   }.observes('model.active_merchants'),

   _getStallData: function(merchant_data) {
      var stall = merchant_data && merchant_data.stall;
      var stall_name = this._getDisplayName(stall);
      var stall_uri = stall && stall.uri;
      var stallCatalogData = stall_uri && App.catalog.getCatalogData(stall_uri);
      var stall_icon = stallCatalogData && stallCatalogData.icon;
      var stallData = stall && stall['stonehearth_ace:market_stall'];

      return {
         stall_entity: stall && stall.__self,
         stall_uri: stall_uri,
         stall_name: stall_name,
         stall_icon: stall_icon,
         stall_tier: stallData && stallData.tier,
         has_stall: stall_icon != null,
      }
   },

   _getDisplayName: function(entity) {
      if (entity) {
         var unit_info = entity['stonehearth:unit_info'];
         var display_name = unit_info && unit_info.display_name;
         if (!display_name) {
            var catalogData = entity.uri && App.catalog.getCatalogData(entity.uri);
            display_name = catalogData && catalogData.display_name;
         }
         return display_name && i18n.t(display_name, {self: entity});
      }
   },

   _updatePortrait: function(merchantData) {
      var self = this;
      Ember.run.scheduleOnce('afterRender', function() {
         if (!self.$()) {
            return;
         }

         var el = self.$('#merchants').find(`[merchant-id='${merchantData.id}']`);
         if (el) {
            // apply portraits and tooltips
            var portrait = el.find('.merchantPortrait');
            var img_url = `url(/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=${merchantData.entity}&cache_buster=${Math.random()})`;
            
            portrait.css('background-image', img_url);

            App.tooltipHelper.createDynamicTooltip(portrait, function() {
               return $(App.tooltipHelper.createTooltip(merchantData.display_name, merchantData.description));
            });
         }
      });
   },

   _updateStallPortrait: function(merchantData) {
      var self = this;
      Ember.run.scheduleOnce('afterRender', function() {
         if (!self.$()) {
            return;
         }

         var el = self.$('#merchants').find(`[merchant-id='${merchantData.id}']`);
         if (el) {
            // apply portraits and tooltips
            portrait = el.find('.stallPortrait');
            img_url = `url(/r/get_portrait/?type=headshot&animation=idle.json&size=256&entity=${merchantData.stall_entity}&cache_buster=${Math.random()})`;
            // var opts = 'cam_x=-20&cam_y=12&cam_z=-30&look_x=1&look_y=_2.1&look_z=2&fov=110&yaw=40&pitch=200';
            // img_url = `url(/r/get_portrait/?type=custom&animation=idle.json&size=256&${opts}&entity=${merchantData.stall_entity}&cache_buster=${Math.random()})`;
            portrait.css('background-image', img_url);

            App.tooltipHelper.createDynamicTooltip(portrait, function() {
               return $(App.tooltipHelper.createTooltip(merchantData.display_name, i18n.t('stonehearth_ace:ui.game.mercantile.active.merchant.working_at_stall', merchantData)));
            });
         }
      });
   },

   _updateStallTooltips: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', function() {
         if (!self.$()) {
            return;
         }

         var stalls = self.$('.availableStall');
         if (stalls) {
            stalls.each(function() {
               var el = $(this);
               var id = el.attr('stall-type-id');
               var stallData = self._availableStalls[id];
               if (stallData) {
                  App.tooltipHelper.createDynamicTooltip(el.find('.stallIcon'), function() {
                     var description = stallData.description;

                     // only include the available bit if there are actually any that could be available
                     if (stallData.total > 0) {
                        description += '<div class="itemAdditionalTip">' +
                           i18n.t('stonehearth_ace:ui.game.mercantile.active.stalls.available',
                           { num: stallData.num, num_class: stallData.num_class }) + "</div>"
                     }

                     return $(App.tooltipHelper.createTooltip(stallData.display_name, description));
                  });
               }
            });
         }
      });
   },

   _setupCategories: function() {
      // load and setup all the categories; then category preferences will do the rest
      var self = this;
      var categories = [];
      radiant.each(stonehearth_ace.getMerchantCategories(), function(category, data) {
         // we need to copy the data to a new object because we'll be setting preference values
         var copiedData = radiant.shallow_copy(data);
         copiedData.icon = copiedData.icon || '/stonehearth_ace/ui/game/mercantile/images/categoryPlaceholder.png';
         categories.push(copiedData);
      });

      categories.sort(function(a, b) {
         if (a.ordinal != null && b.ordinal != null) {
            return a.ordinal - b.ordinal;
         }
         else if (a.ordinal == null) {
            return 1;
         }
         else if (b.ordinal == null) {
            return -1;
         }
      });

      self.set('categories', categories);
      self._updateCategoryPreferences();
   },

   _updateCategoryPreferences: function() {
      var self = this;
      var preferences = self.get('model.category_preferences');
      if (!preferences) {
         return;
      }

      var preferenceTypes = App.constants.mercantile.category_preferences;
      var categories = self.get('categories');

      radiant.each(categories, function(_, category) {
         var preference = preferences[category.category];
         if (preference == null) {
            preference = preferenceTypes.ENABLED;
         }
         Ember.set(category, 'preference', preference);
      });

      self._updateNumPreferences();
   }.observes('model.category_preferences'),

   _updateNumPreferences: function() {
      var self = this;
      var maxDisables = self.get('model.max_disables');
      var maxEncourages = self.get('model.max_encourages');
      var numDisables = self.get('model.num_disables');
      var numEncourages = self.get('model.num_encourages');
      var categories = self.get('categories');
      if (maxDisables == null || maxEncourages == null || numDisables == null || numEncourages == null || categories == null) {
         return;
      }

      var preferenceTypes = App.constants.mercantile.category_preferences;
      radiant.each(categories, function(_, category) {
         Ember.set(category, 'isDisabled', category.preference == preferenceTypes.DISABLED);
         Ember.set(category, 'disableEnabled', category.preference != preferenceTypes.DISABLED && numDisables < maxDisables);
         Ember.set(category, 'isEnabled', category.preference == preferenceTypes.ENABLED);
         Ember.set(category, 'enableEnabled', category.preference != preferenceTypes.ENABLED);
         Ember.set(category, 'isEncouraged', category.preference == preferenceTypes.ENCOURAGED);
         Ember.set(category, 'encourageEnabled', category.preference != preferenceTypes.ENCOURAGED && numEncourages < maxEncourages);
      });
   }.observes('model.max_disables', 'model.max_encourages'),

   actions: {
      disableCategory: function(category) {
         if (this.$('#categoriesTable').find(`[category='${category}'] .enabled:not(.selected) .disableCategory`).length > 0) {
            radiant.call_obj(_playerMercantileControllerUri, 'set_category_preference_command', category, App.constants.mercantile.category_preferences.DISABLED);
         }
      },

      enableCategory: function(category) {
         if (this.$('#categoriesTable').find(`[category='${category}'] .enabled:not(.selected) .enableCategory`).length > 0) {
            radiant.call_obj(_playerMercantileControllerUri, 'set_category_preference_command', category, App.constants.mercantile.category_preferences.ENABLED);
         }
      },

      encourageCategory: function(category) {
         if (this.$('#categoriesTable').find(`[category='${category}'] .enabled:not(.selected) .encourageCategory`).length > 0) {
            radiant.call_obj(_playerMercantileControllerUri, 'set_category_preference_command', category, App.constants.mercantile.category_preferences.ENCOURAGED);
         }
      },
   }
});
