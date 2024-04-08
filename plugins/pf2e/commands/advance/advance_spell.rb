module AresMUSH
  module Pf2e

    class PF2AdvanceSpellCmd
      include CommandHandler

      attr_accessor :type, :level, :value, :old_value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.type = downcase_arg(args.arg1)
        self.level = trim_arg(args.arg2)
        spells = trimmed_list_arg(args.arg3,"/")

        if spells
          if spells[1]
            self.value = spells[1]
            self.old_value = spells[0]
          else
            self.value = spells[0]
          end
        end

      end

      def required_args
        [ self.type, self.level, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        # Do they have one of these to select?

        to_assign = enactor.pf2_to_assign

        type_option = to_assign[self.type]

        unless type_option
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        charclass = enactor.pf2_base_info['charclass']
        level = self.level.to_i.zero? ? 'cantrip' : self.level

        list = self.type == "spellbook" ? type_option : type_option[level]


        # Now we have to figure out if we have an open slot.
        open_slot = list.index "open"

        if open_slot
          old = "open"
        elsif self.old_value
          old = list.select {|s| s.downcase.match? self.old_value.downcase}.first

          unless old
            client.emit_failure t('pf2e.not_in_list', :option => self.old_value)
            return
          end

          open_slot = list.index old
        else
          client.emit_failure t('pf2e.no_free', :element => "#{self.type} slot")
          return
        end

        choice = Pf2emagic.check_spell(enactor, charclass, level, self.value, true)

        if choice.is_a? String
          client.emit_failure choice
          return
        end

        spell = choice[0]

        advancement = enactor.pf2_advancement

        # because Ruby is stupid and doesn't let you replace at an index directly.
        list.delete_at open_slot
        list << spell

        # Because I was stupid and repertoire is a Hash and spellbook is an array.

        if self.type == "spellbook"
          to_assign[self.type] = list
          advancement[self.type] = list
        elsif self.type == "repertoire"
          type_option[level] = list

          to_assign[self.type] = type_option
          advancement[self.type] = type_option
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign

        enactor.save

        client.emit_success t('pf2e.add_ok', :item => spell, :list => self.type)
      end
    end
  end
end
