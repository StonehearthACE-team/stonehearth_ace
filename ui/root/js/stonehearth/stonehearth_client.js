
$(document).ready(function(){
   $(top).on("radiant_remove_ladder", function (_, e) {
      var item = e.entity;

      // only remove ladder if player owns it
      if (App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} )
      App.stonehearthClient.removeLadder(item);
   });
});

var StonehearthClient;

(function () {
   StonehearthClient = SimpleClass.extend({

      init: function() {
         var self = this;

         $(top).on("radiant_selection_changed", function (_, e) {
            self._selectedEntity = e.selected_entity;
         });

         $(document).mousemove( function(e) {
            self.mouseX = e.pageX;
            self.mouseY = e.pageY;
         });

         $(document).contextmenu(function (e) {
            e.preventDefault();
         });
      },

      Setup: function() {
         var self = this;
         self.initializeServices();
         self.initializeGameState();
      },

      initializeServices: function() {
         var self = this;

         radiant.call('stonehearth:get_client_service', 'build_editor')
            .done(function(e) {
               self._build_editor = e.result;
               radiant.trace(self._build_editor)
                  .progress(function(change) {
                     self._subSelectedEntity = change.selected_sub_part;
                     $(top).trigger('selected_sub_part_changed', change);
                  });
            })
            .fail(function(e) {
               console.log('error getting build editor')
               console.dir(e)
            });

         radiant.call('stonehearth:get_service', 'build')
            .done(function(e) {
               self._build_service = e.result;
            })
            .fail(function(e) {
               console.log('error getting build service')
               console.dir(e)
            });

      },

      gameState: {
         settlementName: '',
         settlementSerialNumber: 42,
         scoresUri: null,
         saveKey: null
      },

      initializeGameState: function() {
         var self = this;

         radiant.call_obj('stonehearth.session', 'get_player_id_command')
            .done(function(e) {
               self.gameState.playerId = e.id;
            });

         radiant.call_obj('stonehearth.session', 'is_host_player_command')
            .done(function(e) {
               self.gameState.isHostPlayer = e.is_host;
            });

         radiant.call_obj('stonehearth.player', 'get_host_player_id_command')
            .done(function(e) {
               self.gameState.hostPlayerId = e.player_id;
            });

         radiant.call_obj('stonehearth.town', 'get_town_name_command')
            .done(function (e) {
               self.gameState.settlementName = e.townName;
               self.gameState.settlementSerialNumber = e.townSerialNumber;
            });

         radiant.call('stonehearth:get_score')
            .done(function(response){
               self.gameState.scoresUri = response.score;
            });

         radiant.call('radiant:is_multiplayer_enabled')
            .done(function(response) {
               self.gameState.isMultiplayerEnabled = response.enabled;
            });

         radiant.call('radiant:is_steam_present')
            .done(function(response) {
               self.gameState.isSteamPresent = response.present;
            });
      },

      getSelectedEntity : function() {
         return this._selectedEntity;
      },

      getSubSelectedEntity : function() {
         return this._subSelectedEntity;
      },

      settlementName: function(value) {
         if (value) {
            this.gameState.settlementName = value;
         }
         // TODO: Make sure we only call this after the population is initialized or make it a promise.
         return i18n.t(this.gameState.settlementName, { town_number: this.gameState.settlementSerialNumber });
      },

      getPlayerId: function() {
         return this.gameState.playerId;
      },

      getHostPlayerId: function () {
         return this.gameState.hostPlayerId;
      },

      isHostPlayer: function() {
         return this.gameState.isHostPlayer;
      },

      isMultiplayerEnabled: function() {
         return this.gameState.isMultiplayerEnabled;
      },

      isSteamPresent: function() {
         return this.gameState.isSteamPresent;
      },

      // also pass entity_data that's already been fully traced by unit_frame so we don't have to retrace it
      doCommand: function(entity, player_id, command, entity_data) {
         var self = this;
         if (!command.enabled) {
            return;
         }
         var event_name = '';

         if (command.action == 'fire_event') {
            // xxx: error checking would be nice!!
            var e = {
               entity : entity,
               entity_data: entity_data,
               event_data : command.event_data,
               player_id : player_id
            };
            $(top).trigger(command.event_name, e);

            event_name = command.event_name.toString().replace(':','_')

         } else if (command.action == 'call') {
            var uri = ((typeof entity) == 'object') ? entity.__self : entity;
            if (!uri) return;
            var args = [uri];
            if (command.args) {
               radiant.each(command.args, function(_, v) {
                  args.push(v);
               });
            }

            if (command.object) {
               //if the command is "repeating" then call it again when done
               radiant.call_objv(command.object, command['function'], args)
                  .deferred.done(function(response){
                     if (command.sound_on_complete) {
                        radiant.call('radiant:play_sound', {'track' : command.sound_on_complete } );
                     }
                     if (command.repeating == true) {
                        self.doCommand(entity, player_id, command);
                     }
                  });
            } else {
               radiant.callv(command['function'], args)
            }

            event_name = command['function'].toString().replace(':','_')

         } else {
            throw "unknown command.action " + command.action
         }
      },

      getActiveTool: function() {
         return this._activeTool;
      },

      deactivateAllTools: function() {
         var self = this;
         return radiant.call('stonehearth:deactivate_all_tools')
            .always(function() {
               self._activeTool = null;
            });
      },

      // Wrapper to call all tools, handling the boilerplate tool management.
      _callTool: function(toolName, toolFunction, preCall) {
         var self = this;
         var deferred = new $.Deferred();

         var debug_log = function(str) {
            //console.log('(processing tool ' + toolName + ') ' + str);
         };

         debug_log('new call to _callTool... ');

         var activateTool = function() {
            debug_log('activating tool...')
            if (preCall) {
               debug_log('in preCall for activateTool...');
               preCall();
            }
            debug_log('calling tool function...');
            self._activeTool = toolFunction()
               .done(function(response) {
                  if (self._activeTool && self._activeTool.state() == "resolved") {
                     debug_log('clearing self._activeTool in tool done handler...');
                     self._activeTool = null;
                  }
                  deferred.resolve(response);
               })
               .fail(function(response) {
                  if (self._activeTool && self._activeTool.state() == "rejected") {
                     debug_log('clearing self._activeTool in tool fail handler...');
                     self._activeTool = null;
                  }
                  deferred.reject(response);
               });
         };

         if (self._activeTool) {
            // If we have an active tool, trigger a deactivate so that when that
            // tool completes, we'll activate the new tool.
            debug_log('installing activateTool always handler on old tool to activate this one (crazy!)');
            self.deactivateAllTools().always(activateTool);
         } else {
            debug_log('activating tool immediately, since there is no active one now.');
            activateTool();
         }
         debug_log('returning deferred from _callTool');

         return deferred;
      },

      _currentTip: null,
      showTip: function(title, description, options) {
         var self = this
         var o = options || {};

         if (o.i18n) {
            title = i18n.t(title);
            description = i18n.t(description);
         }

         if (self._currentTip && self._currentTip.title == title && self._currentTip.description == description) {
            // do nothing
         } else {
            self._destroyCurrentTip();
            description = description || '';
            self._currentTip = App.gameView.addView(App.StonehearthTipPopup,
               {
                  title: title,
                  description: description,
                  warning: o.warning,
                  timeout: o.timeout,
                  deferred: o.deferred
               });
         }

         return self._currentTip;
      },

      showTipWithKeyBindings: function (title, description, keyBindings) {
         var self = this;
         var combos = Object.values(keyBindings).map(function (actionName) {
            var hotkey = App.hotkeyManager.getHotKey(actionName);
            var combo = hotkey && (hotkey.combo1 || hotkey.combo2);
            return combo;
         });
         App.hotkeyManager.getPrettyKeyComboNames(combos).done(function (names) {
            Object.keys(keyBindings).forEach(function (key, i) {
               keyBindings[key] = names[i] || i18n.t('stonehearth:ui.shell.settings.controls_tab.unbound');
            });
            self.showTip(i18n.t(title), i18n.t(description, keyBindings));
         });
      },

      // if tip is null, whatever tip is showing will be unconditionally hidden
      hideTip: function(tip) {
         if (tip) {
            if (this._currentTip == tip) {
               this._destroyCurrentTip();
            }
         } else {
            this._destroyCurrentTip();
         }
      },

      _destroyCurrentTip: function() {
         if (this._currentTip) {
            this._currentTip.destroy();
            this._currentTip = null;
         }
      },

      _characterSheet: null,
      // ACE: dismiss instead of destroy
      showCharacterSheet: function(entity) {
         if (this._petCharacterSheet != null && !this._petCharacterSheet.isDestroyed) {
            this._petCharacterSheet.dismiss();
         }
         if (this._characterSheet != null && !this._characterSheet.isDestroyed) {
            if (this._characterSheet.get('uri') == entity) {
               this._characterSheet.dismiss();
            }
            else {
               this._characterSheet.set('uri', entity);
               this._characterSheet.show();
            }
         } else {
            this._characterSheet = App.gameView.addView(App.StonehearthCitizenCharacterSheetView, { uri: entity });
         }
      },

      _petCharacterSheet: null,
      // ACE: dismiss instead of destroy
      showPetCharacterSheet: function(entity) {
         if (this._characterSheet != null && !this._characterSheet.isDestroyed) {
            this._characterSheet.dismiss();
         }

         if (this._petCharacterSheet != null && !this._petCharacterSheet.isDestroyed) {
            if (this._petCharacterSheet.get('uri') == entity) {
               this._petCharacterSheet.dismiss();
            }
            else {
               this._petCharacterSheet.set('uri', entity);
               this._petCharacterSheet.show();
            }
         } else {
            this._petCharacterSheet = App.gameView.addView(App.StonehearthPetCharacterSheetView, { uri: entity });
         }
      },

      // ACE: added job_index parameter
      showPromotionTree: function(entity_id, job_index) {
         var view = App.stonehearth.promotionTreeView;
         if (view && view.get('citizen.__self') == entity_id) {
            view.dismiss();
         } else if (view) {
            view.show(entity_id, job_index);
         } else {
            App.stonehearth.promotionTreeView = App.gameView.addView(App.StonehearthPromotionTree, {
               citizen: entity_id,
               job_index: job_index
            });
         }
      },

      // ACE: added fence view
      showBuildFenceView: function() {
         var view = App.stonehearth.buildFenceView;
         if (view) {
            view.show();
         }
         else {
            App.stonehearth.buildFenceView = App.gameView.addView(App.AceBuildFenceModeView);
         }
      },

      _partyEditor: null,
      showPartyEditor: function(party) {
         if (this._partyEditor != null && !this._partyEditor.isDestroyed) {
            this._partyEditor.set('uri', party);
            //this._partyEditor.destroy();
            //this._partyEditor = null;
         } else {
            this._partyEditor = App.gameView.addView(App.StonehearthPartyEditorView, { uri: party });
         }
      },
      hidePartyEditor: function() {
         if (this._partyEditor != null && !this._partyEditor.isDestroyed) {
            this._partyEditor.destroy();
         }
      },

      // item is a reference to an actual entity, not a class of entities like stonehearth:furniture:comfy_bed
      placeItem: function(item) {
         this._placeItemOrItemType('item', 'placeItem', item);
      },

      // item type is a uri, not an item entity
      placeItemType: function(itemType, quality) {
         this._placeItemOrItemType('itemType', 'placeItemType', itemType, quality);
      },

      // item type is a uri, not an item entity
      craftAndPlaceItemType: function(itemType, gameMode) {
         this._placeItemOrItemType('itemType', 'placeItemType', itemType, null, {
            repeat_tool: true,
            add_craft_order: true,
            gameMode: gameMode,
            tip_description: 'stonehearth_ace:ui.game.menu.build_menu.items.craft_and_build.tip_description',
         });
      },

      // ACE: added custom tooltips
      _placeItemOrItemType: function (placementType, toolName, item, quality, options) {
         var self = this;
         var placementCall = placementType == 'item' ? 'stonehearth:choose_place_item_location' : 'stonehearth:choose_place_item_type_location';
         var opts = options || {};

         radiant.call('stonehearth:check_can_place_item', item, quality)
            .done(function (response) {
               radiant.call('stonehearth_ace:get_custom_tooltip_command', item, 'stonehearth:ui.game.menu.build_menu.items.place_item')
               .done(function (r) {
                  var custom_tooltips = r.custom_tooltips;
                  var tip_title = opts.tip_title || custom_tooltips.tip_title || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_title';
                  var tip_description = opts.tip_description || custom_tooltips.tip_description || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_description';
                  var tip_bindings = opts.tip_bindings || custom_tooltips.tip_bindings || {left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'};
                  self.showTipWithKeyBindings(tip_title, tip_description, tip_bindings);

                  App.setGameMode(opts.gameMode || 'place');
                  return self._callTool(toolName, function() {
                     return radiant.call(placementCall, item, quality, null, options)
                        .done(function(response) {
                           radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} )
                           if ((placementType == 'itemType') && (response.more_items || opts.repeat_tool)) {
                              self._placeItemOrItemType(placementType, toolName, item, quality, options);
                           } else {
                              self.hideTip();
                           }
                        })
                        .fail(function(response) {
                           //App.setGameMode('normal');
                           self.hideTip();
                        })
                        .always(function(response) {
                           if (placementType == 'item') {
                              App.setGameMode('normal');
                              self.hideTip();
                           }
                        });
                  });
               });
            })
            .fail(function(response) {
               self.showTip(i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_title'),
                            i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_description', {
                               tag: i18n.t("i18n(stonehearth:ui.game.unit_frame.placement_tags." + response.placement_tag + ")"),
                               num: response.num_placed || 0,
                               max: response.max_placeable || 0
                            }),
                            {warning: 'warning'});
            });
      },

      giveCombatCommand: function(command, uri) {
         var self = this;
         return this._callTool('execute_combat_command', function(){
            return radiant.call_obj('stonehearth.combat_commands', 'execute_combat_command', command, uri)
               .done(function(response){
                  //TODO: play sound here
                  self.giveCombatCommand(command, uri);
               });
         });
      },

      // item is a reference to an actual entity, not a class of entities like stonehearth:furniture:comfy_bed
      undeployItem: function(item) {
         var self = this;

         return this._callTool('undeployItem', function() {
            return radiant.call('stonehearth:undeploy_item', item);
         });
      },

      // item is a reference to an actual entity, not a class of entities like stonehearth:furniture:comfy_bed
      undeployGolem: function (item) {
         var self = this;

         return this._callTool('undeployItem', function() {
            return radiant.call('stonehearth:undeploy_golem', item);
         });
      },

      // item type is a uri, not an item entity
      buildLadder: function() {
         var self = this;

         var tip = self.showTip('stonehearth:ui.game.menu.build_menu.items.build_ladder.tip_title', 'stonehearth:ui.game.menu.build_menu.items.build_ladder.tip_description',
            {i18n: true});

         App.setGameMode('place');
         return this._callTool('buildLadder', function() {
            return radiant.call_obj(self._build_editor, 'build_ladder')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.buildLadder();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      // item type is a uri, not an item entity
      removeLadder: function(ladder) {
         return radiant.call_obj(this._build_service, 'remove_ladder_command', ladder);
      },

      boxHarvestResources: function() {
         var self = this;
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.harvest.tip_title',
               'stonehearth:ui.game.menu.harvest_menu.items.harvest.tip_description', {i18n : true});

         return this._callTool('boxHarvestResources', function() {
            return radiant.call('stonehearth:box_harvest_resources')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxHarvestResources();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      boxClearItem: function() {
         var self = this;
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.clear_item.tip_title',
               'stonehearth:ui.game.menu.harvest_menu.items.clear_item.tip_description', {i18n : true});

         var handleClearing = function(args) {
            radiant.call('stonehearth:server_box_clear_resources', args.box, args.should_clear);
            self.boxClearItem();
         }

         return this._callTool('boxClearItem', function() {
            return radiant.call('stonehearth:box_clear_resources')
               .done(function(response){
                  //put up a dialog asking for confirmation, if there are entities in the box

                  if (response.has_entities) {
                     App.gameView.addView(App.StonehearthConfirmView,
                     {
                        title : i18n.t('stonehearth:ui.game.menu.harvest_menu.items.clear_item.confirm_title'),
                        message : i18n.t('stonehearth:ui.game.menu.harvest_menu.items.clear_item.confirm_message'),
                        buttons : [
                           {
                              id: 'confirmClear',
                              label: i18n.t('stonehearth:ui.game.menu.harvest_menu.items.clear_item.confirm_clear'),
                              click: handleClearing,
                              args: {box : response.box, should_clear : true}
                           },
                           {
                              id: 'cancelClear',
                              label: i18n.t('stonehearth:ui.game.menu.harvest_menu.items.clear_item.confirm_clear_no'),
                              click: handleClearing,
                              args: {box : response.box, should_clear : false}
                           }
                        ]
                     });
                  } else {
                     self.boxClearItem();
                  }
               })
               .fail(function(response){
                  self.hideTip(tip);
               });
         });
      },

      boxLootItems: function() {
         var self = this;
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.loot_item.tip_title',
               'stonehearth:ui.game.menu.harvest_menu.items.loot_item.tip_description', {i18n : true});

         return this._callTool('boxLootItems', function() {
            return radiant.call('stonehearth:box_loot_items')
               .done(function(response){
                  radiant.call('stonehearth:server_box_loot_items', response.box)
                  self.boxLootItems();
               })
               .fail(function(response){
                  self.hideTip(tip);
               });
         });
      },

      select_combat_party: function(party_id) {
         var self = this;
         if (self._partyEditor != null && !self._partyEditor.isDestroyed && !self._partyEditor.isDestroying) {
            self.hidePartyEditor();
         }
         radiant.call_obj('stonehearth.party_editor', 'select_party_by_population_name', party_id);
      },

      boxCancelTask: function() {
         var self = this;
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.cancel_task.tip_title',
               'stonehearth:ui.game.menu.harvest_menu.items.cancel_task.tip_description', {i18n : true});

         return this._callTool('boxCancelTask', function() {
            return radiant.call('stonehearth:box_cancel_task')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxCancelTask();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      createStockpile: function() {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth:ui.game.menu.zone_menu.items.create_stockpile.tip_title',
               'stonehearth:ui.game.menu.zone_menu.items.create_stockpile.description', { i18n: true });

         return this._callTool('createStockpile', function() {
            return radiant.call('stonehearth:choose_stockpile_location')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  radiant.call('stonehearth:select_entity', response.stockpile);
                  self.createStockpile();
               })
               .fail(function(response) {
                  self.hideTip(tip);
                  console.log('stockpile created!');
               });
         });
      },

      createQuestStorage: function() {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth_ace:ui.game.menu.zone_menu.items.create_quest_storage.tip_title',
               'stonehearth_ace:ui.game.menu.zone_menu.items.create_quest_storage.tip_description', { i18n: true });

         return this._callTool('createQuestStorage', function() {
            return radiant.call('stonehearth_ace:choose_quest_storage_zone_location')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  radiant.call('stonehearth:select_entity', response.quest_storage);
                  self.createQuestStorage();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      //TODO: make this available ONLY after a farmer has been created
      // ACE: added fieldType parameter
      createFarm: function(fieldType) {
         var self = this;

         App.setGameMode('farm');
         var tip = self.showTipWithKeyBindings('stonehearth:ui.game.menu.zone_menu.items.create_farm.tip_title',
               'stonehearth_ace:ui.game.menu.zone_menu.items.create_farm.tip_description',
               {left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'});

         return this._callTool('createFarm', function(){
            return radiant.call('stonehearth:choose_new_field_location', fieldType)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               radiant.call('stonehearth:select_entity', response.field);
               self.createFarm(fieldType);
            })
            .fail(function(response) {
               self.hideTip(tip);
               console.log('new field created!');
            });
         });
      },

      createTrappingGrounds: function() {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth:ui.game.menu.zone_menu.items.create_trapping_grounds.tip_title',
               'stonehearth:ui.game.menu.zone_menu.items.create_trapping_grounds.tip_description', { i18n: true });

         return this._callTool('createTrappingGrounds', function() {
            return radiant.call('stonehearth:choose_trapping_grounds_location')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  radiant.call('stonehearth:select_entity', response.trapping_grounds);
                  self.createTrappingGrounds();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      createPasture: function() {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth:ui.game.menu.zone_menu.items.create_pasture.tip_title',
               'stonehearth:ui.game.menu.zone_menu.items.create_pasture.tip_description', { i18n: true });

         return this._callTool('createPasture', function() {
            return radiant.call('stonehearth:choose_pasture_location')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  radiant.call('stonehearth:select_entity', response.pasture);
                  self.createPasture();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },


      mineBasic: function () {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.mine_basic.tip_title',
               'stonehearth:ui.game.menu.harvest_menu.items.mine_basic.tip_description', { i18n: true });

         return this._callTool('digDown', function () {
            return radiant.call('stonehearth:designate_mining_zone', 'cube')
               .done(function (response) {
                  radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:place_structure' });
                  self.mineBasic();
               })
               .fail(function (response) {
                  self.hideTip(tip);
               });
         });
      },

      mineCustom: function() {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTip('stonehearth:ui.game.menu.harvest_menu.items.mine_custom.tip_title',
                                'stonehearth:ui.game.menu.harvest_menu.items.mine_custom.tip_description', { i18n: true });
         
         return this._callTool('digDown', function () {
            return radiant.call('stonehearth:designate_mining_zone', 'custom_block')
                  .done(function(response) {
                        radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                        self.mineCustom();
                     })
                  .fail(function(response) {
                        self.hideTip(tip);
                     });
            });
      },

      undo: function () {
         radiant.call_obj(this._build_service, 'undo_command')
      },

      drawTemplate: function(precall, template, ignoreQuality) {
         var self = this;

         self.showTipWithKeyBindings('stonehearth:ui.game.build_mode.overhead_tips.draw_template_title',
                                     'stonehearth:ui.game.build_mode.overhead_tips.draw_template_description',
                                     { left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'});

         return this._callTool('drawTemplate', function() {
            return radiant.call_obj(self._build_editor, 'place_template', template, ignoreQuality)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .always(function(response) {
                  self.hideTip();
               });
         }, precall);
      },

      buildWall: function(column, wall) {
         var self = this;

         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.wall_segment_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.wall_segment_tip_description', { i18n: true });
            return radiant.call_obj(self._build_editor, 'place_new_wall', column, wall)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         }
      },

      buildFloor : function(floorBrush, floorCategory) {
         var self = this;
         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.build_floor_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.build_floor_tip_description', { i18n: true });
            return radiant.call_obj(self._build_editor, 'place_new_floor', floorBrush, floorCategory)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         };
      },

      deleteStructure : function() {
         var self = this;
         var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.delete_structure_tip_title',
                                'stonehearth:ui.game.build_mode.overhead_tips.delete_structure_tip_description',
                                { i18n: true });

         return this._callTool('deleteStructure', function() {
            return radiant.call_obj(self._build_editor, 'delete_structure')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.deleteStructure();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },

      eraseStructure : function() {
         var self = this;
         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.erase_structure_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.erase_structure_tip_description', { i18n: true });
            return radiant.call_obj(self._build_editor, 'erase_structure')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         };
      },

      callTool: function(toolStruct) {
         return this._callTool(toolStruct.toolId, toolFn, toolStruct.precall);
      },

      buildRoad: function(roadBrush, curbBrush) {
         var self = this;

         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.build_road_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.build_road_tip_description', { i18n: true });

            return radiant.call_obj(self._build_editor, 'place_new_road', roadBrush, curbBrush)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
            };
      },

      growRoof: function(roof, option) {
         var self = this;

         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.roof_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.roof_tip_description', { i18n: true });

            return radiant.call_obj(self._build_editor, 'grow_roof', roof, option)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .always(function (response) {
                  self.hideTip(tip);
               });
            };
      },

      drawStairs: function(option) {
         var self = this;

         return function () {
            self.showTipWithKeyBindings('stonehearth:ui.game.build_mode.overhead_tips.stairs_tip_title',
                                        'stonehearth:ui.game.build_mode.overhead_tips.stairs_tip_description',
                                        { left_binding: 'build:rotate:left', right_binding: 'build:rotate:right' });

            return radiant.call_obj(self._build_editor, 'add_stairs', option)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               })
               .always(function (response) {
                  self.hideTip();
               });
            };
      },

      setAddStairsOptions: function(options) {
         return radiant.call_obj(this._build_editor, 'set_add_stairs_options', options);
      },

      applyConstructionDataOptions: function(blueprint, options) {
         return radiant.call_obj(this._build_service, 'apply_options_command', blueprint.__self, options);
      },

      getCost: function(building, includingFinished) {
         return radiant.call_obj(this._build_service, 'get_cost_command', building, includingFinished);
      },

      setGrowRoofOptions: function(options) {
         return radiant.call_obj(this._build_editor, 'set_grow_roof_options', options);
      },

      growWalls: function(column, wall) {
         var self = this;

         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.raise_walls_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.raise_walls_tip_description', { i18n: true } );
            return radiant.call_obj(self._build_editor, 'grow_walls', column, wall)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'});
               })
               .always(function (response) {
                  self.hideTip();
               });
         };
      },

      addDoodad: function (doodadUri, doodadQuality) {
         var self = this;

         return function() {
            var tip = self.showTip('stonehearth:ui.game.build_mode.overhead_tips.doodad_tip_title', 'stonehearth:ui.game.build_mode.overhead_tips.doodad_tip_description', { i18n: true });
            return radiant.call_obj(self._build_editor, 'add_doodad', doodadUri, doodadQuality)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.hideTip();
               });
         };
      },

      buildRoom: function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
         var self = this;
         return this._callTool('buildRoom', function() {
            return radiant.call_obj(self._build_editor, 'create_room');
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
         });
      },

      _townMenu: null,
      showTownMenu: function(show) {
      // toggle the town menu
         if (!this._townMenu || this._townMenu.isDestroyed) {
            this._townMenu = App.gameView.addView(App.StonehearthTownView);
         } else {
            this._townMenu.destroy();
            this._townMenu = null;
         }
      },

      _citizensManager: null,
      showCitizenManager: function(hideOnCreate) {
         var self = this;
         if (!self._citizensManager || self._citizensManager.isDestroyed || self._citizensManager.isDestroying) {
            self._citizensManager = App.gameView.addView(App.StonehearthCitizensView, { hideOnCreate: hideOnCreate });
         } else if(!hideOnCreate) {
            if (self._citizensManager.get('isVisible')) {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:jobs_close' });
               self._citizensManager.hide();
            } else {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:jobs_open' });
               self._citizensManager.show();
            }
         }
      },

      _tasksManager: null,
      showTasksManager: function(show) {
         // toggle the tasksManager
         if (!this._tasksManager || this._tasksManager.isDestroyed) {
            this._tasksManager = App.gameView.addView(App.StonehearthTasksView);
         } else {
            this._tasksManager.destroy();
            this._tasksManager = null;
         }
      },

      _redAlertWidget: null,
      enableAlertMode: function() {
         radiant.call_obj('stonehearth.town', 'town_alert_enabled_command')
            .done(function(response) {
               if (response.enabled) {
                  radiant.call_obj('stonehearth.town', 'disable_town_alert_command');
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:scenarios:redalert_off'});
                  if (self._redAlertWidget) {
                     self._redAlertWidget.destroy();
                     self._redAlertWidget = null;
                  }
               } else {
                  radiant.call_obj('stonehearth.town', 'enable_town_alert_command');
                  if (!self._redAlertWidget) {
                     self._redAlertWidget = App.gameView.addView(App.StonehearthRedAlertWidget);
                  }
               }
            })
      },

      showRedAlert: function() {
         if (!self._redAlertWidget) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:scenarios:redalert'} );
            self._redAlertWidget = App.gameView.addView(App.StonehearthRedAlertWidget);
         }
      },

      collectCpuProfile: function(profileLength) {
         radiant.call('radiant:collect_cpu_profile', profileLength)
      },

      profileLongTicks: function() {
         return radiant.call('radiant:toggle_profile_long_ticks')
      },

      setTime: function(time) {
         radiant.call('stonehearth:cl_set_time', time);
      },

      _multiplayerMenu: null,
      showMultiplayerMenu: function(hideOnCreate) {
         if (!this._multiplayerMenu || this._multiplayerMenu.isDestroying || this._multiplayerMenu.isDestroyed) {
            this._multiplayerMenu = App.gameView.addView(App.StonehearthMultiplayerMenuView, {hideOnCreate: hideOnCreate});
         } else if (!hideOnCreate) {
            if (this._multiplayerMenu.get('isVisible')) {
               this._multiplayerMenu.hide();
            } else {
               this._multiplayerMenu.show();
            }
         }
      },

      _modsMatchModal: null,
      showModsMatchModal: function(key) {
         var self = this;

         if (self._modsMatchModal != null && !self._modsMatchModal.isDestroyed) {
            self._modsMatchModal.destroy();
            self._modsMatchModal = null;
         }

         radiant.call("radiant:saved_mods_match_loaded_game", key)
            .done(function(result) {
               if (result.success) {
                  radiant.call("radiant:client:load_game", key);
               } else {
                  // open the load game mod sync screen
                  if (result.reason == "different_mods") {
                     if (App.getCurrentScreenName() == 'game') {
                        self._modsMatchModal = App.gameView.addView(App.StonehearthLoadMatchModsView, { _mods: result.mods, _key: key });
                     } else if (App.getCurrentScreenName() == 'shell') {
                        self._modsMatchModal = App.shellView.addView(App.StonehearthLoadMatchModsView, { _mods: result.mods, _key: key });
                     }
                  } else if (result.reason == "different_mod_order") {
                     if (App.getCurrentScreenName() == 'game') {
                        self._modsMatchModal = App.gameView.addView(App.StonehearthLoadMatchModOrderView, { _savedMods: result.mods.mod_order, _loadedMods: result.loaded_mod_order, _key: key });
                     } else if (App.getCurrentScreenName() == 'shell') {
                        self._modsMatchModal = App.shellView.addView(App.StonehearthLoadMatchModOrderView, { _savedMods: result.mods.mod_order, _loadedMods: result.loaded_mod_order, _key: key });
                     }
                  }
               }
            });
      },

      _tradeMenu: null,
      showTradeMenu: function(trade) {
         if (!this._tradeMenu || this._tradeMenu.isDestroyed) {
            this._tradeMenu = App.gameView.addView(App.StonehearthTradeMenuView, { uri: trade });
         } else {
            this._tradeMenu.set('uri', trade);
         }
      },

      closeTradeMenu: function() {
         if (this._tradeMenu && !this._tradeMenu.isDestroyed) {
            this._tradeMenu.destroy();
            this._tradeMenu = null;
         }
      },

      _showExitConfirmDialog: function(menuLocSubLocation, acceptCallback, viewName) {
      var self = this;
      if (!viewName || !App[viewName]) {
         viewName = 'gameView';
      }

      App[viewName].addView(App.StonehearthConfirmView,
         {
            title : i18n.t('stonehearth:ui.game.esc_menu.' + menuLocSubLocation + '.title'),
            message : i18n.t('stonehearth:ui.game.esc_menu.' + menuLocSubLocation + '.message'),
            buttons : [
               {
                  id: 'yesButton',
                  label: i18n.t('stonehearth:ui.game.esc_menu.' + menuLocSubLocation + '.yes_button'),
                  click: acceptCallback
               },
               {
                  id: 'cancel',
                  label: i18n.t('stonehearth:ui.game.esc_menu.' + menuLocSubLocation + '.cancel_button')
               }
            ]
         });
      },

      openWorkshopItem: function(itemId) {
         radiant.call('radiant:open_url_external', 'http://steamcommunity.com/sharedfiles/filedetails/?id=' + itemId); //workshop url
      },

      _settingsMenu: null,
      showSettings: function(hideOnCreate) {
         if (!this._settingsMenu || this._settingsMenu.isDestroying || this._settingsMenu.isDestroyed) {
            if (App.getCurrentScreenName() == 'game') {
               this._settingsMenu = App.gameView.addView(App.SettingsView, {hideOnCreate: hideOnCreate});
            } else {
               this._settingsMenu = App.shellView.addView(App.SettingsView, {hideOnCreate: hideOnCreate, isMainMenu: true});
            }
         } else if(!hideOnCreate) {
            if (this._settingsMenu.get('isVisible')) {
               this._settingsMenu.hide();
            } else {
               this._settingsMenu.show();
            }
         }
      },

      _saveMenu: null,
      showSaveMenu: function(hideOnCreate) {
         if (!this._saveMenu || this._saveMenu.isDestroying || this._saveMenu.isDestroyed) {
            if (App.getCurrentScreenName() == 'game') {
               this._saveMenu = App.gameView.addView(App.SaveView, {hideOnCreate: hideOnCreate});
            } else {
               this._saveMenu = App.shellView.addView(App.SaveView, {hideOnCreate: hideOnCreate, hideSaveButtons: true});
            }
         } else if(!hideOnCreate) {
            if (this._saveMenu.get('isVisible')) {
               this._saveMenu.hide();
            } else {
               this._saveMenu.show();
            }
         }
      },

      getSaveView: function() {
         if (!this._saveMenu) {
            this.showSaveMenu(true);
         }

         return this._saveMenu;
      },

      quitToMainMenu: function(viewName, view) {
         var doQuitToMainMenu = function() {
            if (viewName == 'shellView') {
               // don't reload the whole game if we're just coming from the game creation views
               App.navigate('shell/title');
               if (view) {
                  view.destroy();
               }
            }
            else {
               radiant.call('radiant:client:return_to_main_menu');
            }
         };

         this._showExitConfirmDialog('return_to_menu_dialog', doQuitToMainMenu, viewName);
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click' });
      },

      exitGame: function(viewName) {
         var doExit = function() {
            radiant.call_obj('stonehearth.analytics', 'game_exit_command')
               .always(function(e) {
                  radiant.call('radiant:exit');
               });
         };

         this._showExitConfirmDialog('exit_confirm_dialog', doExit, viewName);
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click' });
      },

      // ACE: added various functions, mostly triggered through the start menu
      showMercantileView: function(hideOnCreate) {
         // toggle the mercantile view
         var self = this;
         if (!self._mercantileView || self._mercantileView.isDestroyed || self._mercantileView.isDestroying) {
            self._mercantileView = App.gameView.addView(App.StonehearthAceMerchantileView, { hideOnCreate: hideOnCreate });
         } else if(!hideOnCreate) {
            if (self._mercantileView.get('isVisible')) {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:carpenter_menu:menu_closed' });
               self._mercantileView.hide();
            } else {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth_ace:sounds:ui:mercantile_menu:open' });
               self._mercantileView.show();
            }
         }
      },

      // ACE: added various functions, mostly triggered through the start menu
      showPetManager: function(hideOnCreate) {
         // toggle the pet manager view
         var self = this;
         if (!self._petManager || self._petManager.isDestroyed || self._petManager.isDestroying) {
            self._petManager = App.gameView.addView(App.StonehearthAcePetsView, { hideOnCreate: hideOnCreate });
         } else if(!hideOnCreate) {
            if (self._petManager.get('isVisible')) {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:carpenter_menu:menu_closed' });
               self._petManager.hide();
            } else {
               radiant.call('radiant:play_sound', { 'track': 'stonehearth_ace:sounds:ui:mercantile_menu:open' });
               self._petManager.show();
            }
         }
      },

      boxHarvestAndReplant: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.harvest_and_replant.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.harvest_and_replant.tip_description', {i18n : true});
   
         return self._callTool('boxHarvestAndReplant', function() {
            return radiant.call('stonehearth_ace:box_harvest_and_replant_resources')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxHarvestAndReplant();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxMove: function() {
         var self = this;
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_move.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_move.tip_description', {i18n : true});
   
         return self._callTool('boxMove', function() {
            return radiant.call('stonehearth_ace:box_move')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxMove();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxUndeploy: function() {
         var self = this;
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_undeploy.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_undeploy.tip_description', {i18n : true});
   
         return self._callTool('boxUndeploy', function() {
            return radiant.call('stonehearth_ace:box_undeploy')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxUndeploy();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxCancelPlacement: function() {
         var self = this;
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_cancel_placement.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_cancel_placement.tip_description', {i18n : true});
   
         return self._callTool('boxCancelPlacement', function() {
            return radiant.call('stonehearth_ace:box_cancel_placement')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxCancelPlacement();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxEnableAutoHarvest: function() {
         var self = this;
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_enable_auto_harvest.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_enable_auto_harvest.tip_description', {i18n : true});
   
         return self._callTool('boxEnableAutoHarvest', function() {
            return radiant.call('stonehearth_ace:box_enable_auto_harvest')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxEnableAutoHarvest();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxDisableAutoHarvest: function() {
         var self = this;
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_disable_auto_harvest.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_disable_auto_harvest.tip_description', {i18n : true});
   
         return self._callTool('boxDisableAutoHarvest', function() {
            return radiant.call('stonehearth_ace:box_disable_auto_harvest')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxDisableAutoHarvest();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxHunt: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_hunt.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_hunt.tip_description', {i18n : true});
   
         return self._callTool('boxHunt', function() {
            return radiant.call('stonehearth_ace:box_hunt')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxHunt();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      buildWell: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_description',
            {i18n: true});
   
         App.setGameMode('place');
         return self._callTool('buildWell', function() {
            return radiant.call('stonehearth_ace:place_buildable_entity', 'stonehearth_ace:construction:simple:water_well_ghost')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.buildWell();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      buildFence: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_description',
            {i18n: true});
   
         //App.setGameMode('fence');
         //self.showBuildFenceView();
         return self._callTool('buildFence', function() {
            // TODO: make fence pieces customizable
            var fencePieces = [
               'stonehearth:construction:picket_fence:end',
               'stonehearth:construction:picket_fence:bar:single',
               'stonehearth:construction:picket_fence:bar:double'
            ];
            return radiant.call('stonehearth_ace:choose_fence_location_command', fencePieces)
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.buildFence();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      boxForage: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.harvest_menu.items.box_forage.tip_title',
               'stonehearth_ace:ui.game.menu.harvest_menu.items.box_forage.tip_description', {i18n : true});
   
         return self._callTool('boxForage', function() {
            return radiant.call('stonehearth_ace:box_forage')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
                  self.boxForage();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      },
   
      buildFishTrap: function() {
         var self = this;
   
         var tip = self.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_description',
            {i18n: true});
   
         App.setGameMode('place');
         return self._callTool('buildFishTrap', function() {
            return radiant.call('stonehearth_ace:place_buildable_entity', 'stonehearth_ace:trapper:fish_trap_anchor_ghost')
               .done(function(response) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
                  self.buildFishTrap();
               })
               .fail(function(response) {
                  self.hideTip(tip);
               });
         });
      }
   });
   App.stonehearthClient = new StonehearthClient();
})();
