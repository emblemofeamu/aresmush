require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Every door onto a balance names who moved it and why.
    #
    # `Audit.post` writes whatever it is handed, so a caller that passes neither leaves an amount
    # against an empty reason in the player's own history. The four nomination commands did exactly
    # that, on the most common award in the game, and nothing said so - the entry was there, which
    # is all the audit's own specs were asking.
    describe "a caller that moves a balance" do

      CALLS = /(?:Pf2e\.award_xp|Pf2egear\.pay_player)\(([^)]*)\)/

      def sources
        Dir[File.join(AresMUSH.game_path, '..', 'plugins', '**', '*.rb')]
          .reject { |path| path.include?('/specs/') }
      end

      # name, amount, by, reason - four before the optional ref.
      def anonymous_calls
        sources.each_with_object([]) do |path, found|
          File.read(path).each_line.with_index(1) do |line, number|
            next if line.strip.start_with?('#')

            match = CALLS.match(line)

            next unless match
            next if match[1].split(',').size >= 4

            found << "#{File.basename(path)}:#{number} #{line.strip}"
          end
        end
      end

      it "should say who moved it and what for" do
        expect(anonymous_calls).to eq []
      end
    end
  end
end
