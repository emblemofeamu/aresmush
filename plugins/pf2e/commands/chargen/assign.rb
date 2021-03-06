module AresMUSH
  module Pf2e
    class PF2AssignCmd
      include CommandHandler

      attr_accessor :type, :ability

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.type = downcase_arg(args.arg1)
        self.option = downcase_arg(args.arg2)
      end

      def required_args
        [ self.type, self.option ]
      end

      def check_cg_or_advance
        return nil unless ( enactor.chargen_locked || enactor.is_admin? )
        return nil if enactor.chargen_stage
        return nil if enactor.has_permission?('advancing')
        return t('pf2e.only_in_chargen')
      end

      def handle
        to_assign = enactor.pf2_to_assign
        # Lores are a different class of object, but are assigned out of the skill pool
        hash_key = self.type.match?("open lore") ? "open skill" : self.type

        if !enactor.pf2_baseinfo_locked
          client.emit_failure t('pf2e.lock_info_first')
          return
        elsif !to_assign.has_key?(hash_key)
          client.emit_failure t('pf2e.bad_option', :element => 'assignment', :option => self.type)
          return
        end

        # The values in to_assign are always an array, an integer, or a string.
        # An array means they have a choice, an integer counts how many can be freely assigned.
        # A string identifies the list from which that feat must be chosen.

        k = to_assign["#{hash_key}"]

        if k.is_a?(Array)
          k = k.each { |k| k.downcase }
          if k.empty?
            client.emit_failure t('pf2e.already_assigned')
            return
          elsif !k.include?(self.option)
            client.emit_failure t('pf2e.bad_option', :element => self.type, :option => self.option)
            return
          end
        elsif k.is_a?(Integer)
          if k.zero?
            client.emit_failure t('pf2e.no_free', :element => self.type)
            return
          end
        end

        if self.type.match?("boost")
          boosts = enactor.pf2_boosts_working

          abilities = %w{ strength dexterity constitution intelligence wisdom charisma }

          if !(abilities.include? self.option)
            client.emit_failure t('pf2e.bad_ability')
            return
          end

          case self.type
          when "open boost"
            btype = "free"
          when "open anboost"
            btype = "ancestry"
          when "bgboost", "open bgboost"
            btype = "background"
          when "class boost"
            btype = "charclass"
          end

          assign = boosts["#{btype}"]
          assign << self.option
          boosts["#{btype}"] = assign

          if k.is_a?(Array)
            track = enactor.pf2_cg_assigned
            remaining = 0
            track[("#{self.type}" + " track")] = self.option
            enactor.update(pf2_cg_assigned: track)
            to_assign.delete(self.type)
          elsif k.is_a(Integer)
            k = k - 1
            remaining = k
            to_assign["#{self.type}"] = k
          end


          enactor.update(pf2_boosts_working: boosts)
          enactor.update(pf2_to_assign: to_assign)

          client.emit_success t('pf2e.assign_ok', :element => self.type, :option => self.option.capitalize, :remaining => k)

          if btype == 'charclass'
            combat_stats = enactor.combat

            if !combat_stats
              client.emit_ooc t('pf2e.combat_something_wrong')
              return
            end

            combat_stats.update(key_abil: self.option.capitalize)
          end

        elsif (hash_key.match?'skill') || (hash_key.match? 'lore')

          is_lore = self.type.match?('lore')

          if k.is_a?(Array)
            skills_available = k
            track = enactor.pf2_cg_assigned
          else
            skills_available = is_lore ? false : Global.read_config('pf2e_skills').keys
          end

          skills_down = skills_available ? skills_available.each { |s| s.downcase } : skills_available

          if skills_available
            if !skills_down.member?(self.option)
              client.emit_failure t('pf2e.bad_option', :element => "skill", :options => skills.skills_available.join(", "))
              return
            end

            i = skills_down.index(self.option)
            skill = skills_available[i]
          else
            skill = titlecase_arg(self.option)
          end

          has_skill = is_lore ? Pf2eSkills.find_skill(self.option, enactor) : Pf2eLores.find_lore(self.option, enactor)

          if has_skill
            client.emit_failure t('pf2e.already_has_skill')
            return
          elsif is_lore
            Pf2eLores.create(name: skill, character: enactor, proflevel: 'trained')
            client.emit_success t('pf2e.skill_added', :option => skill, :skilltype => 'lores')
          else
            Pf2eSkills.create(name: skill, character: enactor, proflevel: 'trained')
            client.emit_success t('pf2e.skill_added', :option => skill, :skilltype => 'skills')
          end

          if k.is_a?(Array)
            remaining = 0
            track[("#{self.type}" + " track")] = self.option
            enactor.update(pf2_cg_assigned: track)
            to_assign.delete(self.type)
          elsif k.is_a(Integer)
            k = k - 1
            remaining = k
            to_assign["#{self.type}"] = k
          end

          enactor.update(pf2_to_assign: to_assign)

        elsif self.type.match?('feat')

          char_feats = enactor.pf2_feats

          if self.type == 'bgfeat'
            feat_type = 'general'
          else
            feat_type = self.type.split[0]
          end

          feat_list = Global.read_config('pf2e_feats',feat_type).keys

          # Archetype feats are chosen using class feats, and skill feats can be chosen with general feats.
          if self.type == 'charclass feat'
            archetype_feats = Global.read_config('pf2e_feats', 'archetype').keys
            archetype_feats.each { |f| feat_list << f }
          elsif self.type == 'general feat'
            skill_feats = Global.read_config('pf2e_feats', 'skill').keys
            skill_feats.each { |f| feat_list << f }
          end

          feat = self.option.split.each { |w| w.capitalize }

          if !(feat_list.include? feat)
            client.emit_failure t('pf2e.wrong_feat_type')
            return
          end

          qualifies = Pf2eFeats.can_take_feat?(enactor, feat_type, feat)

          if !qualifies
            client.emit_failure t('pf2e.feat_prereq_not_met')
            return
          end

          char_feat_list = char_feats[feat_type]
          char_feat_list << feat
          char_feats[feat_type] = char_feat_list

          track = enactor.pf2_cg_assigned
          track[("#{self.type}" + " track")] = self.option
          enactor.update(pf2_cg_assigned: track)
          enactor.update(pf2_feats: char_feats)

        elsif self.type.match?('open language')


        end

      end
    end
  end
end
