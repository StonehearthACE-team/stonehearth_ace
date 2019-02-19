App.StonehearthCitizenCharacterSheetView.reopen({
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
   }
});
