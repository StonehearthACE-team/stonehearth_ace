var StonehearthBulletinBoard;

(function () {
   StonehearthBulletinBoard = SimpleClass.extend({

      components: {
         "bulletins" : {
            "*" : {
               "i18n_data" : {
                  "boss" : {
                     "stonehearth:unit_info": {}
                  },
                  "entity" : {
                     "stonehearth:unit_info": {},
                     "stonehearth:job" : {}
                  }
               }
            }
         },
         "alerts" : {
            "*" : {
               "i18n_data" : {
                  "boss" : {
                     "stonehearth:unit_info": {}
                  },
                  "entity" : {
                     "stonehearth:unit_info": {},
                     "stonehearth:job" : {}
                  }
               }
            }
         }
      },

      init: function(initCompletedDeferred) {
         var self = this;
         this._initCompleteDeferred = initCompletedDeferred;

         self._lastViewedBulletinId = -1;
         self._lastViewedAlertId = -1;

         radiant.call('stonehearth:get_bulletin_board_datastore')
            .done(function(response) {
               self._bulletinBoardUri = response.bulletin_board;
               self._createTrace();
            });

         self._orderedBulletins = Ember.A();
         self._alertBulletins = Ember.A();

         self._unclosedBulletinDialogViews = {};
      },

      _ensureContainer: function() {
         var self = this;
         if (self.notificationContainerView) {
            return true;
         }
         if (!App.gameView) {
            return false;
         }
         self.notificationContainerView = App.gameView.addView(App.StonehearthNotificationContainer);
         return !!self.notificationContainerView;
      },

      _createTrace: function() {
         var self = this;

         self._radiantTrace = new RadiantTrace();
         self._bulletinBoardTrace = self._radiantTrace.traceUri(self._bulletinBoardUri, self.components)
            .progress(function(bulletinBoard) {
               if (!self._ensureContainer()) {
                  return;
               }

               if (bulletinBoard.bulletins) {
                  self._bulletins = bulletinBoard.bulletins;
                  self._updateBulletinList(self._bulletins, self._orderedBulletins, 'bulletins');
                  self._tryShowNextBulletin();
               }
               if (bulletinBoard.alerts) {
                  self._alerts = bulletinBoard.alerts;
                  self._updateBulletinList(self._alerts, self._alertBulletins, 'alerts');
                  self._tryShowNextAlert();
               }
            });

         this._initCompleteDeferred.resolve();
      },

      _destroyMissingView: function(viewName) {
         // Remove the view referenced by `viewName` if it is no longer in the model
         var self = this;
         var view = self[viewName];
         if (!view) {
            return;
         }
         var id = view.get('model.id');
         if (!id) {
            return;
         }
         if (!self._bulletins[id]) {
            self[viewName] = null;
            view.destroy();
         }
      },

      _updateBulletinList: function(bulletin_map, bulletin_list, type, sort_fn) {
         var self = this;
         var list = radiant.map_to_array(bulletin_map);

         sort_fn = sort_fn || function (a, b) {
            return a.id - b.id;
         };

         list.sort(sort_fn);

         bulletin_list.clear();
         bulletin_list.pushObjects(list);

         self._destroyMissingView('_bulletinDialogView');
         if (self.notificationContainerView) {
            self.notificationContainerView.destroyMissingViews(bulletin_map, type);
         }
      },

      _tryShowNextBulletin: function() {
         var self = this;

         if (self.notificationContainerView.isShowingBulletinNotification() || self._bulletinDialogView) {
            return;
         }

         var bulletins = self._orderedBulletins;
         var numBulletins = bulletins.length;

         for (var i = 0; i < numBulletins; i++) {
            var bulletin = bulletins[i];
            //The bulletin keeps track of whether it's been shown, but this updates
            //too late to be in perfect sync with the UI. So keep track of what was
            //shown this session, but on load, use the shown to prevent all the shown bulletins
            //from appearing again. This seems...redundant, happy to take suggestions.
            if (!bulletin.shown && (bulletin.id > self._lastViewedBulletinId)) {
               if (bulletin.data.skip_notification) {
                  self._lastViewedBulletinId = bulletin.id
                  self.showDialogView(bulletin);
               } else {
                  self.showNotificationView(bulletin);
               }
               radiant.call('stonehearth:mark_bulletin_shown', bulletin.id);
               return;
            }
         }
      },

      _tryShowNextAlert: function() {
         var self = this;
         var alerts = self._alertBulletins;
         var numAlerts = alerts.length;

         for (var i = 0; i < numAlerts; i++) {
            var alert = alerts[i];
            if (!alert.shown && (alert.id > self._lastViewedAlertId)) {
               self.showAlertView(alert);
               radiant.call('stonehearth:mark_bulletin_shown', alert.id);
               return;
            }
         }
      },

      showNotificationView: function(bulletin) {
         var self = this;
         if (!self._ensureContainer()) {
            return;
         }
         self.notificationContainerView.addNotificationView(bulletin);
         self._lastViewedBulletinId = bulletin.id;
      },

      showAlertView: function(alert) {
         var self = this;
         if (!self._ensureContainer()) {
            return;
         }
         self.notificationContainerView.addNotificationView(alert);
         self._lastViewedAlertId = alert.id;
      },

      showDialogView: function(bulletin) {
         var self = this;
         var bulletinId = bulletin.id;
         var dialogBulletinViewId = (self._bulletinDialogView && self._bulletinDialogView.get('model')) ? self._bulletinDialogView.get('model.id') : '';
         if (self._bulletinDialogView && dialogBulletinViewId == bulletinId) {
            // Trying to display the current dialog! Just hide ourselves because the current
            // dialog is probably under us.
            self.hideListView();
            return;
         }

         // If we are showing a notification for the requested bulletin, destroy that notification.
         self.notificationContainerView.removeNotificationView(bulletin);

         if (self._bulletinDialogView && !self._bulletinDialogView.isDestroyed) {
            // If we are already showing a dialog, hide that dialog and store off that it's hidden.
            if (dialogBulletinViewId != '') {
               if (self._bulletinDialogView.SHOULD_DESTROY_ON_HIDE_DIALOG) {
                  self._bulletinDialogView.hideByDestroying();
               } else {
                  self._unclosedBulletinDialogViews[dialogBulletinViewId] = self._bulletinDialogView;
                  self._bulletinDialogView.hide();
               }
            }

            self._bulletinDialogView = null;
         }

         if (self._unclosedBulletinDialogViews[bulletinId]) {
            // If the requested bulletin has already been shown and is hiding. reshow it/
            self._bulletinDialogView = self._unclosedBulletinDialogViews[bulletinId];
            self._bulletinDialogView.show();
         } else {
            // If the requested bulletin hasn't been created, create the bulletin.
            var dialogViewName = bulletin.ui_view;
            if (dialogViewName && App[dialogViewName]) {
               self._bulletinDialogView = App.gameView.addView(App[dialogViewName], { uri: bulletin.__self });
            } else {
               self.markBulletinHandled(bulletin);
            }
         }

         self.hideListView();
      },

      closeDialogView: function(filter_fn) {
         var self = this;
         var dialogBulletinViewModel = self._bulletinDialogView && !self._bulletinDialogView.isDestroyed && self._bulletinDialogView.get('model');
         if (dialogBulletinViewModel) {
            if (!filter_fn || filter_fn(dialogBulletinViewModel)) {
               var id = dialogBulletinViewModel.id;
               if (self._bulletinDialogView.SHOULD_DESTROY_ON_HIDE_DIALOG) {
                  self._bulletinDialogView.hideByDestroying();
               } else {
                  if (id) {
                     self._unclosedBulletinDialogViews[id] = self._bulletinDialogView;
                  }
                  self._bulletinDialogView.hide();
               }

               // also mark the bulletin as handled and remove any notification for it
               if (id) {
                  self.notificationContainerView.removeNotificationView(self._bulletins[id]);
                  self.markBulletinHandled(self._bulletins[id]);
               }

               self._bulletinDialogView = null;
            }
         }
      },

      tryShowBulletin: function(bulletin) {
         var self = this;

         if (self.notificationContainerView.isShowingBulletinNotification()) {
            return;
         }

         if (bulletin && bulletin.id) {
            self._lastViewedBulletinId = bulletin.id
            self.showDialogView(bulletin);

            if (!bulletin.shown) {
               radiant.call('stonehearth:mark_bulletin_shown', bulletin.id);
            }
         }
      },

      toggleListView: function() {
         var self = this;

         // toggle the view
         if (!self._bulletinListView || self._bulletinListView.isDestroyed) {
            self._bulletinListView = App.gameView.addView(App.StonehearthBulletinList, {
                                                            context: {
                                                               bulletins : self._orderedBulletins,
                                                               alerts : self._alertBulletins
                                                            }
                                                         });
         } else {
            self.hideListView();
         }
      },

      hideListView: function() {
         var self = this;
         if (self._bulletinListView != null && !self._bulletinListView.isDestroyed) {
            self._bulletinListView.destroy();
         }
         self._bulletinListView = null;
      },

      zoomToLocation: function(bulletin) {
         var entity = bulletin && bulletin.data && bulletin.data.zoom_to_entity;

         if (entity) {
            radiant.call('stonehearth:camera_look_at_entity', entity);
            radiant.call('stonehearth:select_entity', entity);
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         }
      },

      onNotificationViewDestroyed: function(bulletin) {
         var self = this;
         self._tryShowNextBulletin();
      },

      onAlertViewDestroyed: function(alert) {
         var self = this;
         self._tryShowNextAlert();
      },

      onDialogViewDestroyed: function(bulletin) {
         var self = this;
         self._unclosedBulletinDialogViews[bulletin.id] = null;

         self._bulletinDialogView = null;
         self._tryShowNextBulletin();
      },

      recreateDialogView: function(bulletin) {
         var self = this;
         if (self._bulletinDialogView) {
            var oldDialogView = self._bulletinDialogView;
            // defer the destruction of the old dialog until after render
            // to prevent flickering between views...
            Ember.run.scheduleOnce('afterRender', this, function() {
               oldDialogView.destroy();
            });
            self._bulletinDialogView = null;
            self._unclosedBulletinDialogViews[bulletin.id] = null;
            self.showDialogView(bulletin);
         }
      },

      markBulletinHandled: function(bulletin) {
         var self = this;
         var bulletins = self._orderedBulletins;
         var alerts = self._alertBulletins;

         if (!bulletin) return;

         // if this is the last bulletin, auto close the list view
         if (bulletins.length + alerts.length <= 1) {
            var lastId = null;
            if (bulletins.length > 0) {
               lastId = bulletins[0].id;
            }
            if (alerts.length > 0) {
               lastId = alerts[0].id;
            }
            var isLastBulletin = lastId !== null && lastId === bulletin.id;
            var isEmpty = bulletins.length == 0 && alerts.length == 0;
            if (isLastBulletin || isEmpty) {
               self.hideListView();
            }
         }

         if (bulletin.close_on_handle) {
            radiant.call('stonehearth:remove_bulletin', bulletin.id);
         }
      },

      // unused
      // used to remove flicker when updating the bulletin list
      // side effect is that the old elements in the list will not update,
      //    since the ListView is not (yet) tracking them individually
      _updateOrderedBulletins: function(updatedList) {
         var self = this;
         var orderedBulletins = self._orderedBulletins;
         var oldLength = orderedBulletins.length;
         var newLength = updatedList.length;
         var shortestLength = Math.min(oldLength, newLength);
         var i, j;

         // find the first index that differs
         for (i = 0; i < shortestLength; i++) {
            if (orderedBulletins[i].id != updatedList[i].id) {
               break;
            }
         }

         // delete everything after that index
         for (j = i; j < oldLength; j++) {
            orderedBulletins.popObject();
         }

         // copy the remaining items from the updatedList
         for (j = i; j < newLength; j++) {
            orderedBulletins.pushObject(updatedList[j]);
         }

         for (i = 0; i < newLength; i++) {
            if (orderedBulletins[i] != updatedList[i]) {
               console.log('Error: orderedBulletins is not correct!')
               break;
            }
         }
      },

      getTrace: function() {
         return this._bulletinBoardTrace;
      }
   });
})();
