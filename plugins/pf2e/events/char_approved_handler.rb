module AresMUSH
  module Pf2e
    class CharApprovedHandler
      def on_event(event)
        char = Character[event.char_id]
        return unless char

        level = char.pf2_level
        tracker = char.pf2_level_tracker || {}

        return if tracker.values.any? { |entry| entry.is_a?(Hash) && entry['source'] }

        entry = {
          'base_info' => char.pf2_base_info,
          'boosts' => char.pf2_boosts_working,
          'feats' => Pf2e::DraftSheet.of(char).feats_by_bucket,
          'languages' => char.pf2_lang,
          'faith' => char.pf2_faith,
          'skills' => char.skills.each_with_object({}) do |skill, hash|
            next if skill.prof_level.to_s == 'untrained'
            hash[skill.name] = skill.prof_level
          end
        }

        entry['source'] = level > 1 ? 'respec' : 'chargen'

        Pf2e.record_level(char, level, entry)

        # The draft becomes history: everything chargen produced is written as one chargen
        # transaction, and from here the ledger is the source of truth for this sheet.
        Pf2e::Ledger.commit_chargen!(char)
      end
    end
  end
end
