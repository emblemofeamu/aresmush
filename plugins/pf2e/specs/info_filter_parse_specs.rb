require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `cg/info <thing>=<text>` and `advance/info <thing>=<text>` narrow a long option list.
    #
    # Without it the hint behind a big pool - "236 eligible options, use advance/info Additional
    # Lore" - hands back six pages, which is barely more use than the refusal that sent the player
    # there.
    describe "the info commands' arguments" do

      def parsed(klass, args)
        handler = klass.new(double, double(:args => args, :page => 1), double)
        handler.parse_args
        handler
      end

      [ PF2ChargenInfoCmd, PF2AdvanceInfoCmd ].each do |klass|
        describe klass.name.split('::').last do
          it "should take an element on its own" do
            handler = parsed(klass, 'Additional Lore')

            expect(handler.element.to_s.downcase).to eq 'additional lore'
            expect(handler.filter).to be_nil
          end

          it "should split a filter off the element" do
            handler = parsed(klass, 'Additional Lore=arch')

            expect(handler.element.to_s.downcase).to eq 'additional lore'
            expect(handler.filter).to eq 'arch'
          end

          it "should keep an element whose own name has no filter after it" do
            expect(parsed(klass, 'skill').filter).to be_nil
          end

          it "should not be confused by spaces around the equals" do
            handler = parsed(klass, 'Additional Lore = arch')

            expect(handler.element.to_s.downcase).to eq 'additional lore'
            expect(handler.filter).to eq 'arch'
          end

          it "should treat an empty filter as no filter" do
            expect(parsed(klass, 'Additional Lore=').filter).to be_nil
          end
        end
      end
    end
  end
end
