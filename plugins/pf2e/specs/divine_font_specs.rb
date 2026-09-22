require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Chargen

      # Choosing a divine font.
      #
      # Only a deity that grants both asks, so the pool marker is the question and the chosen word is
      # the answer. The word goes on the magic object, which a core may not write - so the core says
      # which it was and the shell writes it.
      describe DivineFont do

        def state(offered = [ 'heal', 'harm' ])
          CharState.build({ 'name' => 'Tester', 'to_assign' => { 'divine font' => offered } },
                          :config => ConfigView.fixture({}))
        end

        it "should resolve the marker to the chosen font" do
          result = DivineFont.choose(state, 'font' => 'heal')

          expect(result.state['to_assign']['divine font']).to eq 'heal'
          expect(result.state['divine_font']).to eq 'heal'
        end

        it "should refuse when the deity does not offer a choice" do
          expect(DivineFont.choose(state(nil), 'font' => 'heal').code).to eq :no_option
        end

        it "should refuse a font that is not one of the two" do
          expect(DivineFont.choose(state, 'font' => 'hurt').code).to eq :bad_font
        end

        it "should take the font however it was typed" do
          expect(DivineFont.choose(state, 'font' => 'HARM').state['divine_font']).to eq 'harm'
        end
      end
    end
  end
end
