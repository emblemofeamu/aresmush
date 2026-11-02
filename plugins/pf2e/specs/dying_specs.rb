require "plugin_test_loader"

module AresMUSH

  # Taking a character to nothing, and picking them back up.
  #
  # Both paths read `char.pf2e_conditions`, which is not an attribute of anything - the reader is
  # `pf2_conditions`. So a DM's `damage` that drops someone to nothing raised NoMethodError and the
  # character was never put into Dying, and healing a character who was already at full damage raised
  # the same on the line that should have made them Wounded.
  describe Pf2eHP, :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Dying#{rand(1000000)}")
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 12)
      @char.update(:hp => @hp, :pf2_conditions => {})
    end

    after(:each) do
      @hp.delete if @hp
      @char.delete if @char
    end

    def reread
      Character[@char.id]
    end

    it "should have a character with hit points to take away" do
      expect(Pf2eHP.get_max_hp(@char)).to be > 0
    end

    it "should not raise when damage takes a character to nothing" do
      expect { Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true) }.to_not raise_error
    end

    it "should put a character taken to nothing into Dying" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)

      expect(Pf2e.condition_level(reread, 'Dying')).to eq 1
    end

    # Dying goes up by one more for each point of Wounded already carried.
    it "should start Dying higher for a character who is already Wounded" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 1, 'status' => true } })

      Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
    end

    it "should not raise when healing a character who is at full damage" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)

      expect { Pf2eHP.modify_damage(reread, 5, true) }.to_not raise_error
    end

    it "should make a healed character Wounded and no longer Dying" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)
      Pf2eHP.modify_damage(reread, 5, true)

      expect(Pf2e.condition_level(reread, 'Wounded')).to eq 1
      expect(Pf2e.get_condition_value(reread, 'Dying')).to be_nil
    end

    # Wounded comes with losing Dying, once: someone who stopped dying on their own is already wounded
    # for it, and healing them adds nothing more.
    it "should not wound again someone healed after they stopped dying" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)
      Pf2e.remove_condition(reread, 'Dying', true)
      Pf2e.set_condition(reread, 'Wounded', 1)

      Pf2eHP.modify_damage(reread, 5, true)

      expect(Pf2e.condition_level(reread, 'Wounded')).to eq 1
    end

    it "should kill a character whose Dying reaches four" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 3, 'status' => true } })

      fate = Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(fate).to eq :dead
      expect(reread.pf2_is_dead).to be true
    end

    it "should do nothing more to the dead" do
      @char.update(:pf2_is_dead => true, :pf2_conditions => { 'Dying' => { 'value' => 4, 'status' => true } })
      @hp.update(:damage => Pf2eHP.get_max_hp(@char))

      Pf2eHP.modify_damage(reread, 5, true)

      expect(Pf2eHP.get_current_hp(reread)).to eq 0
      expect(Pf2e.condition_level(reread, 'Dying')).to eq 4
    end

    it "should list the dead as dead" do
      @char.update(:pf2_is_dead => true)

      expect(Pf2e.condition_labels(reread, false).first).to eq 'Dead'
    end

    # Doomed lowers the threshold a character dies at.
    it "should kill a Doomed character sooner" do
      @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 2, 'status' => true },
                                        'Doomed' => { 'value' => 1, 'status' => true } })

      Pf2eHP.modify_damage(reread, Pf2eHP.get_max_hp(@char), false, true)

      expect(reread.pf2_is_dead).to be true
    end

    # A hit smaller than the temporary hit points is absorbed entirely - and the reduced pool has
    # to be written down, or the same temporary hit points soak every hit that comes.
    it "should record temporary hit points spent absorbing a hit" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 3, false, true)

      expect(Pf2eHP[@hp.id].temp_hp).to eq 2
    end

    it "should leave real hit points alone while temporary ones absorb the hit" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 3, false, true)

      expect(Pf2eHP[@hp.id].damage).to eq 0
    end

    it "should spend the temporary pool and carry the rest to real damage" do
      @hp.update(:temp_hp => 5)

      Pf2eHP.modify_damage(reread, 8, false, true)

      expect(Pf2eHP[@hp.id].temp_hp).to eq 0
      expect(Pf2eHP[@hp.id].damage).to eq 3
    end

    # A Strike in a fight is not a GM's word that a character may die, but it still drops them.
    describe "damage that may not kill" do
      def max
        Pf2eHP.get_max_hp(reread)
      end

      it "should put a character taken to nothing into Dying" do
        Pf2eHP.modify_damage(@char, max + 7, false, false)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 1
      end

      it "should take them no lower than nothing" do
        Pf2eHP.modify_damage(@char, max + 7, false, false)

        expect(Pf2eHP.get_current_hp(reread)).to eq 0
      end

      it "should raise Dying by one when they are hit again while dying" do
        Pf2eHP.modify_damage(@char, max, false, false)
        Pf2eHP.modify_damage(reread, 3, false, false)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
      end

      # The rules' Dying 4 is death; damage that may not kill leaves them unconscious instead, no longer
      # dying and wounded for it.
      it "should leave them unconscious rather than dead" do
        @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 3, 'status' => true } })

        fate = Pf2eHP.modify_damage(reread, max, false, false)

        expect(fate).to eq :spared
        expect(reread.pf2_is_dead).to be_falsey
        expect(Pf2e.condition_level(reread, 'Dying')).to eq 0
        expect(Pf2e.condition_level(reread, 'Wounded')).to eq 4
        expect(reread.pf2_conditions['Unconscious']['granted_by']).to eq Pf2eHP::NO_HIT_POINTS
      end

      # Outside an encounter nobody has said a character may die.
      it "should be what damage is when nobody says" do
        @char.update(:pf2_conditions => { 'Wounded' => { 'value' => 3, 'status' => true } })

        expect(Pf2eHP.modify_damage(reread, max)).to eq :spared
      end
    end

    # A critical hit that drops a character leaves them Dying 2, and one that hits them while dying
    # raises it by two.
    describe "a critical hit" do
      it "should leave a character it drops Dying 2" do
        Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, false, nil, [], :critical => true)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
      end

      it "should raise Dying by two" do
        Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, false)
        Pf2eHP.modify_damage(reread, 1, false, false, nil, [], :critical => true)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 3
      end
    end

    # A hit that deals two kinds of damage is one hit: what the first kind dropped, the second does not
    # drop again.
    describe "the rest of a hit that has already dropped them" do
      def max
        Pf2eHP.get_max_hp(reread)
      end

      it "should not raise Dying again" do
        Pf2eHP.modify_damage(@char, max, false, true, nil, [], :critical => true)
        Pf2eHP.modify_damage(reread, 9, false, true, nil, [], :critical => true, :continuing => true)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
        expect(reread.pf2_is_dead).to be_falsey
      end

      it "should drop them where the first of it did not" do
        Pf2eHP.modify_damage(@char, max - 1, false, true)
        Pf2eHP.modify_damage(reread, 9, false, true, nil, [], :continuing => true)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 1
      end

      it "should not raise Dying for someone it found dying, more than the hit already has" do
        Pf2eHP.modify_damage(@char, max, false, true)
        Pf2eHP.modify_damage(reread, 3, false, true)
        Pf2eHP.modify_damage(reread, 3, false, true, nil, [], :continuing => true)

        expect(Pf2e.condition_level(reread, 'Dying')).to eq 2
      end
    end

    # Resistance that takes the whole of a hit leaves no damage taken, and so no nearer death.
    it "should leave Dying as it was after a hit that dealt nothing" do
      Pf2eHP.modify_damage(@char, Pf2eHP.get_max_hp(@char), false, true)
      Pf2eHP.modify_damage(reread, 0, false, true)

      expect(Pf2e.condition_level(reread, 'Dying')).to eq 1
    end

    it "should leave a character standing who is only hurt" do
      Pf2eHP.modify_damage(@char, 1, false, true)

      expect(reread.pf2_is_dead).to be_falsey
      expect(Pf2e.condition_level(reread, 'Dying')).to eq 0
    end
  end
end
