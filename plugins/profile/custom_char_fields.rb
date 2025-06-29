module AresMUSH
  module Profile
    class CustomCharFields

      # Gets custom fields for display in a character profile.
      #
      # @param [Character] char - The character being requested.
      # @param [Character] viewer - The character viewing the profile. May be nil if someone is viewing
      #    the profile without being logged in.
      #
      # @return [Hash] - A hash containing custom fields and values.
      #    Ansi or markdown text strings must be formatted for display.
      # @example
      #    return { goals: Website.format_markdown_for_html(char.goals) }
      def self.get_fields_for_viewing(char, viewer)

        if viewer == char || viewer&.has_permission?("manage_alts")
          if !(char.player)
            return { registration: Website.format_markdown_for_html("Not yet registered.") }
          else
            altlist = AltTracker.get_altlist_by_object(char.player).join(", ")
            player_email = char.player.name ? char.player.name : "No email set."
            return { alttracker_register: Website.format_markdown_for_html(player_email), alttracker_alts: Website.format_markdown_for_html(altlist) }
          end
        else
          return {}
        end

      end

      # Gets custom fields for the character profile editor.
      #
      # @param [Character] char - The character being requested.
      # @param [Character] viewer - The character editing the profile.
      #
      # @return [Hash] - A hash containing custom fields and values.
      #    Multi-line text strings must be formatted for editing.
      # @example
      #    return { goals: Website.format_input_for_html(char.goals) }
      def self.get_fields_for_editing(char, viewer)
        return {}
      end

      # Gets custom fields for character creation (chargen).
      #
      # @param [Character] char - The character being requested.
      #
      # @return [Hash] - A hash containing custom fields and values.
      #    Multi-line text strings must be formatted for editing.
      # @example
      #    return { goals: Website.format_input_for_html(char.goals) }
      def self.get_fields_for_chargen(char)
        return {}
      end
      
      # Deprecated - use save_fields_from_profile_edit2 instead
      def self.save_fields_from_profile_edit(char, char_data)
        return []
      end

      # Saves fields from character creation (chargen).
      #
      # @param [Character] char - The character being updated.
      # @param [Hash] chargen_data - A hash of character fields and values. Your custom fields
      #    will be in chargen_data[:custom]. Multi-line text strings should be formatted for MUSH.
      #
      # @return [Array] - A list of error messages. Return an empty array ([]) if there are no errors.
      # @example
      #        char.update(goals: Website.format_input_for_mush(chargen_data[:custom][:goals]))
      #        return []
      def self.save_fields_from_chargen(char, chargen_data)
        return []
      end
      
      # Saves fields from profile editing.
      #
      # @param [Character] char - The character being updated.
      # @param [Character] enactor - The character triggering the update.
      # @param [Hash] char_data - A hash of character fields and values. Your custom fields
      #    will be in char_data[:custom]. Multi-line text strings should be formatted for MUSH.
      #
      # @return [Array] - A list of error messages. Return an empty array ([]) if there are no errors.
      # @example
      #        char.update(goals: Website.format_input_for_mush(char_data[:custom][:goals]))
      #        return []
      def self.save_fields_from_profile_edit2(char, enactor, char_data)
        # By default, this calls the old method for backwards compatibility. The old one didn't
        # use enactor. Replace this with your own code.
        return CustomCharFields.save_fields_from_profile_edit(char, char_data)
      end

      
    end
  end
end
