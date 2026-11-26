// ACE: overall improvements made for the campaign browser
// big thanks to Alviun's AOC (I did peek inside their browser for inspiration, but not code was directly copied!)

$(document).on('stonehearthReady', function () {
   App.debugDock.addToDock(App.StonehearthCampaignBrowserIcon);
});

App.StonehearthCampaignBrowserIcon = App.View.extend({
   templateName: 'campaignBrowserIcon',
   classNames: ['debugDockIcon'],

   didInsertElement: function () {
      var self = this;
      $('#campaignBrowserIcon').tooltipster();
      self.$().on('click.campaignBrowser', function () {
         if (self._gameMasterView && !self._gameMasterView.isDestroyed) {
            self._gameMasterView.destroy();
         }
         self._gameMasterView = App.debugView.addView(App.StonehearthGameMasterView);
      });
   },

   willDestroyElement: function () {
      this.$().off('.campaignBrowser');
      this._super();
   }
});

// the most relevant change overall is the change from tree.size to nodeSize
// so each row has a predictable amount of room and nothing gets squeezed
// on a fixed size viewport
var D3Node = SimpleClass.extend({
   init: function (tree, uri) {
      this._tree = tree;
      this._uri = uri;
      this._children = [];
      this._visible = true;
      this._destroyed = false;
      this.x0 = 0;
      this.y0 = 0;
      this.name = 'loading...';
      this.data = null;
   },

   start_trace: function () {
      var self = this;

      if (self._destroyed || self._trace || !self._uri) {
         return;
      }

      self._trace = new RadiantTrace(self._uri)
         .progress(function (data) {
            if (!self._destroyed) {
               self._update(data);
            }
         })
         .fail(function (error) {
            if (!self._destroyed) {
               console.log('Failed to trace campaign browser node:', self._uri, error);
               self.name = ' unavailable';
               self._tree._update(self);
            }
         });

      $.each(self._children, function (_, child) {
         child.start_trace();
      });
   },

   toggle: function () {
      if (this._destroyed) {
         return;
      }

      this._visible = !this._visible;
      this._tree._update(this);
   },

   inspect: function () {
      if (!this._destroyed && this.data) {
         this._tree.options.inspect_node(this);
      }
   },

   _update: function (data) {
      var self = this;
      if (self._destroyed) {
         return;
      }

      self.name = self._tree.options.get_node_name(data) || '(unnamed)';
      self.data = data;

      var childUris = self._tree.options.get_node_children(data) || [];
      $.each(childUris, function (_, uri) {
         var exists = self._children.some(function (child) {
            return child._uri === uri;
         });

         if (!exists) {
            var child = new D3Node(self._tree, uri);
            self._children.push(child);
            child.start_trace();
         }
      });

      self._tree._update(self);
   },

   destroy: function () {
      if (this._destroyed) {
         return;
      }

      this._destroyed = true;
      $.each(this._children, function (_, child) {
         child.destroy();
      });
      this._children = [];

      if (this._trace) {
         this._trace.destroy();
         this._trace = null;
      }
   }
});

// a lot of stuff was "hardcoded" here and we're just making it more flexible
var D3CollapsableTree = SimpleClass.extend({
   init: function (options) {
      var self = this;

      self.options = options;
      self._destroyed = false;
      self._rowHeight = 42;
      self._depthWidth = 190;
      self._margin = { top: 30, right: 50, bottom: 30, left: 55 };
      self._duration = 180;

      self._root = new D3Node(self, options.root_node_uri);

      self._container = $(options.container);
      self._container
         .addClass('campaignBrowserViewport')
         .css({
            position: 'relative',
            overflow: 'auto',
            width: '100%',
            height: '100%',
            minHeight: '250px'
         });

      self._svg = d3.select(options.container)
         .append('svg')
         .attr('class', 'campaignBrowserTree')
         .attr('xmlns', 'http://www.w3.org/2000/svg');

      self._vis = self._svg.append('g')
         .attr('class', 'campaignBrowserCanvas');

      self._zoom = d3.behavior.zoom()
         .scaleExtent([0.25, 2.5])
         .on('zoom', function () {
            self._applyZoom();
         });

      self._svg.call(self._zoom)
         .on('dblclick.zoom', null);

      // toolbar appended after svg to render on top of things (pun intended)
      self._addToolbar();

      self._tree = d3.layout.tree()
         .children(function (node) {
            return node._visible ? node._children : [];
         })
         .nodeSize([self._rowHeight, self._depthWidth])
         .separation(function (a, b) {
            return a.parent === b.parent ? 1.0 : 1.15;
         });

      self._diagonal = d3.svg.diagonal()
         .projection(function (d) {
            return [d.y, d.x];
         });

      self._root.start_trace();
      self._update(self._root);
   },

   _addToolbar: function () {
      var self = this;
      var toolbar = $('<div class="campaignBrowserToolbar"></div>').css({
         position: 'absolute',
         top: '8px',
         right: '12px',
         zIndex: 1000,
         display: 'flex',
         visibility: 'visible',
         pointerEvents: 'auto',
         gap: '5px',
         padding: '5px',
         background: 'rgba(39, 40, 34, 1)',
         borderRadius: '4px'
      });

      function addButton(label, title, callback) {
         $('<button type="button"></button>')
            .text(label)
            .attr('title', title)
            .css({
               cursor: 'pointer',
               padding: '4px 9px',
               color: '#eee',
               background: '#32332B',
               border: '1px solid #4D4F43',
               borderRadius: '3px'
            })
            .on('click', function (event) {
               event.preventDefault();
               event.stopPropagation();
               callback();
            })
            .appendTo(toolbar);
      }

      // I should probably localize these later
      addButton('Fit', 'Fit the entire visible tree in the window', function () {
         self.fitToView();
      });
      addButton('+', 'Zoom in', function () {
         self._zoom.scale(Math.min(2.5, self._zoom.scale() * 1.2));
         self._applyZoom();
      });
      addButton('−', 'Zoom out', function () {
         self._zoom.scale(Math.max(0.25, self._zoom.scale() / 1.2));
         self._applyZoom();
      });
      addButton('Reset', 'Reset zoom and position', function () {
         self._zoom.scale(1).translate([self._margin.left, self._margin.top]);
         self._applyZoom();
      });

      // this is to stop the toolbar from moving when moving/scrolling with the handlebars 
      var parent = self._container.parent();

      parent.css('position', 'relative');

      var containerPosition = self._container.position();

      toolbar.css({
         top: containerPosition.top + 4,
         right: 30
      });

      parent.append(toolbar);
      self._toolbar = toolbar;
   },

   // zooooooooooooooooooooooooooom
   _applyZoom: function () {
      if (this._destroyed) {
         return;
      }

      var transform = d3.event && d3.event.translate
         ? d3.event.translate
         : (this._zoom && this._zoom.translate()) || [0, 0];

      var scale = d3.event && d3.event.scale
         ? d3.event.scale
         : (this._zoom && this._zoom.scale()) || 1;

      // reaching this number was fun, I started with 1/3 and it was crazy how
      // longer the tree was actually getting on each zoom out, turns out you want the change to be very proportionally tiny
      // because you want to keep the text visually equidistant on all zoom levels, otherwise it just looks too obviously stretched
      var horizontalScale = 1 / Math.pow(scale, 1 / 800);

      // the stretching
      this._vis.attr('transform',
         'translate(' + transform[0] + ',' + transform[1] + ') scale(' +
         horizontalScale + ',' + scale + ')');

      // keeping the circles and the text the same
      this._vis.selectAll('text, circle')
         .attr('transform',
            'scale(' + (1 / horizontalScale) + ',' + (1 / scale) + ')');
   },

   _update: function (source) {
      var self = this;
      if (self._destroyed) {
         return;
      }

      var nodes = self._tree.nodes(self._root);
      var links = self._tree.links(nodes);

      if (!nodes.length) {
         return;
      }

      // define the horizontal space per depth according to the longest label
      // This prevents long campaign/event names from running over the next column
      var depthWidths = {};
      var maxDepth = 0;
      nodes.forEach(function (d) {
         maxDepth = Math.max(maxDepth, d.depth);
         var estimatedLabelWidth = Math.max(40, String(d.name || '').length * 7.5);
         depthWidths[d.depth] = Math.max(depthWidths[d.depth] || 0, estimatedLabelWidth);
      });

      var depthOffsets = {};
      var depthOffset = 0;
      for (var depth = 0; depth <= maxDepth; depth++) {
         depthOffsets[depth] = depthOffset;

         var currentWidth = depthWidths[depth] || 40;
         var nextWidth = depthWidths[depth + 1] || 40;

         depthOffset += (currentWidth / 2) + (nextWidth / 2) + 30;
      }

      nodes.forEach(function (d) {
         d.y = depthOffsets[d.depth];
      });

      // I trusted strangers online to reach this point and figure out a better use of D3.
      // Well, they didn't tell me anything, really, I just trusted what they wrote in places I don't want to return to so soon
      var minX = d3.min(nodes, function (d) { return d.x; });
      var maxX = d3.max(nodes, function (d) { return d.x; });
      var maxY = d3.max(nodes, function (d) { return d.y; });
      var contentHeight = maxX - minX + self._margin.top + self._margin.bottom;
      var contentWidth = maxY + self._margin.left + self._margin.right;
      var xOffset = self._margin.top - minX;

      nodes.forEach(function (d) {
         d._displayX = d.x + xOffset;
      });

      self._svg
         .attr('width', Math.max(contentWidth, self._container.width()))
         .attr('height', Math.max(contentHeight, self._container.height()));

      var node = self._vis.selectAll('g.node')
         .data(nodes, function (d) { return d._uri; });

      var nodeEnter = node.enter().append('g')
         .attr('class', 'node')
         .attr('transform', function () {
            return 'translate(' + (source.y0 || 0) + ',' +
               ((source.x0 || 0) + xOffset) + ')';
         });

      // I thought the CSS would coveer all that but for some reason I had to do that for the nodes to work how I want (I probably did it wrong)
      nodeEnter.append('circle')
         .attr('r', 5)
         .style('fill', function (d) { return d._visible ? '#ffffff' : '#9bbbd0'; })
         .style('stroke', '#42616f')
         .style('stroke-width', 1.5)
         .on('click', function (d) {
            d3.event.stopPropagation();
            d.toggle();
         });

      nodeEnter.append('text')
         .attr('x', 0)
         .attr('dy', '1.5em')
         .style('text-anchor', 'middle')
         .style('font-family', 'Arial, sans-serif')
         .style('font-size', '12px')
         .style('font-weight', '400')
         .style('stroke', 'none')
         .style('fill', '#263238')
         .text(function (d) { return d.name; })
         .on('click', function (d) {
            d3.event.stopPropagation();
            d.inspect();
         });

      nodeEnter.append('title')
         .text(function (d) { return d.name; });

      var nodeUpdate = node.transition()
         .duration(self._duration)
         .attr('transform', function (d) {
            return 'translate(' + d.y + ',' + d._displayX + ')';
         });

      nodeUpdate.select('circle')
         .style('fill', function (d) {
            return d._visible ? '#ffffff' : '#9bbbd0';
         });

      nodeUpdate.select('text')
         .text(function (d) { return d.name; })
         .style('fill-opacity', 1);

      nodeUpdate.select('title')
         .text(function (d) {
            return d.name + (d._children.length ?
               ' (' + d._children.length + ' children) — click circle to ' +
               (d._visible ? 'collapse' : 'expand') : '');
         });

      node.exit().transition()
         .duration(self._duration)
         .style('opacity', 0)
         .remove();

      var link = self._vis.selectAll('path.link')
         .data(links, function (d) { return d.target._uri; });

      link.enter().insert('path', 'g')
         .attr('class', 'link')
         .style('fill', 'none')
         .style('stroke', '#50c6d5')
         .style('stroke-width', 2.5)
         .attr('d', function (d) {
            return self._diagonal({
               source: { x: d.source._displayX, y: d.source.y },
               target: { x: d.target._displayX, y: d.target.y }
            });
         });

      link.transition()
         .duration(self._duration)
         .attr('d', function (d) {
            return self._diagonal({
               source: { x: d.source._displayX, y: d.source.y },
               target: { x: d.target._displayX, y: d.target.y }
            });
         });

      link.exit().transition()
         .duration(self._duration)
         .style('opacity', 0)
         .remove();

      nodes.forEach(function (d) {
         d.x0 = d._displayX;
         d.y0 = d.y;
      });

      self._applyZoom();

      // default zoom level for first render
      if (!self._hasRendered) {
         self._hasRendered = true;
         self._zoom.translate([self._margin.left, 0]).scale(1);
         self._applyZoom();
      }
   },

   fitToView: function () {
      if (this._destroyed || !this._vis) {
         return;
      }

      var nodes = this._tree.nodes(this._root);
      if (!nodes.length) {
         return;
      }

      var minX = d3.min(nodes, function (d) { return d.x; });
      var maxX = d3.max(nodes, function (d) { return d.x; });

      var availableHeight = this._container.height() - 40;
      var contentHeight = maxX - minX + this._margin.top + this._margin.bottom;

      var scale = availableHeight / contentHeight;
      scale = Math.max(0.25, Math.min(1, scale));

      // Center the actual displayed node coordinates vertically for the snuggly fit
      var xOffset = this._margin.top - minX;
      var translateY = (availableHeight - (maxX - minX) * scale) / 2
         - (minX + xOffset) * scale;

      this._zoom
         .translate([this._margin.left, translateY])
         .scale(scale);

      this._applyZoom();
   },

   resize: function () {
      if (this._destroyed) {
         return;
      }

      var nodes = this._tree.nodes(this._root);
      if (!nodes.length) {
         return;
      }

      var minX = d3.min(nodes, function (d) { return d.x; });
      var maxX = d3.max(nodes, function (d) { return d.x; });
      var maxY = d3.max(nodes, function (d) { return d.y; });
      this._svg
         .attr('width', Math.max(maxY + this._margin.left + this._margin.right,
            this._container.width()))
         .attr('height', Math.max(maxX - minX + this._margin.top + this._margin.bottom,
            this._container.height()));
   },

   destroy: function () {
      if (this._destroyed) {
         return;
      }

      this._destroyed = true;
      if (this._svg) {
         this._svg.on('.zoom', null);
         this._svg.remove();
      }
      if (this._toolbar) {
         this._toolbar.remove();
      }
      if (this._root) {
         this._root.destroy();
      }
      this._container = null;
   }
});


App.StonehearthGameMasterView = App.View.extend({
   templateName: 'game_master',
   uriProperty: 'model',

   didInsertElement: function () {
      var self = this;

      // scrolling with the left mouse button just feels better for the campaign browser
      var windowElement = self.$('#game_master');
      if ($.fn.draggable) {
         windowElement.draggable({
            handle: '#toolbar',
            cancel: '.ui-resizable-handle, #close, #start, button, input, textarea'
         });
      }

      if ($.fn.resizable) {
         windowElement.resizable({
            minWidth: 520,
            minHeight: 360,
            handles: 'n,e,s,w,se,sw,ne,nw',
            resize: function () {
               if (self._node_browser) {
                  self._node_browser.resize();
               }
            }
         });
      }

      radiant.call_obj('stonehearth.game_master', 'get_root_node_command')
         .done(function (result) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            if (!result || !result.__self) {
               console.log('Campaign browser: game master returned no root node.', result);
               return;
            }

            if (!result.child_nodes || result.child_nodes.length <= 0) {
               self.set('notYetStarted', true);
            }

            var container = self.$('#campaignBrowserContent')[0];
            if (!container) {
               console.log('Campaign browser: #campaignBrowserContent was not found.');
               return;
            }

            self._node_browser = new D3CollapsableTree({
               container: container,
               root_node_uri: result.__self,
               get_node_name: function (node) {
                  return node.node_name;
               },
               get_node_children: function (node) {
                  return node.child_nodes || [];
               },
               inspect_node: function (node) {
                  if (self._nodeInspector) {
                     self._nodeInspector.destroy();
                     self._nodeInspector = null;
                  }

                  if (!node.data || self.isDestroying || self.isDestroyed) {
                     return;
                  }

                  var nodeSelection = self._node_browser._vis.selectAll('g.node')
                     .filter(function (d) {
                        return d._uri === node._uri;
                     });

                  var nodeElement = nodeSelection[0][0];

                  if (!nodeElement) {
                     return;
                  }

                  var nodeRect = nodeElement.querySelector('circle').getBoundingClientRect();

                  self._nodeInspector = App.debugView.addView(
                     App.StonehearthObjectBrowserView,
                     {
                        uri: node.data.__self,
                        relativeTo: {
                           top: nodeRect.bottom - 750,
                           left: nodeRect.right - 750
                        }
                     }
                  );
               }
            });
         })
         .fail(function (error) {
            console.log('Call to stonehearth.game_master:get_root_node_command() failed.', error);
         });
   },

   actions: {
      close: function () {
         this.destroy();
      },

      startGameMaster: function () {
         radiant.call('debugtools:start_game_master_command');
         this.set('notYetStarted', false);
      }
   },

   destroy: function () {
      if (this._node_browser) {
         this._node_browser.destroy();
         this._node_browser = null;
      }

      if (this._nodeInspector) {
         this._nodeInspector.destroy();
         this._nodeInspector = null;
      }

      this._super();
   },

   willDestroyElement: function () {
      if (this._node_browser) {
         this._node_browser.destroy();
         this._node_browser = null;
      }
      this.$().off('.campaignBrowser');
      this._super();
   }
});
