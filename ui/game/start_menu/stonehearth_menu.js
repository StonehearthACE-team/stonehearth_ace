$.widget( "stonehearth.stonehearthMenu", $.stonehearth.stonehearthMenu, {

   _addItems: function(nodes, parentId, name, depth) {
      if (!nodes) {
         return;
      }

      if (!depth) {
         depth = 0;
      }
      
      // sort the nodes by their ordinal property, if they have one
      function compare(a, b) {
         if (a.ordinal && b.ordinal) {
            return a.ordinal < b.ordinal ? -1 : (a.ordinal > b.ordinal ? 1 : 0);
         }
         else if(a.ordinal) {
            return -1;
         }
         else if(b.ordinal) {
            return 1;
         }
         else {
            return 0;
         }
      }

      radiant.each(nodes, function(key, node) {
         node.key = key;
      });
      var nodesArr = radiant.map_to_array(nodes);
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
            item.addClass('locked'); // initially lock all nodes that require a job. The user of the menu will unlock them
         }

         if (node.menu_action) {
            item.attr('menu_action', node.menu_action);
         }

         self._buildTooltip(item);

         if (node.items) {
            self._addItems(node.items, key, node.name, depth + 1);
         }
      });

      if (name) {
         $('<div>').html(i18n.t(name))
                   .addClass('header')
                   .appendTo(el);
      }
   }
});
