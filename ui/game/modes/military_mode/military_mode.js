App.AceMilitaryModeView = App.View.extend({
   templateName: 'militaryMode',
   closeOnEsc: true,
   modal: false,

   patrolBannersTraceStructure: {
      'ordered_banners_by_party': {
         '*': {   // indexed by party id
            '*': {}
         }
      },
      'patrol_banners': {
         '*': {
            'stonehearth_ace:patrol_banner': {}
         }
      }
   },

   selectedParty: 'party_1',
   selectedBanner: null,
   patrolBannersArray: [],

   init: function() {
      this._super();
      var self = this;

      self.allPartyBanners = {};

      $(top).on('mode_changed', function(_, mode) {
         self._onStateChanged();
      });
   },

   _onStateChanged: function() {
      var self = this;
      if (App.getGameMode() != 'military') {
         self.hide();
      }
   },

   dismiss: function () {
      this.hide();
   },

   willDestroyElement: function() {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');

      self.$().off('click');

      self._super();
   },

   didInsertElement: function () {
      var self = this;
      self._super();

      self.$().draggable({ handle: '.title' });

      self.$().on('click', '.partyTab', function() {
         var partyId = $(this).attr('partyId');
   
         self.$('.partyTab').removeClass('active');
         $(this).addClass('active');

         self.setSelectedParty(partyId);
      });

      self.$().on('click', 'tr', function() {
         if (!$(this).hasClass("ignoreClick")) {
            self._selectRow($(this), true);
         }
      });

      self.$().on( 'click', '.window .title .closeDivButton', function() {
         self.hide();
      });

      radiant.call('stonehearth_ace:get_patrol_banners_command')
      .done(function (response) {
         if (self.isDestroying || self.isDestroyed) {
            return;
         }
         var patrolBanners = response.patrol_banners;
         if (patrolBanners) {
            self.radiantTrace = new RadiantTrace();
            self.radiantTrace.traceUri(patrolBanners, self.patrolBannersTraceStructure)
            .progress(function (data) {
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }
               self._updateData(data);
            });
         }
      });

      self.hide();
   },

   _onEntitySelected: function(e) {
      var self = this;

      // when the selected entity changes, select the correct entry if it's a party banner in the currently shown party
      var found = false;
      radiant.each(self.allPartyBanners, function(party, banners) {
         if (found) return;
         radiant.each(banners, function(id, banner) {
            if (found) return;
            if (banner.entity == e.selected_entity) {
               found = true;
               self.selectedEntity = banner;
               self.selectedEntityId = banner.id;
            }
         });
      });

      if (!found) {
         self.selectedEntity = null;
         self.selectedEntityId = null;
      }

      self._selectRowByEntityId(self.selectedEntityId);
   },

   setSelectedParty: function(partyId) {
      var self = this;
      self.set('selectedParty', partyId);
   },

   _updateData: function(data) {
      var self = this;

      var partyBanners = {};
      radiant.each(data.patrol_banners, function(id, banner) {
         var pb = banner['stonehearth_ace:patrol_banner'];
         var catalogData = App.catalog.getCatalogData(banner.uri);
         var party = pb.party_id;

         if (!partyBanners[party]) {
            partyBanners[party] = {};
         }
         
         partyBanners[party][id] = {
            'id': id,
            'entity': banner.__self,
            'partyId': party,
            'prevBanner': pb.prev_banner,
            'nextBanner': pb.next_banner,
            'distance': pb.distance_to_next_banner && Math.round(pb.distance_to_next_banner),
            'name': catalogData.display_name,
            'icon': catalogData.icon
         };
      });

      self.allPartyBanners = partyBanners;

      var ordered = {};
      radiant.each(data.ordered_banners_by_party, function(party, banners) {
         ordered[party] = [];
         radiant.each(banners, function(_, banner) {
            ordered[party].push(banner.object_id);
         });
      });

      self.orderedPartyBanners = ordered;

      self._updateView();
   },

   _updateView: function() {
      var self = this;
      var party = self.get('selectedParty');

      var banners = [];
      radiant.each(self.orderedPartyBanners[party], function(_, id) {
         var entity = self.allPartyBanners[party][id];
         banners.push({
            'id': id,
            'entity': entity.entity,
            'nextBanner': entity.nextBanner,
            'distance': entity.distance,
            'name': entity.name,
            'icon': entity.icon
         });
      });
      self.set('patrolBannersArray', banners);

      Ember.run.scheduleOnce('afterRender', function() {
         var selectedEntityId = self.selectedEntityId;
         if (selectedEntityId) {
            self._selectRowByEntityId(selectedEntityId);
         }
      });
   }.observes('selectedParty'),

   _selectRowByEntityId: function(entityId) {
      // find the row to select and pass that to the _selectRow function
      var self = this;
      var row = entityId && self.$('[data-attr="'+entityId+'"]');
      self._selectRow(row, false);
   },

   _selectRow: function(row, userClicked) {
      var self = this;

      if (row && row.length > 0) {
         var entityId = row.attr('data-attr');
         var entity = self.allPartyBanners[self.get('selectedParty')][entityId];
         self.set('selectedBanner', entity);
         
         var selected = row.hasClass('selected'); // Is this row already selected?
         if (!selected) {
            row.parent().children().removeClass('selected'); // Unselect everything in the parent view
            row.addClass('selected');

            if (userClicked) {
               radiant.call('stonehearth:select_entity', entity.entity);
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });  
            }
         }
      }
      else {
         self.$('#tasksListTable').find('tr').removeClass('selected'); // Unselect everything in the parent view
         self.set('selectedBanner', null);
      }
   },

   actions: {
      clearAllBanners: function() {
         var self = this;
         var selectedParty = self.get('selectedParty');
         radiant.call('stonehearth_ace:remove_patrol_banners_by_party_command', selectedParty)
      },

      createNewBanner: function(selectedParty, prevBanner, nextBanner) {
         var self = this;
         
         if (!selectedParty) {
            selectedParty = self.get('selectedParty');
            var selectedBanner = self.get('selectedBanner');
            var patrolBanners = self.get('patrolBannersArray');
            
            if (selectedBanner) {
               prevBanner = selectedBanner.entity;
               nextBanner = selectedBanner.nextBanner;
            }
            else if (patrolBanners.length > 0) {
               prevBanner = patrolBanners[patrolBanners.length - 1].entity;
               nextBanner = patrolBanners[0].entity;
            }
         }

         radiant.call('stonehearth_ace:add_patrol_banner_command', selectedParty, prevBanner, nextBanner)
         .done(function(r) {
            if (r.new_banner) {
               self.send('createNewBanner', selectedParty, r.new_banner);
            }
         });
      },

      swapBannerWithPrev: function() {
         var self = this;
         var selectedBanner = self.get('selectedBanner');
         if (selectedBanner && selectedBanner.prevBanner) {
            radiant.call('stonehearth_ace:swap_patrol_banners_order_command', selectedBanner.prevBanner);
         }
      },

      swapBannerWithNext: function() {
         var self = this;
         var selectedBanner = self.get('selectedBanner');
         if (selectedBanner) {
            radiant.call('stonehearth_ace:swap_patrol_banners_order_command', selectedBanner.entity);
         }
      }
   }
});
