var topElement;
$(document).on('stonehearthReady', function(){
   topElement = $(top);
   App.debugDock.addToDock(App.StonehearthObjectBrowserIcon);
});

App.StonehearthObjectBrowserIcon = App.View.extend({
   templateName: 'objectBrowserIcon',
   classNames: ['debugDockIcon'],

   didInsertElement: function() {
      $('#objectBrowserIcon').tooltipster();
      this.$().click(function() {
         App.debugView.addView(App.StonehearthObjectBrowserView, { trackSelected: true })
      });
   }

});

App.StonehearthObjectBrowserView = App.View.extend({
   templateName: 'objectBrowser',
   uriProperty: 'model',

   init: function() {
      this._super();
      this.backStack = [];
      this.forwardStack = [];
      this._viewingPrivateData = false;
   },

   didInsertElement: function() {
      var self = this;

      // for some reason $(top) here isn't [ Window ] like everywhere else.  Why?  Dunno.
      // So annoying!  Use the cached value of $(top) we got in 'stonehearthReady'
      topElement.on("radiant_selection_changed.object_browser", function (_, data) {
         if (self.trackSelected) {
            var uri = App.stonehearthClient.getSubSelectedEntity();
            if (!uri) {
               uri = App.stonehearthClient.getSelectedEntity();
            }
            //var uri = data.selected_entity;
            if (uri) {
               self.navigateTo(uri);
            }
         }
      });

      this.$().draggable();

      if (self.relativeTo) {
         var top = self.relativeTo.top + 64;
         var left = self.relativeTo.left + 64;
         this.$().css({'top': top, 'left' : left})
      }
      this.$('.button').tooltipster({
         theme: 'tooltipster-shdt',
         arrow: true,
      });

      this.$('#body').on("click", ".navlink", function(event) {
         var uri = $(this).attr('href');

         event.preventDefault();

         self.trackSelected = false;
         self._updateTrackSelectedControl();

         if (event.shiftKey) {
            App.debugView.addView(App.StonehearthObjectBrowserView, {
                  uri: uri,
                  relativeTo: self.$().offset(),
               })
         } else {
            self.navigateTo(uri);
         }
      });

      $('#uriInput').keypress(function (e) {
         if (self.isDestroying || self.isDestroyed) {
            return;
         }
         if (e.which == 13) {
            $(this).blur();
            self.navigateTo($(this).val());
         }
      });

      self._updateTrackSelectedControl();
      self._updateCollapsedControl();
   },

   destroy: function() {
      topElement.off("radiant_selection_changed.object_browser");
      this._super();
   },

   navigateTo: function(uri) {
      var self = this;
      var currentUri = self.get('uri');
      if (uri != currentUri) {
         self.backStack.push(currentUri);
         self.forwardStack = [];
         if (uri.indexOf('/') < 0 && uri.indexOf(':') < 0) {
            radiant.call("debugtools:get_mod_controller_command", uri)
               .done(function(response) {
                  self.set('uri', response.mod_uri);
               })
         } else {
            self.set('uri', uri);
         }
      }
      self.set("privateData", null);
      self._viewingPrivateData = false;
   },

   _updateCollapsedControl : function() {
      var self = this;
      if (self.collapsed) {
         this.$('#collapse_image').addClass('fa-chevron-up')
                                  .removeClass('fa-chevron-down');
         this.$('#body').hide();
      } else {
         this.$('#collapse_image').removeClass('fa-chevron-up')
                                  .addClass('fa-chevron-down');
         this.$('#body').show();
      }
   },

   _updateTrackSelectedControl : function() {
      var self = this;
      if (self.trackSelected) {
         var selected = App.stonehearthClient.getSubSelectedEntity();
         if (!selected) {
            selected = App.stonehearthClient.getSelectedEntity();
         }
         if (selected) {
            self.set('uri', selected)
         }
         this.$("#trackSelected").addClass('depressed');
      } else {
         this.$("#trackSelected").removeClass('depressed');
      }
   },

   _updateToggleRawViewControl : function() {
      var self = this;
      if (self.showRawView) {
         this.$("#toggleRawView").addClass('depressed');
      } else {
         this.$("#toggleRawView").removeClass('depressed');
      }
   },

   actions: {
      goBack: function() {
         if (this.backStack.length > 0) {
            var currentUri = this.get('uri');

            var nextUri = this.backStack.pop();
            this.forwardStack.push(currentUri);
            this.set('uri', nextUri);
            this.set("privateData", null);
            this._viewingPrivateData = false;
         }
      },

      goForward: function () {
         if (this.forwardStack.length > 0) {
            var currentUri = this.get('uri');

            var nextUri = this.forwardStack.pop();
            this.backStack.push(currentUri);
            this.set('uri', nextUri);
            this.set("privateData", null);
            this._viewingPrivateData = false;
         }
      },

      close: function () {
         this.destroy();
      },

      toggleCollapsed: function() {
         var self = this;
         self.collapsed = !self.collapsed;
         self._updateCollapsedControl();
      },

      toggleTrackSelected: function() {
         var self = this;
         self.trackSelected = !self.trackSelected;
         self._updateTrackSelectedControl();
      },

      toggleRawView: function() {
         var self = this;
         self.set('showRawView', !self.get('showRawView'));
         self._updateToggleRawViewControl();
      },

      togglePrivateVariables: function() {
         var self = this;
         self._viewingPrivateData = !self._viewingPrivateData;
         if (self._viewingPrivateData) {
            var uri = self.get("uri");
            radiant.call("debugtools:get_all_data", uri)
               .done(function(response) {
                  if (response) {
                     if (response.__fields) {
                        self.set("privateData", response.__fields);
                     } else {
                        self.set("privateData", response);
                     }
                  }
               })
               .fail(function(error) {
                  self.set("privateData", error);
               });
         } else {
            self.set("privateData", null);
         }
      },

      showAllEntities: function() {
         App.debugView.addView(App.StonehearthEntityTrackerInspectorView)
      },

      selectEntity: function() {
         var entity = this.get('uri');

         if (entity) {
            radiant.call('stonehearth:select_entity', entity);
            radiant.call('stonehearth:camera_look_at_entity', entity);
         } else {
            console.log('entity undefined')
         }
      }
   }
});

App.StonehearthObjectBrowserContentView = App.View.extend({
   templateName: 'objectBrowserContent',
   uriProperty: 'model',

   subViewClass: function() {
      var known_types = {
         'stonehearth:game_master:encounter' :  'stonehearthObjectBrowserEncounter',
      }
      var type = this.get('model.__controller');
      var subViewClass = known_types[type];
      if (!subViewClass) {
         subViewClass = 'stonehearthObjectBrowserRaw';
      }

      if (this._lastSubViewClass && this._lastSubViewClass != subViewClass) {
         Ember.run.scheduleOnce('afterRender', this, 'rerender');
      }
      this._lastSubViewClass = subViewClass;

      return subViewClass;
   }.property('model', 'model.__controller'),
});

App.StonehearthObjectBrowserRawPrivateView = App.View.extend({
   templateName: 'stonehearthObjectBrowserRawPrivate',

   raw_view: function() {
      var model = this.get('privateData');

      if (!model) {
         return '- no data -';
      }
      var json = json_stable_stringify(model, { space: '   ' });
      return json.replace(/&/g, '&amp;')
                 .replace(/</g, '&lt;')
                 .replace(/>/g, '&gt;')
                 .replace(/ /g, '&nbsp;')
                 .replace(/\n/g, '<br>')
                 .replace(/"(object:\/\/[^"]*)"/g, '<a class="navlink" href="$1">$1</a>')
                 .replace(/uri\":&nbsp;\"([^"]*)"/g, 'uri": <a class="navlink" href="$1">$1</a>');
   }.property('privateData'),
});

App.StonehearthObjectBrowserRawView = App.View.extend({
   templateName: 'stonehearthObjectBrowserRaw',
   uriProperty: 'model',

   raw_view: function() {
      var model = this.get('model');

      if (!model) {
         return '- no data -';
      }
      var json = json_stable_stringify(model, { space: '   ' });
      return json.replace(/&/g, '&amp;')
                 .replace(/</g, '&lt;')
                 .replace(/>/g, '&gt;')
                 .replace(/ /g, '&nbsp;')
                 .replace(/\n/g, '<br>')
                 .replace(/"(object:\/\/[^"]*)"/g, '<a class="navlink" href="$1">$1</a>')
                 .replace(/uri\":&nbsp;\"([^"]*)"/g, 'uri": <a class="navlink" href="$1">$1</a>');
   }.property('model')
});


App.StonehearthObjectBrowserEncounterView = App.ContainerView.extend({
   uriProperty: 'model',
   components: {
      script : {},
      ctx : {}
   },

   init : function() {
      this._super();
      var self = this;
      self.radiantTraceJournals = new RadiantTrace();
      self.traceJournals = self.radiantTraceJournals.traceUri(this.uri, {
         'script' : '*'
      });
      self.traceJournals.progress(function(obj) {
         self.makeChild(obj);
         self.radiantTraceJournals.destroy();
      });
   },

   didInsertElement: function() {
      this._super();
   },

   makeChild: function(obj) {
      var known_types = {
         'stonehearth:game_master:encounters:generator' :            'StonehearthObjectBrowserGeneratorEncounterView',
         'stonehearth:game_master:encounters:wait' :                 'StonehearthObjectBrowserWaitEncounterView',
         'stonehearth:game_master:encounters:wait_for_net_worth' :   'StonehearthObjectBrowserWaitForNetWorthEncounterView',
         'stonehearth:game_master:encounters:wait_for_time_of_day' : 'StonehearthObjectBrowserWaitForTimeOfDayEncounterView',
         'stonehearth:game_master:encounters:wait_for_requirements_met' : 'StonehearthObjectBrowserWaitForRequirementsMetView',
         'stonehearth:game_master:encounters:collection_quest' :     'StonehearthObjectBrowserCollectionQuestEncounterView',
         'stonehearth:game_master:encounters:delivery_quest' :   'StonehearthObjectBrowserDeliveryQuestEncounterView',
         'stonehearth_ace:game_master:encounters:firstbloom:egg_hunt' :   'StonehearthObjectBrowserEggHuntEncounterView',
         'stonehearth:game_master:encounters:dispatch_quest' : 'StonehearthObjectBrowserDispatchQuestEncounterView',
      }

      var type = obj.script.__controller;

      var encounterSubViewClass = known_types[type];
      if (!encounterSubViewClass) {
         encounterSubViewClass = 'StonehearthObjectBrowserRawEncounterView';
      }

      this.destroyAllChildren();
      this._childView = this.createChildView(App[encounterSubViewClass], {uri : obj.script.__self, encounter_name : obj.node_name});
      this.pushObject(this._childView);
   }
});

App.StonehearthObjectBrowserBaseView = App.View.extend({
   uriProperty: 'model',
   components: {
      ctx : {}
   },

   destroy : function() {
      self._dead = true
      if (self._interval) {
         clearInterval(self._interval);
         self._interval = null;
      }
   },

   didInsertElement: function() {
      var self = this;

      self._super();
   },

   startPolling: function() {
      var self = this;

      if (!this.get('model.__self')) {
         return;
      }
      if (self.pollRate && !self._interval) {
         self._poll_encounter();
         self._interval = setInterval(function() { self._poll_encounter(); }, self.pollRate);
      }

      self._call_encounter('get_out_edges_cmd')
         .done(function(o) {
            if (!self._dead) {
               var edgeList = null;
               if ((typeof o.result) == "string") {
                  edgeList = [];
                  edgeList.push(o.result);
               }
               else if (o.out_edges && o.type == "trigger_one") {
                  edgeList = [];
                  radiant.each(o.out_edges, function(k, v) {
                     if ((typeof v) == "string") {
                        edgeList.push(v);
                     } else {
                        edgeList.push(v.out_edge);
                     }
                  });
               }
               self.set('out_edges', edgeList);
            }
         });
   }.observes('model').on('init'),

   _poll_encounter : function() {
      var self = this;
      if (!self._dead) {
         self._call_encounter('get_progress_cmd')
                  .done(function(o) {
                     if (!self._dead) {
                        self.set('progress', o);
                     }
                  })
      }
   },

   _call_encounter : function(method, arg0, arg1, arg2) {
      var obj = this.get('model.__self');
      return radiant.call_obj(obj, method, arg0, arg1, arg2)
                        .fail(function(o) {
                           console.log('failed!', o)
                        })
   }
});

App.StonehearthObjectBrowserRawEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserRawEncounter'
});

App.StonehearthObjectBrowserWaitEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserWaitEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      },
      triggerEdge: function(edge_name) {
         this._call_encounter('trigger_now_cmd', edge_name)
      }
   }
});

App.StonehearthObjectBrowserGeneratorEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserGeneratorEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      },
      triggerEdge: function(edge_name) {
         this._call_encounter('trigger_now_cmd', edge_name)
      }
   }
});

App.StonehearthObjectBrowserWaitForNetWorthEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserWaitForNetWorthEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      },
   }
});

App.StonehearthObjectBrowserWaitForTimeOfDayEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserWaitForTimeOfDayEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      },
   }
});

App.StonehearthObjectBrowserWaitForRequirementsMetView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserWaitForRequirementsMetEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      },
   },

   _poll_encounter : function() {
   var self = this;
      if (!self._dead) {
         self._call_encounter('get_progress_cmd')
                  .done(function(o) {
                     if (!self._dead) {
                        self.set('progress', o);
                        self.set('requirements', radiant.map_to_array(o.requirements, function(k, v) {
                           return k.toString() + ': ' + v.toString();
                        }));
                     }
                  })
      }
   }
});

App.StonehearthObjectBrowserCollectionQuestEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserCollectionQuestEncounter',
   pollRate: 500,
   actions: {
      triggerEdge: function(edge_name) {
         this._call_encounter('trigger_now_cmd', edge_name)
      },
      forceReturnNow: function() {
         this._call_encounter('force_return_now_cmd');
      },
   }
});

App.StonehearthObjectBrowserDeliveryQuestEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserDeliveryQuestEncounter',
   pollRate: 500,
   actions: {
      forceComplete: function() {
         this._call_encounter('force_complete')
      },
   }
});

App.StonehearthObjectBrowserEggHuntEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserEggHuntEncounter',
   pollRate: 500,
   actions: {
      forceComplete: function() {
         this._call_encounter('force_complete')
      },
   }
});

App.StonehearthObjectBrowserDispatchQuestEncounterView = App.StonehearthObjectBrowserBaseView.extend({
   templateName: 'stonehearthObjectBrowserDispatchQuestEncounter',
   pollRate: 500,
   actions: {
      triggerNow: function() {
         this._call_encounter('trigger_now_cmd');
      }
   },
   ctxUpdated: function() {
      console.log('model ctx updated!')
   }.observes('model.ctx')
});

App.stonehearthObjectBrowserDebugCommandsView = App.View.extend({
   templateName: 'stonehearthObjectBrowserDebugCommands',
   closeOnEsc: true,
   uriProperty: 'model',

   components: {
      "uri": {},
      "stonehearth:job": {},
      "stonehearth:attributes": {},
      "stonehearth:expendable_resources": {}
   },
   didInsertElement: function() {
      var self = this;
      if (self.posX && self.posY) {
         self.$("#objectBrowser").css({top: self.posY, left: self.posX, position:'absolute'});
      }
      self._super();

      var entity = self.get('model');
      if (entity) {
         self._modelUpdated();
         self._initialized = true;
      }
   },
   _modelUpdated: function() {
      var self = this;
      if (self._initialized || !self.$("#objectBrowser")) {
         return;
      }
      var entity = self.get('model');
      // Generate list of all console commands that apply to the selected entity.
      var allCommands = radiant.console.getCommands();
      var possibleCommandsArray = [];
      radiant.each(allCommands, function(key, command) {
         if (command.test && command.test(entity)) {
            var name = command.debugMenuNameOverride ? command.debugMenuNameOverride : key;
            possibleCommandsArray.push({
               displayName: name,
               command: key
            });
         }
      });
      self.set('consoleCommands', possibleCommandsArray);
   }.observes('model'),

   actions: {
      doConsoleCommand: function(command) {
         radiant.console.run(command);
      },
      close: function () {
         this.destroy();
      },
   }
});
