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
        level = char.pf2_level + 1

        charclass = char.pf2_base_info['charclass']

        charclass_adv_info = Global.read_config('pf2e_class', charclass, 'advance')['level']

        # Some specialties have their own peculiar advancement bits. Look for those and merge them in if present.
        subclass_adv_info = Global.read_config('pf2e_specialty', charclass, char.pf2_base_info['specialty'])['advance']
        sublevel_adv_info = subclass_adv_info ? subclass_adv_info[level] : nil

        info = sublevel_adv_info ? charclass_adv_info.merge(sublevel_adv_info) : charclass_adv_info

        # Send information for processing.
        msg = Pf2e.assess_advancement(enactor,info)

        # msg is an array of all the messages that indicate stuff to pick, so display that plus a success message.

        client.emit_ooc msg.join("%r")
        client.emit_success t('pf2e.advance_started', :level => level, :charclass => charclass)
      end

    end
  end
end
