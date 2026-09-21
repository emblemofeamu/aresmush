module AresMUSH
  module Pf2e

    # Throws away everything picked since `advance`, putting the character back where they
    # started the level.
    #
    # The picks themselves are the draft, so the core clears them. What this shell still does
    # by hand is undo the three things a pick writes straight to the sheet before the level is
    # committed - archetype features, a repertoire swap, and the archetype slots - each of
    # which would be simpler if it went to the draft like everything else.
    class PF2AdvanceResetCmd
      include CommandHandler

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        before = Pf2e::CharState.of(enactor)

        remove_archetype_features(Pf2e::Advancement::Lifecycle.granted_features(before))
        undo_repertoire_swap(Pf2e::Advancement::Lifecycle.repertoire_swap(before))

        outcome = Pf2e::CharacterService.call(before, :reset_advancement)

        return if Pf2e::CharState.emit_error!(client, outcome)

        Pf2e::CharState.commit!(enactor, before, outcome)

        # Nothing is left to take back a step at a time.
        Pf2e::DraftJournal.clear!(enactor)

        # Not part of the state a core may write, and the commit boundary for a level-up is
        # advance/done - so leaving the flag set here would strand the character mid-level.
        enactor.update(:advancing => false)

        Pf2e::CharState.emit_messages!(client, outcome)
      end

      private

      def remove_archetype_features(granted)
        return if granted.empty?

        features = enactor.pf2_features

        features['archetype_features'] = Array(features['archetype_features']).reject do |held|
          granted.any? { |name| name.to_s.casecmp?(held.to_s) }
        end

        enactor.update(:pf2_features => features)
      end

      def undo_repertoire_swap(swap)
        return unless swap

        magic = enactor.magic
        charclass = enactor.pf2_base_info['charclass']

        return unless magic && charclass

        repertoire = magic.repertoire || {}
        for_class = repertoire[charclass] || {}
        at_level = Array(for_class[swap['level']])

        index = at_level.index { |spell| spell.to_s.casecmp?(swap['new'].to_s) }

        return unless index

        at_level[index] = swap['old']
        for_class[swap['level']] = at_level
        repertoire[charclass] = for_class

        magic.update(:repertoire => repertoire)
      end

    end
  end
end
