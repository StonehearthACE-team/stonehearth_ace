App.StonehearthCitizenCharacterSheetView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();
      
      self.$('#name').focus(function() {
         self.$('#name').val(self.get('model.custom_name'))
            .select();
      })
      .blur(function() {
         // if the name didn't change, make sure we add back any title we might have!
         // (if the name did change, this will get taken care of automatically by the _onNameChanged function)
         if (self.$('#name').val() == self.get('model.custom_name')) {
            self.$('#name').val(self.get('model.unit_name'));
         }
      })
      .on('mousedown', function(e) {
         if (e.button == 2) {
            self._showTitleSelectionList();
            e.preventDefault();
         }
      });
   },

   _onNameChanged: function() {
      var self = this;
      var unit_info = self.get('model.stonehearth:unit_info');
      var unit_name = i18n.t(unit_info && unit_info.display_name, {self: self.get('model')});
      var custom_name = unit_info && unit_info.custom_name;
      var title_description = unit_info && unit_info.current_title && unit_info.current_title.description;
      self.set('model.unit_name', unit_name);
      self.set('model.custom_name', custom_name);

      var text = title_description;
      var title;
      if (text) {
         text = i18n.t(text);
         title = unit_name;
      }
      else {
         text = unit_name;
      }

      App.guiHelper.addTooltip(self.$('#name'), text, title || "");
   }.observes('model.stonehearth:unit_info'),

   //Go through each job we've had and annotate the perk table accordingly
   _updateJobsAndPerks : function() {
      var self = this;

      //Hide all the job divs before selectively showing the ones for the current
      //character.
      if (!self.$('.jobData')) {
         return; // this can happen if character is destroyed.
      }

      self.$('.jobData').hide();

      //show each class that this person has ever been
      var allJobData = App.jobConstants;
      var jobs = this.get('model.stonehearth:job.job_controllers');
      var workerDivs = [];
      radiant.each(jobs, function(alias, data) {
         var job_alias = data.json_path;
         var isWorker = job_alias == 'stonehearth:jobs:worker';
         var hasPerks = job_alias != 'stonehearth:jobs:worker';
         var jobData = allJobData[job_alias];
         if (jobData) {
            isWorker = jobData.description.is_worker;
            hasPerks = false;
            if (jobData.description.levelArray) {
               jobData.description.levelArray.forEach(levelData => {
                  if (levelData.perks && levelData.perks.length > 0) {
                     hasPerks = true;
                  }
               });
            }
         }
         else {
            job_alias = alias;
         }

         if (hasPerks) {
            var div = self.$("[uri='" + job_alias + "']");

            //For each, figure out which perks should be unlocked
            self._unlockPerksToLevel(div, data.last_gained_lv)

            $(div).show();

            if (isWorker) {
               workerDivs.push(div);
            }
         }
      });

      //Highlight current class, since it needs to be 100% up to date
      self.$('.activeClassNameHeader').removeClass('activeClassNameHeader');
      self.$('.className').addClass('retiredClassNameHeader');
      self.$('.jobData').addClass('retiredEffect');
      var currClassAlias = this.get('model.stonehearth:job.job_json_path');
      var $currClass = self.$("[uri='" + currClassAlias + "']");
      $currClass.prependTo("#citizenCharacterSheet #abilitiesTab");
      $currClass.find('.className').removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      $currClass.removeClass('retiredEffect');
      //$currClass.removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      self._unlockPerksToLevel($currClass,  this.get('model.stonehearth:job.curr_job_controller.last_gained_lv'))
      $currClass.find('.retiredAt').hide();

      workerDivs.forEach(div => {
         div.find('.retiredAt').hide();
      });

      //Make the job tooltips
      this._updateJobTooltips();
   },

   //Given a perk div and target level, change the classes within to reflect the current level
   _unlockPerksToLevel : function (target_div, target_level) {
      $(target_div).find('.levelLabel').addClass('lvLabelLocked');
      $(target_div).find('img').addClass('perkImgLocked');
      for(var i=0; i<=target_level; i++) {
         $(target_div).find("[imgLevel='" + i + "']").removeClass('perkImgLocked').addClass('perkImgUnlocked');
         $(target_div).find("[lbLevel='" + i + "']").removeClass('lvLabelLocked').addClass('lvLabelUnlocked');
         $(target_div).find("[divLevel='" + i + "']").attr('locked', "false");
      }

      //For good measure, throw the level into the class name header or remove if the level is 0
      if (target_level >= 0 && target_level <= 2) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.apprentice'));
      } else if (target_level >= 3 && target_level <= 4) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.journeyman'));
      } else if (target_level >= 5) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.master'));
      }

      //Calculate the height of the jobPerks section based on the number of perkDivs
      //TODO: factor these magic numbers out or change if/when the icons change size
      // var numPerks = $(target_div).find('.perkDiv').length;
      // if (numPerks == 0) {
      //    $(target_div).find('.jobPerks').css('height', '0px');
      // } else {
      //    var num_rows = parseInt(numPerks/8) + 1;
      //    var total_height = num_rows * 90;
      //    $(target_div).find('.jobPerks').css('height', total_height + 'px');
      // }

      $(target_div).find('.retiredAt').show();
   },

   _showTitleSelectionList: function(e) {
      var self = this;

      var result = stonehearth_ace.createTitleSelectionList(self._titles, self.get('model.stonehearth:unit_info.titles'), self.get('uri'), self.get('model.custom_name'));
      if (result) {
         self.$('#name').after(result.container);
         result.showList();
      }
   },

   _loadAvailableTitles: function() {
      // when the selection changes, load up the appropriate titles json
      var self = this;
      self._titles = {};
      var json = self.get('model.stonehearth:unit_info.titles_json');
      if (json) {
         stonehearth_ace.loadAvailableTitles(json, function(data){
            self._titles = data;
         });
      }
   }.observes('model.uri')
});
