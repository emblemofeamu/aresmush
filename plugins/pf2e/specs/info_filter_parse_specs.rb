require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # `cg/info <thing>=<text>`, `advance/info <thing>=<text>` and `spell/eligible <rank>=<text>`
    # narrow a long option list.
    #
    # Without it the hint behind a big pool - "236 eligible options, use advance/info Additional
    # Lore" - hands back six pages, which is barely more use than the refusal that sent the player
    # there.
    #
    # All three take the same shape, and the half that matters most is the one with no filter: a
    # parser that insists on the `=` refuses exactly the forms the help offers - `spell/eligible 3`
    # did nothing but reprint the source summary that told the player to type it.
    describe "the info commands' arguments" do

      # What each command's first half is called: a feat or an element for the info commands, a rank
      # for the spell list.
      def element_for(klass)
        klass == Pf2emagic::PF2SpellEligibleCmd ? 'cantrip' : 'Additional Lore'
      end

      def short_element_for(klass)
        klass == Pf2emagic::PF2SpellEligibleCmd ? '3' : 'skill'
      end

      def parsed(klass, args, reader = :element)
        handler = klass.new(double, double(:args => args, :page => 1), double)
        handler.parse_args
        handler.define_singleton_method(:element) { send(reader) } unless reader == :element
        handler
      end

      [ [ PF2ChargenInfoCmd, :element ], [ PF2AdvanceInfoCmd, :element ],
        [ Pf2emagic::PF2SpellEligibleCmd, :rank ] ].each do |klass, reader|
        describe klass.name.split('::').last do
          it "should take an element on its own" do
            handler = parsed(klass, element_for(klass), reader)

            expect(handler.element.to_s.downcase).to eq element_for(klass).downcase
            expect(handler.filter).to be_nil
          end

          it "should split a filter off the element" do
            handler = parsed(klass, "#{element_for(klass)}=arch", reader)

            expect(handler.element.to_s.downcase).to eq element_for(klass).downcase
            expect(handler.filter).to eq 'arch'
          end

          it "should keep an element whose own name has no filter after it" do
            expect(parsed(klass, short_element_for(klass), reader).filter).to be_nil
          end

          it "should not be confused by spaces around the equals" do
            handler = parsed(klass, "#{element_for(klass)} = arch", reader)

            expect(handler.element.to_s.downcase).to eq element_for(klass).downcase
            expect(handler.filter).to eq 'arch'
          end

          it "should treat an empty filter as no filter" do
            expect(parsed(klass, "#{element_for(klass)}=", reader).filter).to be_nil
          end
        end
      end
    end
  end
end
