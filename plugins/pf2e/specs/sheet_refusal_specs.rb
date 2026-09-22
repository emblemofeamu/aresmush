require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Every refusal a sheet command makes, spoken rather than raised.
    #
    # `t` takes keywords, so handing it an args hash positionally is two arguments and Ruby 3 raises
    # `ArgumentError` - even when the hash is empty. The sheet commands only reach that line when
    # something is refused, and nothing drove them through a refusal, so the player got the
    # dispatcher's generic error and the log got a backtrace.
    describe "a sheet command's refusals" do

      class SheetRefusalClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit emit_success emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }

        def screen_reader
          false
        end
      end

      def viewer(name = 'Viewer')
        double(:name => name, :is_admin? => false, :has_permission? => false, :pf2_viewsheet => {})
      end

      # A character with no sheet at all, which is what `admin/reset` leaves behind.
      def blank(name = 'Viewer')
        double(:name => name, :is_admin? => false, :has_permission? => false, :magic => nil,
               :pf2_baseinfo_locked => false, :pf2_viewsheet => {})
      end

      def caster_less(name = 'Viewer')
        double(:name => name, :is_admin? => false, :has_permission? => false, :magic => nil,
               :pf2_baseinfo_locked => true, :pf2_viewsheet => {})
      end

      def run(klass, char, text, enactor: nil)
        client = SheetRefusalClient.new
        handler = klass.new(client, Command.new(text), enactor || char)

        allow(Pf2e).to receive(:get_character).and_return(char)

        handler.parse_args
        handler.handle

        client
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e', 'open_sheets').and_return(false)
      end

      describe PF2DisplaySheetCmd do
        it "should say a character has no sheet yet" do
          client = run(PF2DisplaySheetCmd, blank, 'sheet')

          expect(client.failures.size).to eq 1
          expect(client.failures.first).to_not include('%{')
        end

        it "should name a section that does not exist" do
          client = run(PF2DisplaySheetCmd, caster_less, 'sheet/nonsense')

          expect(client.failures.first).to include('nonsense')
        end

        it "should say a character casts nothing" do
          client = run(PF2DisplaySheetCmd, caster_less, 'sheet/magic')

          expect(client.failures.size).to eq 1
        end

        it "should refuse a viewer who may not look" do
          client = run(PF2DisplaySheetCmd, caster_less('Shown'), 'sheet Shown', :enactor => viewer)

          expect(client.failures.size).to eq 1
        end
      end

      describe PF2DisplayCombatSheetCmd do
        it "should say a character has no sheet yet" do
          client = run(PF2DisplayCombatSheetCmd, blank, 'sheet/combat')

          expect(client.failures.size).to eq 1
        end
      end

      describe PF2ShowSheetCmd do
        it "should refuse to share a section the sharer has not got" do
          other = caster_less('Someone')
          allow(ClassTargetFinder).to receive(:find).and_return(double(:found? => true, :target => other))

          client = run(PF2ShowSheetCmd, caster_less, 'sheet/show Someone=magic')

          expect(client.failures.size).to eq 1
        end
      end
    end
  end
end
