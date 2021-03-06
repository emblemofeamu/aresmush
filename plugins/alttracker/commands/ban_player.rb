module AresMUSH
  module AltTracker

    class BanPlayerCmd
      include CommandHandler

      attr_accessor :name, :reason

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.name = trim_arg(args.arg1)
        self.reason = trim_arg(args.arg2).to_s
      end

      def required_args
        [ self.name, self.reason ]
      end

      def check_can_modify
        return nil if enactor.has_permission?("manage_alts")
        return t('dispatcher.not_allowed')
      end

      def handle
        ClassTargetFinder.with_a_character(self.name, client, enactor) do |char|
          if char.player
            player = char.player

            player.characters.each { |alt|
              alt.update(player: nil)
              alt.update(approval_job: nil)
              alt.update(chargen_locked: false)
            }

            player.update(banned: self.reason)
            client.emit_success "Player #{player.email} banned from gameplay and all alts unapproved. Reason: #{self.reason}"
          else
            client.emit_failure t('alttracker.not_registered', :name => self.name)
          end
        end
      end

    end

  end
end
