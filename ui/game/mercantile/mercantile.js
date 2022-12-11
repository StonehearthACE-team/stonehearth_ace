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
      radiant.call_obj('stonehearth_ace.mercantile', 'get_player_controller_command')
         .done(function (response) {
            self.set('uri', response.controller);
         });
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

      self.$('#merchants').on('click', '.shop', function() {
         var merchantDiv = $(this).parent();
         if (merchantDiv) {
            var id = merchantDiv.attr('merchant-id');
            var merchant = id && self._activeMerchants[id];
            if (merchant) {
               $(top).trigger('stonehearth_ace_show_shop', {entity: merchant});
            }
         }
      });
      
      self.$('#merchants').on('click', '.stall', function() {
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

      self.$('#merchants').on('click', '.portrait', function() {
         var merchantDiv = $(this).parent().parent();
         if (merchantDiv) {
            var id = merchantDiv.attr('merchant-id');
            var merchant = id && self._activeMerchants[id];
            if (merchant) {
               radiant.call('stonehearth:select_entity', merchant.entity);
               radiant.call('stonehearth:camera_look_at_entity', merchant.entity);
            }
         }
      });
   },

   _updateNumMerchants: function() {
      var self = this;
      var maxDailyMerchants = self.get('model.max_daily_merchants');
      var limitedByStalls = self.get('model.limited_by_stalls');
      var numStalls = self.get('model.num_stalls');
      var numMerchants = null;

      if (maxDailyMerchants != null) {
         if (maxDailyMerchants <= 1) {
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
      }

      self.set('numMerchants', numMerchants);
   }.observes('model.max_daily_merchants', 'model.limited_by_stalls', 'model.num_stalls'),

   _updateActiveMerchants: function() {
      var self = this;

      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.name'));
      App.tooltipHelper.removeDynamicTooltip(self.$('#merchants.stall'));

      var active_merchants = self.get('model.active_merchants');
      var merchants = {};
      var merchantsChanged = self._destroyMerchantTraces(active_merchants);

      if (active_merchants) {
         var components = {
            // 'stonehearth_ace:merchant': {
               'stall': {
                  'stonehearth:unit_info': {},
               }
            // },
            // 'stonehearth:unit_info': {},
         };

         radiant.each(active_merchants, function(id, merchant) {
            // this is great for most of the data, but the individual merchants need to be traced to track their stall usage
            if (self._merchantTraces[id] != null) {
               merchants[id] = self._activeMerchants[id];
            }
            else {
               merchantsChanged = true;

               // name information
               var unit_info = merchant['stonehearth:unit_info'];
               var display_name = self._getDisplayName(merchant);
               var description = unit_info && unit_info.description;
               if (!description) {
                  var catalogData = merchant.uri && App.catalog.getCatalogData(merchant.uri);
                  if (catalogData) {
                     description = i18n.t(catalogData.description, {self: merchant});
                  }
               }

               merchants[id] = {
                  id: id,
                  entity: merchant.__self,
                  display_name: display_name,
                  description: description,
               };

               self._merchantTraces[id] = new StonehearthDataTrace(merchant['stonehearth_ace:merchant'], components)
                  .progress(function (response) {
                     if (self.isDestroyed || self.isDestroying) {
                        return;
                     }
                     
                     var thisMerchant = merchants[id];
                     var merchant_data = response; //['stonehearth_ace:merchant'];
                     var stallData = self._getStallData(merchant_data) || {};
                     Ember.set(thisMerchant, 'stall_entity', stallData.stall_entity);
                     Ember.set(thisMerchant, 'stall_name', stallData.stall_name);
                     Ember.set(thisMerchant, 'stall_icon', stallData.stall_icon);
                     Ember.set(thisMerchant, 'has_stall', stallData.has_stall);
                  });
            }
         });
      }

      if (merchantsChanged) {
         self._activeMerchants = merchants;

         // use the entire object so we have a simpler time updating for stall changes
         var merchantArr = [];
         radiant.each(merchants, function(_, merchant) {
            merchantArr.push(merchant);
         });
         self.set('merchants', merchantArr);
      }
   }.observes('model.active_merchants'),

   _getStallData: function(merchant_data) {
      var stall = merchant_data && merchant_data.stall;
      var stall_name = this._getDisplayName(stall);
      var stallCatalogData = stall && App.catalog.getCatalogData(stall.uri);
      var stall_icon = stallCatalogData && stallCatalogData.icon;
      return {
         stall_entity: stall && stall.__self,
         stall_name: stall_name,
         stall_icon: stall_icon,
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

   _updatePortraits: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', function() {
         if (!self.$()) {
            return;
         }

         var merchants = self.$('.merchant');
         if (merchants) {
            merchants.each(function() {
               var el = $(this);
               var id = el.attr('merchant-id');
               var merchantData = self._activeMerchants[parseInt(id)];
               if (merchantData) {
                  // apply portrait and tooltip
                  var img_url = `url(/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=${merchantData.entity}&cache_buster=${Math.random()})`;
                  el.find('.portrait').css('background-image', img_url);

                  App.tooltipHelper.createDynamicTooltip(el.find('.portrait'), function() {
                     return $(App.tooltipHelper.createTooltip(merchantData.display_name, merchantData.description));
                  });

                  App.tooltipHelper.createDynamicTooltip(el.find('.stall'), function() {
                     return $(App.tooltipHelper.createTooltip(merchantData.display_name, i18n.t('stonehearth_ace:ui.game.mercantile.active.merchant.working_at_stall', merchantData)));
                  });
               }
            });
         }
      });
   }.observes('merchants'),

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
});

