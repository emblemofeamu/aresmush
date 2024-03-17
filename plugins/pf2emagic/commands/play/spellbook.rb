module AresMUSH
  module Pf2emagic
    class PF2MagicSpellbookCmd
      include CommandHandler

      attr_accessor :character, :charclass, :charclasses, :spell_level

      def parse_args
        # Usage: spellbook [character=][class/level]
        # Faraday's argparser isn't going to touch this one, so we roll our own.

        self.charclasses = Global.read_config('pf2e_class').keys

        if cmd.args
          # Use the size of the arrays to work out what args were supplied.
          args = cmd.args.split("=")

          if args.size == 2
            self.character = trim_arg(args[0])

            classlevel = args[1].split("/").flatten

            # Coder decision: self.spell_level does not make sense without self.charclass, therefore disallow
            self.charclass = titlecase_arg(classlevel[0])
            self.spell_level = classlevel[1] ? integer_arg(classlevel[1]) : nil
            self.spell_level = 'cantrip' if (self.spell_level && self.spell_level.zero?)
          else
            # Args could be a character name or a class/level split with or without the level in this case.
            # Work out which.
            unknown = args[0].split("/").flatten

            # If unknown splits here, we can assume it's a class/level split and that character name is absent.
            if unknown[1]
              self.spell_level = integer_arg(unknown[1])
              self.charclass = titlecase_arg(unknown[0])
            else
              # If not, unknown[0] is either a character class or a character name, and spell_level is 'all'.

              cc_test = titlecase_arg(unknown[0])

              if charclasses.include? cc_test
                self.charclass = cc_test
              else
                self.character = cc_test
              end
            end
          end

        else
          # If no args, the enactor is asking to see their whole spellbook. All three are nil.
        end

      end

      def check_permissions
        return nil if enactor.has_permission? "manage_alts"
        return nil unless self.character
        return t('dispatcher.not_allowed')
      end

      def check_invalid_admin_syntax
        # Admins should not be using this command on themselves.
        return nil unless enactor.has_permission? "manage_alts"
        return nil if self.character
        return t('pf2e.admin_no_sheet')
      end

      def handle
        # If character came out of the argparsing, get that character, else get the enactor's character
        char = Pf2e.get_character(self.character, enactor)

        unless char
          client.emit_failure t('pf2e.not_found')
          return
        end

        # Check if character is a caster
        unless Pf2emagic.is_caster?(char)
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        csb = char.magic.spellbook

        # Cut the music if there is nothing in the spellbook at all.
        if csb.empty?
          client.emit_failure t('pf2emagic.no_spellbook', :item => char.name)
          return
        end

        # If a charclass was specified, is there anything in the spellbook for that charclass?
        if self.charclass && !(csb.keys.include? self.charclass)
          client.emit_failure t('pf2emagic.no_spellbook', :item => self.charclass)
          return
        end

        # This will not be called in the template unless self.charclass is specified.

        cc = self.charclass ? self.charclass : 'not specified'
        book = self.charclass ? csb[self.charclass] : csb

        # If a spell level was specified, send just that level. Remember that self.charclass
        # has been validated as a charclass at this point in the code.

        if self.spell_level
          # If they specified level, check to make sure they have spells at the specified level.
          levelbook = book[self.spell_level.to_s]

          unless levelbook
            client.emit_failure t('pf2emagic.spellbook_no_spells_at_level', :options => book.keys.join(", "))
            return
          end

          book = { self.spell_level => levelbook }
        end

        template = PF2SpellbookTemplate.new(char, cc, book, client)

        client.emit template.render
      end

    end
  end
end
