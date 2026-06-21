module AresMUSH
  module Pf2emagic

    class PF2ChargenSpellsCmd
      include CommandHandler

      attr_accessor :caster_class, :spell_level, :new_spell, :old_spell

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.caster_class = titlecase_arg(args.arg1)
        self.spell_level = integer_arg(args.arg2)

        spells = trimmed_list_arg(args.arg3, "/")

        if !spells
          self.new_spell = nil
          self.old_spell = nil
        elsif spells && spells[1]
          self.new_spell = spells[1]
          self.old_spell = spells[0]
        else
          self.new_spell = spells[0]
          self.old_spell = false
        end

      end

      def required_args
        [ self.caster_class, self.spell_level, self.new_spell]
      end

      def check_in_chargen
        if enactor.is_approved? || enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def check_baseinfo_locked
        # They need to have done commit info before they can use this command.
        return nil if enactor.pf2_baseinfo_locked
        return t('pf2e.lock_info_first')
      end

      def check_correct_class
        correct_class = enactor.pf2_base_info['charclass']
        entered_class = self.caster_class
        prepared_classes = Global.read_config('pf2e_magic', 'prepared_casters') || []
        spontaneous_classes = Global.read_config('pf2e_magic', 'spontaneous_casters') || []
        all_caster_classes = (prepared_classes + spontaneous_classes).map { |cc| cc.downcase }

        return nil unless correct_class
        return nil unless entered_class
        return nil unless all_caster_classes.include?(entered_class.downcase)
        return nil if entered_class.casecmp?(correct_class)

        t('pf2emagic.cant_learn_wrong_class', :wrong_class => entered_class, :correct_class => correct_class)
      end

      def handle

        level = self.spell_level.zero? ? 'cantrip' : self.spell_level.to_s

        if self.caster_class&.casecmp?('innate')
          msg = Pf2emagic.select_innate_spell(enactor, level, self.old_spell, self.new_spell, true)

          if msg
            client.emit_failure msg
            return
          end

          client.emit_success t('pf2emagic.cg_spell_select_ok')
          return
        end

        # A switch on this command indicates a gate on the spell. Divert to different processing.
        if cmd.switch
          msg = Pf2emagic.select_gated_spell(enactor, self.caster_class, level, self.old_spell, self.new_spell, cmd.switch, false, true)
        else
          msg = Pf2emagic.select_spell(enactor, self.caster_class, level, self.old_spell, self.new_spell, false, true)
        end

        if msg
          client.emit_failure msg
          return
        end

        client.emit_success t('pf2emagic.cg_spell_select_ok')

      end

    end

  end
end
