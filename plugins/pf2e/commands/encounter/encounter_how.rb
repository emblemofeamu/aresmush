module AresMUSH
  module Pf2e

    # `+e/how <name>`: the commands that do what a player names - an action, a Strike, a spell, an item
    # they carry, or something the game does, like spending a Hero Point (`HowTo`). In an encounter, what
    # they carry is the encounter's copy.
    class PF2EncounterHowCmd
      include CommandHandler

      attr_accessor :name

      def parse_args
        self.name = trim_arg(cmd.args)
      end

      def required_args
        [ self.name ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        holder = (encounter && CombatantStates.of(encounter, enactor)) || enactor
        found = HowTo.answers(self.name, HowTo.known(enactor, holder))

        return if CharState.emit_error!(client, found)

        width = found.state.map { |command, _about| command.length }.max
        lines = found.state.map { |command, about| "  #{command.ljust(width)}  #{about}" }

        client.emit ([ t('pf2e.how_title', :name => self.name) ] + lines).join('%r')
      end
    end
  end
end
