App.StonehearthBuildingMaterialListView.reopen({
   _buildBrushList: function(colors, elementRoot) {
      var self = this;

      var colorsArr = [];
      _.forEach(colors, function(data, name) {
         data.name = name;
         data.title = i18n.t(data.display_name);
         colorsArr.push(data);
      });

      colorsArr.sort((a, b) => {
         if (a.ordinal != null && b.ordinal != null) {
            return a.ordinal - b.ordinal;
         }
         else if (a.ordinal != null) {
            return -1;
         }
         else if (b.ordinal != null) {
            return 1;
         }
         else {
            return ('' + a.title).localeCompare(b.title);
         }
      });

      _.forEach(colorsArr, function(data) {
         var name = data.name;
         var brush = $('<div>')
                     .addClass('brush')
                     .addClass('button')
                     .data('brush', name.toLowerCase())
                     .attr('title', data.title)
                     .attr('tooltip', i18n.t(data.display_name));
         if (data.icon) {
            brush = brush.css({ 'background-image' : 'url(' + data.icon + ')' });
         } else if (name) {
            brush = brush.css({ 'background-color' : name });
         }
         brush.append('<div class=selectBox />');

         elementRoot.append(brush);
      });
   }
});