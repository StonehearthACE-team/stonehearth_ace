var getOctile = function(percentage) {
   // return 0-8
   return Math.round(percentage * 8);
};

var citizensLastSortKey = 'job';
var citizensLastSortDirection = 1;

App.StonehearthCitizensView = App.View.extend({
   templateName: 'citizens',
   uriProperty: 'model',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,
   skipInvisibleUpdates: true,
   hideOnCreate: false,
   components: {
      "citizens" : {
         "*": {
            "stonehearth:unit_info": {},
            "stonehearth:commands": {},
            "stonehearth:ai": {
               "status_text_data": {}
            },
            "stonehearth:job": {
               'curr_job_controller' : {}
            },
            "stonehearth:crafter": {
               "workshop": {}
            },
            "stonehearth:attributes": {},
            "stonehearth:work_order": {},
            "stonehearth:happiness": {},
            'stonehearth:traits' : {
               'traits': {
                  '*' : {}
               }
            },
            // ACE: added tracking for health/status
            'stonehearth:expendable_resources' : {},
            'stonehearth:incapacitation' : {
               'sm': {}
            },
         }
      },
      "work_orders": {}
   },

   stats: [
      'mind',
      'body',
      'spirit',
      'health',
      'happiness'
   ],

   work_orders: [
      'haul',
      'mine',
      'gather',
      'build',
      'job'
   ],

   init: function() {
      var self = this;
      this._super();

      radiant.call('stonehearth:get_population')
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            self._populationUri = response.population;
            self.set('uri', self._populationUri);
         });
   },

   willDestroyElement: function() {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');

      self.$().off('click');

      App.presenceClient.removeChangeCallback('citizens_menu');

      if (self._playerPickerView) {
         self._playerPickerView.destroy();
         self._playerPickerView = null;
      }

      this._super();
   },

   dismiss: function () {
      this.hide();
   },

   hide: function () {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }
      this._super();
   },

   show: function () {
      this._super();
      App.stonehearth.modalStack.push(this);
   },

   _onVisibilityChanged: function() {
      var self = this;
      if (self._firstTime) {
         self._firstTime = null;
         return;
      }

      if (self.get('isVisible')) {
         // tell each row to update
         self._containerView.forEach(function(item, index, enumerable) {
            item.updateRow();
         });
      }
   }.observes('isVisible'),

   didInsertElement: function() {
      var self = this;
      self._firstTime = true;
      self._super();

      this.$().draggable({ handle: '.title' });

      var changeCallback = function(presenceData, isMultiplayer) {
         if (self.isDestroying || self.isDestroyed) {
            return;
         }

         self.set('isMultiplayer', isMultiplayer);
      }

      App.presenceClient.addChangeCallback('citizens_menu', changeCallback, true);

      radiant.each(self.stats, function (i, stat) {
         App.tooltipHelper.createDynamicTooltip(self.$('.' + stat), function () {
            return $(App.tooltipHelper.getTooltip(stat));
         });
      });

      radiant.each(self.work_orders, function (i, work_order) {
         App.tooltipHelper.createDynamicTooltip(self.$('.work_' + work_order), function () {
            var title = i18n.t(`stonehearth_ace:ui.game.citizens.work_order_tooltips.${work_order}`);
            var description = i18n.t(`stonehearth_ace:ui.game.citizens.work_order_tooltips.${work_order}_description`);
            return $(App.tooltipHelper.createTooltip(title, description));
         });
      });

      App.tooltipHelper.createDynamicTooltip($('#expStat .bar'));
      App.tooltipHelper.createDynamicTooltip($('.suspendButton'));
      App.tooltipHelper.createDynamicTooltip($('.listTitle'));
      App.tooltipHelper.createDynamicTooltip($('#changeAllWorkingFor'));

      self.$().on('click', ':checkbox[workOrder]', function() {
         var checked = $(this).is(':checked');
         var workOrder = $(this).attr('workOrder');
         var citizenId = $(this).attr('citizenId');
         radiant.call_obj(self._populationUri, 'change_work_order_command', workOrder, parseInt(citizenId), checked);
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });
      });

      self.$().on('click', '.moodIcon', function() {
         self._moodIconClicked = true;
      });

      self.$().on('click', '.listTitle', function() {
         var newSortKey = $(this).attr('data-sort-key');
         if (newSortKey) {
            if (newSortKey == self.get('sortKey')) {
               self.set('sortDirection', -(self.get('sortDirection') || 1));
            } else {
               self.set('sortKey', newSortKey);
               self.set('sortDirection', 1);
            }

            citizensLastSortKey = newSortKey;
            citizensLastSortDirection = self.get('sortDirection');
         }
      });

      if (self.hideOnCreate) {
         self.hide();
      }
   },

   citizenChanged: function (citizen, citizenId) {
      var self = this;
      var existingSelected = self.get('selected');
      if (existingSelected && citizen && existingSelected.__self == citizen.__self) {
         self.setSelectedCitizen(citizen, citizenId, false);
      }
   },

   _updateCitizensArray: function() {
      var self = this;
      var citizensMap = self.get('model.citizens');
      delete citizensMap.size;
      if (self._containerView) {
         // Construct and manage citizen row views manually
         self._containerView.updateRows(citizensMap);
      }
   }.observes('model.citizens'),

   _onSortChanged: function() {
      var self = this;
      var citizensMap = self.get('model.citizens');
      delete citizensMap.size;
      if (self._containerView) {
         self._containerView.updateRows(citizensMap, true);
      }
   }.observes('sortKey', 'sortDirection'),

   setSelectedCitizen: function(citizen, citizenId, userClicked) {
      var self = this;
      var existingSelected = self.get('selected');
      if (citizen) {
         var uri = citizen.__self;
         var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
         self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');

         if (userClicked) { // keep zooming to the person even if they are already selected
            radiant.call('stonehearth:camera_look_at_entity', uri);
            radiant.call('stonehearth:select_entity', uri);
            if (self._moodIconClicked) {
               App.stonehearthClient.showCharacterSheet(uri);
               self._moodIconClicked = false;
            }
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         }
      } else {
         self.$('#selectedPortrait').css('background-image', 'url()');
      }

      self.set('selected', citizen);
   },

   setCitizenRowContainerView: function(containerView) {
      this._containerView = containerView;
   },

   _updateAttributes: function() {
      var self = this;
      var existingSelected = self.get('selected');

      if (existingSelected) {
         var expData = radiant.getExpPercentAndLabel(self.get('selected.stonehearth:job'));
         var expPercent = expData.percent;
         var expLabel = expData.label;

         self.set('exp_bar_style', 'width: ' + expPercent + '%');
         self.set('exp_bar_label', expLabel);
      }
   }.observes('selected.stonehearth:job.curr_job_controller'),

   _buildTraitsArray: function() {
      var self = this;
      var traits = [];
      var traitMap = self.get('selected.stonehearth:traits.traits');

      if (traitMap) {
         traits = radiant.map_to_array(traitMap);
         traits.sort(function(a, b){
            var aUri = a.uri;
            var bUri = b.uri;
            var n = aUri.localeCompare(bUri);
            return n;
         });
      }

      self.set('traits', traits);
   }.observes('selected.stonehearth:traits'),

   openPlayerPickerView: function(citizenData) {
      var self =  this;
      if (self._playerPickerView) {
         self._playerPickerView.destroy();
      }

      self._playerPickerView = App.gameView.addView(App.StonehearthPlayerPickerView, {
         selectedPlayerId: citizenData ? citizenData.get('stonehearth:work_order.working_for') : null,
         selectedCb: function(playerId) {
            if (radiant.isNonEmptyString(playerId)) {
               if (!citizenData) {
                  // Set working for for all citizens if an individual citizen was not passed as an argument
                  var citizensMap = self.get('model.citizens');
                  radiant.each(citizensMap, function(citizenId, citizenData) {
                     radiant.call('stonehearth:set_working_for_player_id', citizenData.__self, playerId);
                  });
               } else {
                  radiant.call('stonehearth:set_working_for_player_id', citizenData.__self, playerId);
               }
            }
            self._playerPickerView = null;
         }
      });
   },

   // ACE: changed to only show commands that are marked as visible_in_citizens_view
   selected_commands: function() {
      var filter_fn = function(uri, data) {
         if (data.visible_in_citizens_view === false) {
            return false;
         }
      };
      var commands = radiant.map_to_array(this.get('selected.stonehearth:commands.commands'), filter_fn);
      commands.sort(function(a, b){
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      });
      return commands;
   }.property('selected.stonehearth:commands.commands'),

   actions: {
      doCommand: function(command, citizen_data) {
         var citizen_id = citizen_data.__self;
         var player_id = citizen_data.player_id;
         App.stonehearthClient.doCommand(citizen_id, player_id, command);
      },
      showPromotionTree: function(citizen) {
         // ACE: also pass along job index
         App.stonehearthClient.showPromotionTree(citizen.__self, citizen['stonehearth:job'].job_index);
      },
      changeWorkingFor: function(citizenData) {
         this.openPlayerPickerView(citizenData);
      },
      changeAllWorkingFor: function(citizenData) {
         this.openPlayerPickerView();
      },
      suspendToggle: function(workOrder) {
         var self = this;
         var suspendedWorkOrders = self.get('model.suspended_work_orders');
         if (!suspendedWorkOrders) {
            return;
         }
         var isSuspended = !suspendedWorkOrders[workOrder];
         radiant.call_obj(self._populationUri, 'set_work_order_suspend_command', workOrder, isSuspended);
      }
   }
});

App.StonehearthCitizenTasksRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'citizenTasksRow',
   uriProperty: 'model',

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:commands": {},
      "stonehearth:ai": {
         "status_text_data": {}

      },
      "stonehearth:job": {
         'curr_job_controller' : {}
      },
      "stonehearth:crafter": {
         "workshop": {}
      },
      "stonehearth:attributes": {},
      "stonehearth:work_order": {},
      'stonehearth:traits' : {
         'traits': {
            '*' : {}
         }
      },
      // ACE: added tracking for health/status
      'stonehearth:attributes' : {},
      'stonehearth:expendable_resources' : {},
      'stonehearth:incapacitation' : {
         'sm': {}
      },
   },

   didInsertElement: function() {
      this._super();
      var self = this;
      self._jobDisplayName = null;

      radiant.each(self.taskView.stats, function(i, stat) {
         var statDiv = self.$('.' + stat);
         if (statDiv) {
            App.tooltipHelper.createDynamicTooltip(statDiv, function () {
               return $(App.tooltipHelper.getTooltip(stat));
            });
         }
      });

      self.$()[0].setAttribute('data-citizen-id', self.get('citizenId'));

      App.tooltipHelper.createDynamicTooltip($('#changeWorkingFor'));

      self._update();
      self._onWorkingForChanged();
      self._updateMoodTooltip();
      self._updateDescriptionTooltip();
      self._onJobChanged();

      // ACE: listen for entity selection and select the corresponding row
      // use a specific function for this rather than a namespace, because we want it then remove the event just for this row
      self.selection_event_func = function(_, e) {
         self._onEntitySelected(e);
      }

      $(top).on('radiant_selection_changed', self.selection_event_func);
   },

   willDestroyElement: function() {
      var self = this;

      $(top).off('radiant_selection_changed', self.selection_event_func);
      self.$().find('.tooltipstered').tooltipster('destroy');

      if (self._playerPickerView) {
         self._playerPickerView.destroy();
         self._playerPickerView = null;
      }

      if (self._moodTrace) {
         self._moodTrace.destroy();
         self._moodTrace = null;
      }

      if (self._containerView) {
         self._containerView.destroy();
         self._containerView = null;
      }

      self._super();
   },

   _onEntitySelected: function(e) {
      var self = this;
      if (e.selected_entity == self._uri) {
         self._selectRow(false);
      }
   },

   click: function(e) {
      var self = this;
      if (!e.target || !$(e.target).hasClass("ignoreClick")) {
         self._selectRow(true);
      }
   },

   actions: {
      changeWorkingFor: function() {
         this.taskView.openPlayerPickerView(this.get('model'));
      }
   },

   _selectRow: function(userClicked) {
      var self = this;
      if (!self.$() || !self.get('model')) {
         return;
      }

      var selected = self.$().hasClass('selected'); // Is this row already selected?
      if (!selected) {
         self.taskView.$('.row').removeClass('selected'); // Unselect everything in the parent view
         self.$().addClass('selected');
      }

      self.taskView.setSelectedCitizen(self.get('model'), self.get('citizenId'), userClicked);
   },

   _update: function() {
      var self = this;
      var citizenData = self.get('model');
      if (self.$() && citizenData) {
         var uri = citizenData.__self;
         if (uri && uri != self._uri) {
            self._uri = uri;
            radiant.call('stonehearth:get_mood_datastore', uri)
               .done(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  if (self._moodTrace) {
                     self._moodTrace.destroy();
                  }
                  self._moodTrace = new RadiantTrace(response.mood_datastore, { current_mood_buff: {} })
                     .progress(function (data) {
                        if (self.isDestroying || self.isDestroyed) {
                           return;
                        }
                        self.set('moodData', data);
                     })
               });
         }

         // fixup row selection
         if (!self.$().hasClass('selected')) {
            var existingSelected = self.taskView.get('selected');
            if (!existingSelected) {
               // If no selected, select ourself if our Hearthling is selected in the world or first in the citizens manager
               radiant.call_obj('stonehearth.selection', 'get_selected_command')
                  .done(function(o) {
                        if (self.isDestroying || self.isDestroyed) {
                           return;
                        }
                        var selected = o.selected_entity;

                        if (self.$('.row') && (self._isFirstRow() || self.get('uri') == selected)){
                           self.$('.row').removeClass('selected');
                           self._selectRow();
                        }
                     });
            } else {
               if (self.get('uri') == existingSelected.__self) {
                  self._selectRow();
               }
            }
         }
      }
      self.taskView.citizenChanged(self.get('model'), self.get('citizenId'));
   }.observes('model'),

   isMultiplayer: function() {
      return this.taskView.get('isMultiplayer');
   }.property('taskView.isMultiplayer'),

   _onWorkingForChanged: function() {
      var self = this;
      var workingForPlayerId = self.get('model.stonehearth:work_order.working_for');
      var playerName;
      if (App.stonehearthClient.getPlayerId() == workingForPlayerId) {
         playerName = i18n.t('stonehearth:ui.game.citizens.working_for.myself');
      } else {
         playerName = App.presenceClient.getSteamName(workingForPlayerId) ||
            App.presenceClient.getPlayerDisplayName(workingForPlayerId);
      }

      self.set('workingForPlayerName', playerName);
      var color = App.presenceClient.getPlayerColor(workingForPlayerId);
      if (color) {
         self.set('colorStyle', 'color: rgba(' + color.x + ',' + color.y + ',' + color.z + ', 1)');
      }
   }.observes('model.stonehearth:work_order.working_for'),

   _onJobChanged: function() {
      var self = this;
      var newDisplayName = self.get('model.stonehearth:job.curr_job_name');
      self._jobDisplayName = newDisplayName;
   }.observes('model.stonehearth:job.curr_job_name'),

   _updateMoodTooltip: function() {
      var self = this;
      var moodData = self.get('moodData');
      if (!moodData || !moodData.current_mood_buff) {
         return;
      }
      var currentMood = moodData.mood;
      if (self._currentMood != currentMood) {
         self._currentMood = currentMood;
         Ember.run.scheduleOnce('afterRender', self, function() {
            var citizenData = self.get('model');
            if (citizenData) {
               App.tooltipHelper.createDynamicTooltip(self.$('.moodColumn'), function () {
                  if (!moodData || !moodData.current_mood_buff) {
                     return;
                  }
                  var moodString = App.tooltipHelper.createTooltip(
                     i18n.t(moodData.current_mood_buff.display_name),
                     i18n.t(moodData.current_mood_buff.description));
                  return $(moodString);
               });
            }
         });
      };
   }.observes('moodData'),

   // ACE: show health/status for citizens
   _updateHealth: function() {
      var self = this;
      var currentHealth = self.get('model.stonehearth:expendable_resources.resources.health');
      if (currentHealth == null) {
         return;
      }

      currentHealth = Math.ceil(currentHealth);
      var currentGuts = Math.ceil(self.get('model.stonehearth:expendable_resources.resources.guts'));
      var maxGuts = Math.ceil(self.get('model.stonehearth:attributes.attributes.max_guts.effective_value'));
      var percentGuts = currentGuts / maxGuts;

      var maxHealth = Math.ceil(self.get('model.stonehearth:attributes.attributes.max_health.effective_value'));
      var effMaxHealthPercent = Math.ceil(self.get('model.stonehearth:attributes.attributes.effective_max_health_percent.effective_value') || 100);
      var incapacitationState = self.get('model.stonehearth:incapacitation.sm.current_state');
      var percentHealth = currentHealth / maxHealth;
      var icon;
      var isWounded = effMaxHealthPercent != 100;
      
      if (currentHealth == 0) {
         // if health is 0, check guts:
         if (currentGuts == maxGuts) {
            icon = "heart_full"
         }
         else if (currentGuts > 0) {
            icon = `heart_${getOctile(percentGuts)}_8`;
         }
         else {
            icon = "heart_empty";
         }
      }
      else if (currentHealth == maxHealth) {
         icon = "heart_full"
      }
      else {
         icon = `heart_${getOctile(percentHealth)}_8`;
      }

      var value = percentGuts;
      if (incapacitationState == 'recuperating') {
         icon = "recuperating/" + icon;
      }
      else if (incapacitationState == 'normal') {
         if (isWounded) {
            icon = "wounded/" + icon;
         }
         value = percentHealth;
      }
      else {
         // dying/dead
         icon = "dying/" + icon;
      }

      icon = "/stonehearth_ace/ui/game/citizens/images/health/" + icon + ".png";

      var healthData = {
         icon: icon,
         value: value,
         incapacitationState: incapacitationState,
         isWounded: isWounded,
      };

      var curHealthData = self.get('healthData');

      if (!curHealthData || curHealthData.icon != healthData.icon || curHealthData.value != healthData.value) {
         self.set('healthData', healthData);

         Ember.run.scheduleOnce('afterRender', self, function() {
            var citizenData = self.get('model');
            if (citizenData) {
               App.tooltipHelper.createDynamicTooltip(self.$('.healthColumn'), function () {
                  if (!healthData) {
                     return;
                  }

                  var value = Math.floor(100 * healthData.value);
                  var tooltipKey;
                  if (incapacitationState == 'recuperating') {
                     tooltipKey = 'recuperating';
                  }
                  else if (incapacitationState == 'normal') {
                     tooltipKey = healthData.isWounded ? 'wounded' : (value == 100 ? 'healthy' : 'hurt');
                  }
                  else {
                     tooltipKey = 'dying';
                  }

                  var healthString = App.tooltipHelper.createTooltip(
                     i18n.t(`stonehearth_ace:ui.game.citizens.health_tooltips.${tooltipKey}_title`, {value: value}),
                     i18n.t(`stonehearth_ace:ui.game.citizens.health_tooltips.${tooltipKey}_description`, {value: value}));
                  return $(healthString);
               });
            }
         });
      }
   }.observes('model.uri', 'model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes'),

   _updateDescriptionTooltip: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', self, function() {
         var citizenData = self.get('model');
         if (citizenData) {
            App.tooltipHelper.createDynamicTooltip(self.$('.nameColumn'), function () {
               if (citizenData['stonehearth:unit_info']) {
                  return i18n.t(citizenData['stonehearth:unit_info'].description, { self: citizenData });
               }
            });
         }
      });
   }.observes('model.stonehearth:unit_info'),

   _isFirstRow: function() {
      var tableEl = $('#tasksListTableBody');
      if (tableEl) {
         var rowEls = tableEl.children();
         if (rowEls.length > 0) {
            var viewEl = rowEls[0];
            return viewEl.getAttribute('data-citizen-id') == this.get('citizenId');
         }
      }

      return false;
   },

   updateRow: function() {
      var self = this;

      self._update();
      self._onWorkingForChanged();
      self._updateMoodTooltip();
      self._updateDescriptionTooltip();
      self._onJobChanged();
   },

   workOrderChecked : function(workOrder) {
      var self = this;

      var workOrders = self.get('model.stonehearth:work_order.work_order_statuses');
      var workOrderRefs = self.get('model.stonehearth:work_order.work_order_refs');
      if (!workOrders || !workOrderRefs) {
         return false;
      }
      return workOrderRefs[workOrder] && workOrders[workOrder] != 'disabled';
   },

   workOrderLocked : function(workOrder) {
      var self = this;

      var workOrderRefs = self.get('model.stonehearth:work_order.work_order_refs');
      if (!workOrderRefs) {
         return false;
      }
      return !workOrderRefs[workOrder];
   },

   // Checked properties used to control whether or not the checkbox is checked
   haulChecked: function() {
      return this.workOrderChecked('haul');
   }.property('citizenId', 'model.stonehearth:work_order'),

   buildChecked: function() {
      return this.workOrderChecked('build');
   }.property('citizenId', 'model.stonehearth:work_order'),

   mineChecked: function() {
      return this.workOrderChecked('mine');
   }.property('citizenId', 'model.stonehearth:work_order'),

   gatherChecked: function() {
      return this.workOrderChecked('gather');
   }.property('citizenId', 'model.stonehearth:work_order'),

   jobChecked: function() {
      return this.workOrderChecked('job');
   }.property('citizenId', 'model.stonehearth:work_order'),

   // Locked properties used to control whether or not the checkbox is disabled
   haulLocked: function() {
      return this.workOrderLocked('haul');
   }.property('citizenId', 'model.stonehearth:work_order'),

   buildLocked: function() {
      return this.workOrderLocked('build');
   }.property('citizenId', 'model.stonehearth:work_order'),

   mineLocked: function() {
      return this.workOrderLocked('mine');
   }.property('citizenId', 'model.stonehearth:work_order'),

   gatherLocked: function() {
      return this.workOrderLocked('gather');
   }.property('citizenId', 'model.stonehearth:work_order'),

   jobLocked: function() {
      // Lock job if we are working for another player and we are not a combat class
      if (this.get('model.stonehearth:work_order.working_for') != this.get('model.player_id')
         && !this.get('model.stonehearth:job.curr_job_controller.is_combat_class')) {
         return true;
      }

      return this.workOrderLocked('job');
   }.property('citizenId', 'model.stonehearth:work_order', 'model.stonehearth:job.curr_job_controller'),

   // Id properties for identifying checkboxes
   haulId: function() {
      return "haul_" + this.get('citizenId');
   }.property('citizenId'),

   buildId: function() {
      return "build_" + this.get('citizenId');
   }.property('citizenId'),

   mineId: function() {
      return "mine_" + this.get('citizenId');
   }.property('citizenId'),

   gatherId: function() {
      return "gather_" + this.get('citizenId');
   }.property('citizenId'),

   jobId: function() {
      return "job_" + this.get('citizenId');
   }.property('citizenId'),
});

// Manually manage child views using this container view for performance reasons
// Reduces DOM and view reconstruction
App.StonehearthCitizenTasksContainerView = App.StonehearthCitizenRowContainerView.extend({
   tagName: 'tbody',
   templateName: 'citizenTasksContainer',
   elementId: 'tasksListTableBody',
   containerParentView: null,
   currentCitizensMap: {},
   rowCtor: App.StonehearthCitizenTasksRowView,

   constructRowViewArgs: function(citizenId, entry) {
      return {
         taskView: this.containerParentView,
         uri:entry.__self,
         citizenId: citizenId
      };
   },

   updateRows: function(citizensMap, sortRequested) {
      var self = this;
      var rowChanges = self.getRowChanges(citizensMap);
      self._super(citizensMap);

      if (rowChanges.numRowsChanged == 1 && self._domModified) {
         // Refresh all rows if added/removed a single row, but dom was modified manually
         self.resetChildren(rowChanges);
      } else if (sortRequested) {
         // If no rows have changed but we need to sort
         self._sortCitizensDom(citizensMap);
      }
   },

   // Add a single row in sorted order
   insertInSortedOrder: function(rowToInsert) {
      var self = this;
      var addIndex = self.get('length') || 0;
      var sortFn = self._getCitizenRowsSortFn(self.currentCitizensMap);
      for (var i = 0; i < self.get('length'); i++) {
         var rowView = self.objectAt(i);
         var sortValue = sortFn(rowToInsert.citizenId, rowView.citizenId);
         if (sortValue < 0) {
            addIndex = i;
            break;
         }
      }

      self.addRow(rowToInsert, addIndex);
   },

   // Re-set container view internal array in sorted order
   resetChildren: function() {
      var self = this;
      var sortFn = self._getCitizenRowsSortFn();
      var sorted = self.toArray().sort(function(a, b) {
         var aCitizenId = a.citizenId;
         var bCitizenId = b.citizenId;

         return sortFn(aCitizenId, bCitizenId);
      });

      self.setObjects(sorted);
      Ember.run.scheduleOnce('afterRender', function() {
         var firstRow = self.objectAt(0);
         if (firstRow) {
            firstRow._selectRow();
         }
      });
      self._domModified = false;
   },

   removeRow: function(citizenId) {
      // Select the first row if the row we are removing is selected
      var selected = this.containerParentView.$('.selected');
      if (selected && selected[0]) {
         var selectedCitizenId = selected[0].getAttribute('data-citizen-id');
         if (citizenId == selectedCitizenId && this.get('length') > 1) {
            this.objectAt(0)._selectRow();
         }
      }

      this._super(citizenId);
   },

   // ACE: allow for sorting by job or new health column
   _getCitizenRowsSortFn: function(citizensMap) {
      var self = this;
      // Sort based on the sorting property selected by player
      var sortDirection = self.containerParentView.get('sortDirection') || citizensLastSortDirection;
      var sortKey = self.containerParentView.get('sortKey') || citizensLastSortKey;
      var keyExtractors = {
         'job': function(x) {
            return self._getJobSortKey(x['stonehearth:job']);
         },
         'name': function(x) {
            return x['stonehearth:unit_info'] && i18n.t(x['stonehearth:unit_info'].custom_name, {self: x});
         },
         'activity': function(x) {
            return x['stonehearth:ai'] && i18n.t(x['stonehearth:ai'].status_text_key, {self: x});
         },
         'body': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.body.user_visible_value;
         },
         'mind': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.mind.user_visible_value;
         },
         'spirit': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.spirit.user_visible_value;
         },
         'happiness': function(x) {
            return x['stonehearth:happiness'] && x['stonehearth:happiness'].current_happiness;
         },
         'health': function(x) {
            var incapacitationState = x['stonehearth:incapacitation'].sm.current_state;
            var currentGuts = Math.ceil(x['stonehearth:expendable_resources'].resources.health);
            var maxGuts = Math.ceil(x['stonehearth:attributes'].attributes.max_guts.user_visible_value);
            if (currentGuts < maxGuts) {
               return currentGuts / maxGuts + (incapacitationState == 'recuperating' ? 2 : 0);
            }
            var currentHealth = Math.ceil(x['stonehearth:expendable_resources'].resources.health);
            var maxHealth = Math.ceil(x['stonehearth:attributes'].attributes.max_health.user_visible_value);
            var effMaxHealthPercent = Math.ceil(x['stonehearth:attributes'].attributes.effective_max_health_percent.user_visible_value || 100);
            return currentHealth / maxHealth + (effMaxHealthPercent != 100 && 6 || 4);
         },
         'working-for': function(x) {
            return x['stonehearth:work_order'] && i18n.t(x['stonehearth:work_order'].working_for);
         },
         'haul-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.haul && x['stonehearth:work_order'].work_order_statuses.haul != 'disabled') ? 1 : 0;
         },
         'mine-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.mine && x['stonehearth:work_order'].work_order_statuses.mine != 'disabled') ? 1 : 0;
         },
         'gather-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.mine && x['stonehearth:work_order'].work_order_statuses.gather != 'disabled') ? 1 : 0;
         },
         'build-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.build && x['stonehearth:work_order'].work_order_statuses.build != 'disabled') ? 1 : 0;
         },
         'job-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.job && x['stonehearth:work_order'].work_order_statuses.job != 'disabled') ? 1 : 0;
         },
      };

      return function(aCitizenId, bCitizenId) {
         if (!aCitizenId || !bCitizenId) {
            return 0;
         }

         var aModel = self.currentCitizensMap[aCitizenId];
         var bModel = self.currentCitizensMap[bCitizenId];

         if (!aModel || !bModel) {
            return 0;
         }
         var aKey = keyExtractors[sortKey](aModel);
         var bKey = keyExtractors[sortKey](bModel);
         var n = (typeof aKey == 'string') ? aKey.localeCompare(bKey) : (aKey < bKey ? -1 : (aKey > bKey) ? 1 : 0);
         if (n == 0) {
            var aName = keyExtractors['name'](aModel);
            var bName = keyExtractors['name'](bModel);
            n = aName ? aName.localeCompare(bName) : 0;
         }

         return n * sortDirection;
      };
   },

   _getJobSortKey: function(job) {
      if (job) {
         var alias = job.job_uri;
         var isCombat = App.jobController.jobIsCombat(alias);
         var isCrafter = App.jobController.jobIsCrafter(alias);
         var localized = i18n.t(job.curr_job_name);

         return (isCombat ? '|combat|' : '') + (isCrafter ? '|crafter|' : '') + localized;
      }
   },

   // Hacky but wayyy faster. Manually sort the rows in the DOM.
   // Important note: If we've messed with the DOM this way, the container view's internal
   // child order array will not reflect the changes and thus be in an invalid state. This
   // fine if the the array isn't mutated, but if we need to add or remove a row, we must reset
   // the array using `setObjects` otherwise Ember will render the container view incorrectly.
   _sortCitizensDom: function() {
      var self = this;
      var sortFn = self._getCitizenRowsSortFn();
      var sorted = $('#tasksListTableBody').children().sort(function(a, b) {
         var aCitizenId = a.getAttribute('data-citizen-id');
         var bCitizenId = b.getAttribute('data-citizen-id');

         return sortFn(aCitizenId, bCitizenId);
      });

      $('#tasksListTableBody').append(sorted);
      self._domModified = true;
   },
});
