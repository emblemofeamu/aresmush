module AresMUSH
  module Pf2e

    # Trades one spell in a spontaneous caster's repertoire for another, once per level-up.
    #
    # The decisions are Advancement::Repertoire. What is left here is resolving the two spell
    # names and reading the magic object, both of which need the live character.
    class PF2AdvanceSwapSpellCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :level, :old_value, :new_value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.type = downcase_arg(args.arg1)
        self.level = trim_arg(args.arg2)

        spells = trimmed_list_arg(args.arg3, "/")

        if spells
          self.old_value = spells[0]
          self.new_value = spells[1]
        end
      end

      def required_args
        [ self.type, self.level, self.old_value, self.new_value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def check_repertoire_only
        return nil if self.type == "repertoire"
        return t('pf2e.swapspell_repertoire_only')
      end

      # Also a guard inside Repertoire.swap, which is the authority - this is here so that a
      # player who has already swapped is told that, rather than being told their spell name is
      # wrong on the way to the same answer.
      def check_swap_limit
        return nil unless (enactor.pf2_advancement || {})['repertoire_swap']
        return t('pf2e.swapspell_limit')
      end

      def handle
        magic = enactor.magic

        if !magic
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        charclass = enactor.pf2_base_info['charclass']

        if Pf2emagic.get_caster_type(charclass) != 'spontaneous'
          client.emit_failure t('pf2e.swapspell_repertoire_only')
          return
        end

        old_spell = resolve_spell_name(self.old_value)
        return unless old_spell

        # The new spell goes through the caster's own check, which knows their tradition and
        # what ranks they can reach.
        choice = Pf2emagic.check_spell(enactor, charclass, rank, self.new_value, true)

        if choice.is_a?(String)
          client.emit_failure choice
          return
        end

        swapped = Pf2e::Advancement::Repertoire.swap(held_at_rank, old_spell, choice[0],
          :locked => locked_spells,
          :already_swapped => !!(enactor.pf2_advancement || {})['repertoire_swap'])

        return if Pf2e::CharState.emit_error!(client, swapped)

        record!(old_spell, choice[0], swapped)

        client.emit_success t('pf2e.swapspell_ok', :old => old_spell, :new => choice[0], :level => rank)
      end

      private

      # 'cantrip' or the rank as written.
      def rank
        @rank ||= self.level.to_i.zero? ? 'cantrip' : self.level
      end

      def repertoire
        @repertoire ||= enactor.magic.repertoire || {}
      end

      def held_at_rank
        Array((repertoire[enactor.pf2_base_info['charclass']] || {})[rank])
      end

      # Spells the character's specialty put there, which are not theirs to trade away.
      def locked_spells
        info = Global.read_config('pf2e_specialty',
          enactor.pf2_base_info['charclass'], enactor.pf2_base_info['specialize'])

        Pf2e::Advancement::Repertoire.granted(info, enactor.pf2_level)
      end

      # The swap on the magic object, and the note in the draft that advance/reset reads to put
      # it back.
      def record!(old_spell, new_spell, spells)
        charclass = enactor.pf2_base_info['charclass']
        updated = repertoire
        updated[charclass] = (updated[charclass] || {}).merge(rank => spells)

        enactor.magic.update(:repertoire => updated)

        advancement = enactor.pf2_advancement || {}
        advancement['repertoire_swap'] = { 'level' => rank, 'old' => old_spell, 'new' => new_spell }

        enactor.update(:pf2_advancement => advancement)
      end

      def resolve_spell_name(term)
        matches = Pf2emagic.get_spells_by_name(term)

        if matches.empty?
          client.emit_failure t('pf2emagic.no_such_spell')
          return nil
        end

        if matches.size > 1
          client.emit_failure t('pf2emagic.multiple_matches', :item => 'spell')
          return nil
        end

        matches.first
      end

    end
  end
end
