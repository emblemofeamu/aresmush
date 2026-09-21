require "plugin_test_loader"

module AresMUSH
  module Pf2egear

    # What a character can carry.
    #
    # Fifteen commands opened with the same `case self.category`, each with its own set of accepted
    # spellings - so `weapon` worked where `weapons` did not, and back again in the next command.
    describe Inventory do

      it "should accept every spelling a command used to accept" do
        expect(Inventory.categories).to include('weapon', 'weapons', 'armor', 'shield', 'shields',
                                               'bag', 'bags', 'magicitem', 'gear', 'consumables')
      end

      it "should answer with one canonical name per category" do
        expect(Inventory.canonical('weapon')).to eq 'weapons'
        expect(Inventory.canonical('shield')).to eq 'shields'
      end

      it "should not know a category that does not exist" do
        expect(Inventory.row('sandwich')).to be_nil
        expect(Inventory.canonical('sandwich')).to be_nil
      end

      # PF2e lets a character wear one suit of armour and hold one shield.
      describe "how many may be worn at once" do
        it "should allow one suit of armour and one shield" do
          expect(Inventory.single?('armor')).to be true
          expect(Inventory.single?('shields')).to be true
        end

        it "should allow as many weapons as they can carry" do
          expect(Inventory.single?('weapons')).to be false
        end
      end

      describe "what stacks" do
        it "should stack gear and consumables" do
          expect(Inventory.stackable?('gear')).to be true
          expect(Inventory.stackable?('consumables')).to be true
        end

        it "should keep a weapon as its own item, since each has its own runes" do
          expect(Inventory.stackable?('weapons')).to be false
        end
      end

      describe "what can be invested" do
        it "should name the three kinds PF2e lets a character invest" do
          invested = Inventory.categories.select { |c| Inventory.investable?(c) }.map { |c| Inventory.canonical(c) }.uniq

          expect(invested.sort).to eq %w(armor magicitem weapons)
        end
      end

      describe "what a bag holds" do
        # The character keeps magic items in `magic_items` and a bag keeps them in `magicitem`.
        # bag/store guessed the character's spelling wrong and raised NoMethodError.
        it "should know both spellings of the magic item collection" do
          row = Inventory.row('magicitem')

          expect(row['collection']).to eq :magic_items
          expect(row['in_bag']).to eq :magicitem
        end

        it "should leave a bag out of what a bag can hold" do
          expect(Inventory.bag_categories).to_not include 'bags'
        end
      end

      describe "what using an item requires" do
        it "should want armour and a weapon worn" do
          expect(Inventory.use_needs('armor')).to eq :equipped
          expect(Inventory.use_needs('weapons')).to eq :equipped
        end

        it "should want a magic item invested" do
          expect(Inventory.use_needs('magicitem')).to eq :invested
        end

        it "should want nothing of a consumable" do
          expect(Inventory.use_needs('consumables')).to be_nil
        end
      end

      it "should name a model for every category, and agree with the config" do
        classes = Global.read_config('pf2e_gear_options', 'item_classes') || {}

        expect(Inventory.categories.reject { |c| Inventory.model(c) }).to eq []
        expect(classes.keys.reject { |name| Inventory.row(name) }).to eq []
        classes.each_pair do |name, model|
          expect(Inventory.model(name).to_s).to eq "AresMUSH::#{model}"
        end
      end

      it "should say which of the two things was wrong when asked for an item" do
        char = double(:weapons => double(:to_a => []))

        expect(Inventory.item(char, 'sandwich', 0).code).to eq :bad_category
        expect(Inventory.item(char, 'weapons', 0).code).to eq :not_found
      end
    end
  end
end
