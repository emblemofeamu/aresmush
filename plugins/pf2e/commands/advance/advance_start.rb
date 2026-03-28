module AresMUSH
  module Pf2e

    class PF2ADvancementStartCmd
      include CommandHandler

      def check_approval
        return nil if enactor.is_approved?
        return t('pf2e.not_approved')
      end

      def handle
        # Verify that the character can advance.
        advfail = Pf2e.can_advance(enactor)

        if advfail
          client.emit_failure advfail
          return
        end

        # Gather information.
        level = enactor.pf2_level + 1

        charclass = enactor.pf2_base_info['charclass']

        charclass_adv_info = Global.read_config('pf2e_class', charclass, 'advance')[level]

        archetype1 = enactor.pf2_archetypeinfo['archetype1'] && enactor.pf2_archetypeinfo['archetype_specialty1'] || []
        archetype2 = enactor.pf2_archetypeinfo['archetype2'] && enactor.pf2_archetypeinfo['archetype_specialty2'] || []
        archetype3 = enactor.pf2_archetypeinfo['archetype3'] && enactor.pf2_archetypeinfo['archetype_specialty3'] || []
        archetype4 = enactor.pf2_archetypeinfo['archetype4'] && enactor.pf2_archetypeinfo['archetype_specialty4'] || []

        # Some specialties have their own peculiar advancement bits. Look for those and merge them in if present.
        specialize = enactor.pf2_base_info['specialize']
        subclass_adv_info = nil
        unless specialize.blank?
          specialty_config = Global.read_config('pf2e_specialty', charclass, specialize) || {}
          subclass_adv_info = specialty_config['advance']
        end
        sublevel_adv_info = subclass_adv_info ? subclass_adv_info[level] : nil

        info = if sublevel_adv_info
          merge_advancement_info(charclass_adv_info, sublevel_adv_info)
        else
          charclass_adv_info
        end

        # Send information for processing.

        msg = Pf2e.assess_advancement(enactor,info)

        # msg is an array of all the messages that indicate stuff to pick, so display that plus a success message.

        client.emit_ooc msg.join("%r%%%b")
        client.emit_success t('pf2e.advance_started', :level => level, :charclass => charclass)
        template = Pf2e::PF2AdvanceReviewTemplate.new(enactor, client)
        client.emit template.render
      end

      private

      def merge_advancement_info(base_info, extra_info)
        return extra_info if base_info.nil?
        return base_info if extra_info.nil?
        return extra_info unless base_info.is_a?(Hash) && extra_info.is_a?(Hash)

        merged = base_info.dup
        extra_info.each_pair do |key, extra_val|
          base_val = merged[key]
          merged[key] = if base_val.is_a?(Hash) && extra_val.is_a?(Hash)
            merge_advancement_info(base_val, extra_val)
          elsif base_val.is_a?(Array) && extra_val.is_a?(Array)
            (base_val + extra_val).uniq
          else
            extra_val
          end
        end

        merged
      end

    end
  end
end
