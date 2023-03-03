$.widget( "stonehearth.stonehearthMenu", {

   _dataToMenuItemMap: {},
   _foundjobs: {},

   options: {
      // callbacks
      data: {},

      click: function(item) {
         // console.log('Clicked item: ' + item);
      },

      hide: function() {
         // console.log('menu hidden');
      }
   },

   hideMenu: function() {
      //this.menu.find('.menuItemGroup').hide();
      this.showMenu(null);
      if (this.options.hide) {
         this.options.hide();
      }
      this._currentOpenMenu = null;
   },

   getMenu: function() {
      return this._currentOpenMenu;
   },

   showMenu: function(id) {
      this.menu.find('.menuItemGroup').on('webkitAnimationEnd', function(e) {
         var el = $(e.target);
         if (el && el.hasClass('down')) {
            el.hide();
         }
         //console.log("animationend");
      });
      this.menu.find('.menuItemGroup').each(function(_, el) {
         if ($(el).hasClass('up')) {
            $(el).removeClass('up').addClass('down');
         }
      });
      this.menu.find('.selected').removeClass('selected');

      var nodeData;

      if (id) {
         var subMenu = '[parent="' + id +'"]';
         var subMenuElement = this.menu.find(subMenu);
         subMenuElement.removeClass('down')
         subMenuElement.show();
         subMenuElement.addClass('up');
         nodeData = this._dataToMenuItemMap[id]

         var menuMode = this.menu.find('.rootGroup').find('#' + id);
         if (menuMode) {
            menuMode.addClass('selected');
         }
      }
      else if (this._currentOpenMenu) {
         App.setGameMode('normal');
      }

      this._currentOpenMenu = id;

      // ACE: commented this part out
      // $(top).trigger("start_menu_activated", {
      //    id: id,
      //    nodeData: nodeData
      // });
   },

   /*
   setGameMode: function(mode) {
      if (mode == "normal" && this.getGameMode() != "normal") {
         this.hideMenu();
         return;
      }

      if (this.getGameMode() == mode ) {
         return;
      }

      var self = this;
      $.each(this._dataToMenuItemMap, function(key, node) {
         if (node.game_mode == mode) {

            if (self._currentOpenMenu != key) {
               self.showMenu(key);
            }
         }
      });
   },
   */

   getOpenMenu: function() {
      return this._currentOpenMenu;
   },

   getGameMode: function() {
      if (this._currentOpenMenu) {
         return this._dataToMenuItemMap[this._currentOpenMenu].game_mode
      } else {
         return null;
      }
   },

   lockAllItems: function() {
      var self = this;
      var item = this.element.find('.unlockable');
      if (item.length > 0) {
         item.addClass('locked');
         item.each(function() {
            self._buildTooltip($(this));
         });
      }
   },

   unlockItem: function(attributeName, attributeValue) {
      var self = this;
      var item = this.element.find('[' + attributeName + '=' + attributeValue + ']');
      if (item.length > 0) {
         item.removeClass('locked');
         item.each(function() {
            self._buildTooltip($(this));
         });
         if (item.attr('menu_action') == 'show_crafter_ui') {
            App.workshopManager.createWorkshop(attributeValue.replace(/\\:/g, ':'));
         }
      }
   },

   unlock: function(jobAlias) {
      var self = this;
      var alias = jobAlias.split(":").join('\\:');
      var item = this.element.find('[job=' + alias + ']');
      if (item.length > 0) {
         item.removeClass('locked');
         item.each(function() {
            self._buildTooltip($(this));
         });
      }
   },

   setWarning: function(findString, warning_text) {
      var self = this;
      var items = this.element.find(findString);
      if (items.length > 0) {
         items.each(function() {
            var item = $(this);
            item.warning_text = warning_text;
            self._buildTooltip(item);
         });
      }
   },

   _create: function() {
      var self = this;
      App.gameMenu = this;

      this._dataToMenuItemMap = {};
      this.menu = $('<div>').addClass('stonehearthMenu');

      this._addItems(this.options.data)

      // a bit of a hack. remove the root group then append it, so it's at the bottom of the menu div
      //var rootGroup = this.menu.find('.rootGroup');
      //this.menu.detach('.rootGroup');
      //this.menu.append(rootGroup);

      this.element.append(this.menu);

      this.hideMenu();

      this.menu.on('click', '.menuItem', function() {

         // close all open tooltips
         self.menu.find('.menuItem').tooltipster('hide');

         var menuItem = $(this);
         var id = menuItem.attr('id');
         var nodeData = self._dataToMenuItemMap[id]

         if (menuItem.hasClass('locked')) {
            //XXX, play a "bonk" sound
            return;
         }

         if (nodeData.clickSound) {
            radiant.call('radiant:play_sound', {'track' : nodeData.clickSound});
         }

         // deactivate any tools that are open
         App.stonehearthClient.deactivateAllTools();

         // if this menu has sub-items, hide any menus that are open now so we can show a new one
         var isOpening = false;
         if (nodeData.items) {
            if (self.getMenu() == id) {
               radiant.call('radiant:play_sound', {'track' : nodeData.menuHideSound} );
               self.hideMenu();
            } else {
               radiant.call('radiant:play_sound', {'track' : nodeData.menuShowSound} );
               self.showMenu(id);
               isOpening = true;
            }
         } else if (nodeData.has_custom_menu) {
            if (self.getMenu() == id) {
               self.menu.find('.menuItemGroup').on('webkitAnimationEnd', function (e) {
                  var el = $(e.target);
                  if (el && el.hasClass('down')) {
                     el.hide();
                  }
               });
               self.menu.find('.menuItemGroup').each(function (_, el) {
                  if ($(el).hasClass('up')) {
                     $(el).removeClass('up').addClass('down');
                  }
               });
               self.menu.find('.selected').removeClass('selected');
               self._currentOpenMenu = null;
            } else {
               self.showMenu(null);
               self.menu.find('.rootGroup').find('#' + id).addClass('selected');
               self._currentOpenMenu = id;
               isOpening = true;
            }
         } else {
            if (!nodeData.sticky) {
               self.hideMenu();
            }
         }

         // show the parent menu for this menu item
         var parent = menuItem.parent();
         var grandParentId = parent.attr('parent');
         if (grandParentId && nodeData.ensure_parent_menu != false) {
            self.showMenu(grandParentId);
         }

         self._applyGameMode(nodeData, isOpening);

         if (self.options.click) {
            self.options.click(id, nodeData);
         }
         return false;
      });

      this.menu.on( 'click', '.close', function() {
         self.showMenu(null);
         
         var menuItem = $(this);
         var id = menuItem.attr('id');
         var nodeData = self._dataToMenuItemMap[id]
         self._applyGameMode(nodeData, false);
      });

      /*
      $(document).click(function() {
         if (!App.stonehearthClient.getActiveTool()) {
            self.hideMenus();
         }
      });
      */
   },

   // ACE: added ordinal sorting to nodes and required_ability option for locking
   _addItems: function(nodes, parentId, name, depth, parent) {
      if (!nodes) {
         return;
      }

      if (!depth) {
         depth = 0;
      }
      
      // sort the nodes by their ordinal property, if they have one
      function compare(a, b) {
         var aIsNum = typeof(a.ordinal) == 'number';
         var bIsNum = typeof(b.ordinal) == 'number';
         if (aIsNum && bIsNum) {
            return a.ordinal < b.ordinal ? -1 : (a.ordinal > b.ordinal ? 1 : 0);
         }
         else if(aIsNum) {
            return -1;
         }
         else if(bIsNum) {
            return 1;
         }
         else {
            return 0;
         }
      }

      var nodesArr = [];
      radiant.each(nodes, function(key, node) {
         if (node.icon) {
            node.key = key;
            nodesArr.push(node);
         }
      });
      nodesArr.sort(compare);
      nodes = nodesArr;

      var self = this;
      var groupClass = depth == 0 ? 'rootGroup' : 'menuItemGroup'
      var el = $('<div>').attr('parent', parentId)
                         .addClass(groupClass)
                         .addClass('depth' + depth)
                         .append('<div class=close></div>')
                         .appendTo(self.menu);

      // add a special background div for the root group
      if (depth == 0) {
         el.append('<div class=background></div>');
      }

      $.each(nodes, function(_, node) {
         var key = node.key;
         self._dataToMenuItemMap[key] = node;

         if (self.options.shouldHide) {
            if (self.options.shouldHide(key, node)) {
               return true; // return true to continue, because jquery.
            }
         }

         var item = $('<div>')
                     .attr('id', key)
                     .attr('hotkey_action', node.hotkey_action || '')
                     .addClass('menuItem')
                     .addClass('button')
                     .addClass(node.class)
                     .appendTo(el);

         var icon = $('<img>')
                     .attr('src', node.icon)
                     .addClass('icon')
                     .appendTo(item);

         item.append('<div class="notificationPip"></div>');
         item.append('<div class="badgeNum"></div>');

         if ((node.items || node.has_custom_menu) && depth == 0) {
            item.append('<img class=arrow>')
         }

         if (node.required_job) {
            item.addClass('unlockable');
            item.attr('job', node.required_job);
            item.addClass('locked'); // initially lock all nodes that require a job. The user of the menu will unlock them
         }

         if (node.required_job_role) {
            item.addClass('unlockable');
            item.attr('job_role', node.required_job_role);
            item.addClass('locked'); // initially lock all nodes that require a job role. The user of the menu will unlock them
         }

         if (node.required_ability) {
            item.addClass('unlockable');
            item.attr('unlocked_ability', node.required_ability);
            item.addClass('locked'); // initially lock all nodes that require an unlocked ability. The user of the menu will unlock them
         }

         if (node.menu_action) {
            item.attr('menu_action', node.menu_action);
         }

         self._buildTooltip(item);

         node.parent = parent;

         if (node.items) {
            self._addItems(node.items, key, node.name, depth + 1, node);
         }
      });

      if (name) {
         $('<div>').html(i18n.t(name))
                   .addClass('header')
                   .appendTo(el);
      }
   },

   _buildTooltip: function(item) {
      var node = this._dataToMenuItemMap[item.attr('id')];

      var description = i18n.t(node.description);
      if (node.required_job_text && item.hasClass('locked')) {
         description = description + '<span class=warn>' + i18n.t(node.required_job_text) + '</span>';
      };
      if (item.warning_text) {
         description = description + '<span class=warn>' + i18n.t(item.warning_text) + '</span>';
      };

      App.hotkeyManager.makeTooltipWithHotkeys(item, node.name, description);
   },

   _applyGameMode: function(node, enable = true) {
      var self = this;
      // when a node is clicked on, go through that node and its ancestry until a gamemode is found and apply that gamemode
      // when a node is clicked off, go through that node's ancestry until a gamemode is found and apply it; otherwise, reset gamemode
      var curNode = node;
      while (curNode) {
         if (curNode != node || enable) {
            if (self._tryApplyGameMode(curNode)) {
               return;
            }
         }
         curNode = curNode.parent;
      }

      if (node.game_mode && !enable) {
         App.setGameMode('normal');
      }
   },

   _tryApplyGameMode: function(node) {
      if (node.game_mode) {
         App.setGameMode(node.game_mode);
         return true;
      }
   }
});
