require "plugin_test_loader"

module AresMUSH

  # Size, auras and battle forms: what an effect makes of the character's body, and what it puts on the
  # people around them. Each is Foundry's own rule, read with no command yet to drive it.
  describe "forms, size and auras", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @chars = []
      @char = person("Form")
      @items = []
    end

    after(:each) do
      @chars.each do |char|
        Pf2e::ActiveEffects.on(Character[char.id]).each(&:delete)
        [ char.combat, char.hp ].compact.each(&:delete)
        char.abilities.each(&:delete)
        char.delete
      end
      @items.each(&:delete)
    end

    def person(prefix)
      char = Character.create(:name => "#{prefix}#{rand(1000000)}")
      combat = Pf2eCombat.create(:character => char, :armor_prof => { 'unarmored' => 'trained' },
                                 :unarmed_prof => 'trained', :weapon_prof => { 'unarmed' => 'trained' })
      hp = Pf2eHP.create(:character => char, :ancestry_hp => 8, :charclass_hp => 10)
      char.update(:combat => combat, :hp => hp, :pf2_level => 5, :pf2_conditions => {}, :pf2_traits => [],
                  :pf2_derived => {}, :pf2_feats => {}, :pf2_movement => { 'Size' => 'M', 'base_speed' => 25 })
      Pf2e::ABILITIES.each { |name| Pf2eAbilities.create(:character => char, :name => name, :base_val => 12) }
      @chars << char

      Character[char.id]
    end

    def reread(char = @char)
      Character[char.id]
    end

    def apply(name, options = [], char = @char)
      Pf2e::ActiveEffects.apply(reread(char), name, :options => options).state
    end

    describe "size" do
      it "should be the ancestry's until something changes it" do
        expect(Pf2e::Size.of(reread)).to eq('size' => 'med', 'reach' => 5)
      end

      # Shrinking Potion makes you tiny, and a tiny creature reaches nothing.
      it "should be what an effect names" do
        apply('Shrinking Potion')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'tiny', 'reach' => 0)
      end

      # Applereed Mutagen makes you one size larger, and says your reach does not change with it.
      it "should step up one size, and keep reach where the rule says" do
        apply('Applereed Mutagen (Lesser)')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'lg', 'reach' => 5)
      end

      # Bone Swarm makes you huge and says nothing of reach, so reach grows with the size.
      it "should grow reach with the size where the rule says nothing of it" do
        apply('Bone Swarm')

        expect(Pf2e::Size.of(reread)).to eq('size' => 'huge', 'reach' => 15)
      end

      it "should be something a predicate can ask about" do
        apply('Shrinking Potion')

        expect(Pf2e::Effects.facts(reread)).to include 'self:size:tiny', 'self:size:0'
      end
    end

    # Animal Form (Bear) at 2nd rank: AC 16 + level, attacks at +9, a land speed of 30 feet and scent.
    describe "a battle form" do
      before(:each) { apply('Animal Form (Bear)', [ 'rank 2' ]) }

      it "should be the form the character is in" do
        expect(Pf2e::BattleForms.active?(reread)).to be true
      end

      it "should give the form's AC, since AC does not keep the character's own" do
        expect(Pf2e::Stat.total(reread, 'ac')).to eq 16 + 5
      end

      it "should keep a status penalty on top of it" do
        Pf2e.set_condition(reread, 'Frightened', 2)

        expect(Pf2e::Stat.total(reread, 'ac')).to eq 16 + 5 - 2
      end

      it "should give the form's attacks, at the form's modifier where it is better" do
        claw = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'claw' }

        expect(Pf2e::Stat.total(reread, 'attack', claw)).to eq 9
      end

      it "should roll the form's damage with the form's own modifier" do
        claw = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'claw' }

        expect(Pf2e::Damage.formula(reread, claw)).to start_with '1d8+1'
      end

      it "should offer only the form's attacks" do
        expect(Pf2e::Actors.of(reread).attacks.map { |names, _attack| names.first }).to contain_exactly 'Claw', 'Jaws'
      end

      it "should offer the character's own attacks again once it ends" do
        Pf2e::ActiveEffects.remove_named(reread, 'Animal Form (Bear)')

        expect(Pf2e::Actors.of(reread).attacks.map { |names, _attack| names.first }).to_not include 'Jaws'
      end

      describe "with invested handwraps" do
        before(:each) do
          name = 'Handwraps of Mighty Blows (+1 Striking)'
          item = Pf2egear.create_item(@char, 'weapons', name, 1, Global.read_config('pf2e_weapons', name))
          item.update(:invested => true, :runes => { 'fundamental' => { 'potency' => 1, 'power' => 1 } })
          @items << item
        end

        def claw
          Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'claw' }
        end

        # Level 12, trained and Strength +1: +15 of their own, +16 with the handwraps, past the form's +9.
        it "should count their potency where the character's own modifier is used" do
          reread.update(:pf2_level => 12)

          expect(Pf2e::Stat.total(reread, 'attack', claw)).to eq 16
        end

        it "should not count their potency on the form's own modifier" do
          Pf2e::ActiveEffects.remove_named(reread, 'Animal Form (Bear)')
          apply('Animal Form (Bear)', [ 'rank 5' ])

          expect(Pf2e::Stat.total(reread, 'attack', claw)).to eq 18
        end

        it "should not count their striking rune" do
          reread.update(:pf2_level => 12)

          expect(Pf2e::Damage.formula(reread, claw)).to start_with '1d8'
        end
      end

      it "should replace the character's speeds" do
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 30
      end

      it "should give its senses through the ordinary rule" do
        expect(Pf2e::Effects.senses(reread).map { |one| one['name'] }).to include 'scent', 'low-light-vision'
      end

      it "should say the character is polymorphed" do
        expect(Pf2e::Effects.options(reread)).to include 'polymorph', 'battle-form'
      end

      it "should give its temporary hit points" do
        expect(reread.hp.temp_hp).to eq 5
      end

      it "should be over when the effect is" do
        Pf2e::ActiveEffects.remove_named(reread, 'Animal Form (Bear)')

        expect(Pf2e::BattleForms.active?(reread)).to be false
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 25
      end
    end

    # An effect with several shapes has a row for each, and the answer it was applied with picks one.
    describe "a battle form picked by an answer" do
      def forms
        Pf2e::BattleForms.active(reread)
      end

      # Insect Form at 3rd rank: AC 18 + level and +13 mandibles either way, on different legs.
      it "should be the shape answered, with that shape's own figures" do
        apply('Insect Form', [ 'rank 3', 'beetle' ])

        expect(Pf2e::BattleForms.active?(reread)).to be true
        expect(Pf2e::Stat.total(reread, 'ac')).to eq 18 + 5
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 25
        expect(forms['form']['speeds']).to eq('land' => 25)
      end

      it "should tell one shape of an effect from another" do
        apply('Insect Form', [ 'rank 3', 'ant' ])

        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 30
        expect(forms['form']['speeds']).to eq('climb' => 30, 'land' => 30)
      end

      it "should give the shape's attacks and temporary hit points" do
        apply('Insect Form', [ 'rank 3', 'beetle' ])

        mandibles = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'mandibles' }

        expect(Pf2e::Stat.total(reread, 'attack', mandibles)).to eq 13
        expect(reread.hp.temp_hp).to eq 10
      end

      it "should give a ranged attack its reach" do
        apply('Insect Form', [ 'rank 3', 'spider' ])

        web = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'web' }

        expect(web).to include('ranged' => true, 'range' => 20)
      end

      # Every row of every form, at every rank it has figures for, as the sheet and a Strike read them.
      it "should be able to read every attack of every form" do
        forms = Pf2e::ActiveEffects.catalogue.select do |_name, info|
          Array(info['rules']).any? { |one| one['key'] == 'BattleForm' }
        end

        unreadable = forms.flat_map do |name, info|
          apply(name, [ 'rank 10' ])
          effect = Pf2e::ActiveEffects.on(reread).find { |one| one.name == name }

          found = Array(info['rules']).select { |one| one['key'] == 'BattleForm' }.flat_map do |row|
            ([ 0 ] + Array(row['brackets']).map { |one| one['start'].to_i }).uniq.flat_map do |rank|
              Array(Pf2e::BattleForms.bracketed(row, rank)['strikes']).flat_map do |slug, strike|
                every = { 'form' => { 'strikes' => { slug => strike.except('predicate') } } }
                allow(Pf2e::BattleForms).to receive(:active).and_return(every.merge('effect' => effect))

                begin
                  Pf2e::BattleForms.strikes(reread).each do |attack|
                    Pf2e::Stat.total(reread, 'attack', attack)
                    Pf2e::Damage.formula(reread, attack)
                  end
                  []
                rescue StandardError => e
                  [ "#{name} #{slug} at rank #{rank}: #{e.class}: #{e.message}" ]
                end
              end
            end
          end

          allow(Pf2e::BattleForms).to receive(:active).and_call_original
          Pf2e::ActiveEffects.remove_named(reread, name)
          found
        end

        expect(unreadable).to eq []
      end

      # Cosmic Form has one row with the attacks of both its shapes, each saying which it belongs to.
      it "should give only the attacks of the shape answered, where one row lists them all" do
        apply('Cosmic Form', [ 'rank 7', 'moon' ])

        expect(Pf2e::BattleForms.strikes(reread).map { |one| one['slug'] }).to contain_exactly 'moon-fist', 'moonbeam'
      end

      # Demon Form's first row is for every shape but this one.
      it "should not take the row meant for the other shapes" do
        apply('Demon Form', [ 'rank 6', 'kithangian' ])

        rows = Pf2e::ActiveEffects.info('Spell Effect: Demon Form')['rules'].select { |one| one['key'] == 'BattleForm' }

        expect(forms['form']).to eq Pf2e::BattleForms.bracketed(rows.last, 6)
      end

      it "should be no form at all with no answer, or one the effect does not offer" do
        [ [ 'rank 3' ], [ 'rank 3', 'nonsense' ] ].each do |options|
          apply('Insect Form', options)

          expect(Pf2e::BattleForms.active?(reread)).to be false

          Pf2e::ActiveEffects.remove_named(reread, 'Insect Form')
        end
      end

      {
        'Worm Form' => 'hybrid', 'Aberrant Form' => 'chuul', 'Aerial Form' => 'bat', 'Angel Form' => 'balisse',
        'Daemon Form' => 'lacridaemon', 'Demon Form' => 'kithangian', 'Devil Form' => 'coarti',
        'Devouring Dark Form' => 'shark', 'Elemental Form' => 'air', 'Fey Form' => 'dryad',
        'Monstrosity Form' => 'cave-worm', 'Nature Incarnate' => 'green-man', 'Ooze Form' => 'black-pudding',
        'Plant Form' => 'flytrap'
      }.each do |effect, answer|
        it "should hold for #{effect} answered #{answer}" do
          apply(effect, [ answer ])

          expect(Pf2e::BattleForms.active?(reread)).to be true
        end
      end
    end

    # Dragon Form asks which dragon, and its answer is a whole set of figures its rules read parts of.
    describe "a dragon form" do
      def own_options
        Pf2e::ActiveEffects.own_options(reread, Pf2e::ActiveEffects.on(reread).first)
      end

      def resistance(type)
        Pf2e::IWR.of(reread)['resistance'].find { |one| one['type'] == type }&.fetch('value')
      end

      it "should say which dragon, and from which tradition" do
        apply('Dragon Form', [ 'rank 6', 'forest dragon' ])

        expect(own_options).to include 'dragon-form:forest', 'dragon-form-tradition:primal'
      end

      it "should be the form, at its own figures" do
        apply('Dragon Form', [ 'rank 6', 'forest dragon' ])

        expect(Pf2e::Stat.total(reread, 'ac')).to eq 18 + 5
        expect(Pf2e::Stat.total(reread, 'speed', 'land')).to eq 40
        expect(Pf2e::Stat.total(reread, 'speed', 'fly')).to eq 100
      end

      it "should give only the speeds the dragon has" do
        apply('Dragon Form', [ 'rank 6', 'brine dragon' ])

        expect(Pf2e::Stat.total(reread, 'speed', 'swim')).to eq 60
        expect(Pf2e::Stat.total(reread, 'speed', 'burrow')).to eq 0
      end

      it "should resist the damage the dragon deals" do
        apply('Dragon Form', [ 'rank 6', 'forest dragon' ])

        expect(resistance('piercing')).to eq 10
      end

      # A brine dragon's is bludgeoning, on jaws that otherwise only pierce.
      it "should deal that damage with its jaws" do
        apply('Dragon Form', [ 'rank 6', 'brine dragon' ])

        jaws = Pf2e::BattleForms.strikes(reread).find { |one| one['slug'] == 'jaws' }

        expect(Pf2e::Damage.formula(reread, jaws)).to include 'bludgeoning'
      end

      # A caster of the dragon's own tradition resists more: primal is physical 5.
      it "should give its tradition's resistance to a caster of that tradition" do
        apply('Dragon Form', [ 'rank 6', 'forest dragon', 'tradition primal' ])

        expect(resistance('physical')).to eq 5
      end

      it "should not give it to a caster of another, or to one who doesn't say" do
        apply('Dragon Form', [ 'rank 6', 'forest dragon', 'tradition arcane' ])
        expect(resistance('physical')).to be_nil

        Pf2e::ActiveEffects.remove_named(reread, 'Dragon Form')

        apply('Dragon Form', [ 'rank 6', 'forest dragon' ])
        expect(resistance('physical')).to be_nil
      end
    end

    # Angelic Halo puts its effect on allies inside it.
    describe "an aura" do
      before(:each) do
        @ally = person("Ally")
        @foe = person("Foe")
        apply('Angelic Halo')
      end

      def halo
        Pf2e::Auras.of(reread).first
      end

      it "should say what it projects" do
        expect(halo['radius']).to eq 15
        expect(halo['effects'].map { |one| one['name'] }).to eq [ 'Spell Effect: Angelic Halo' ]
      end

      it "should put its effect on an ally inside it" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')

        expect(Pf2e::ActiveEffects.on(reread(@ally)).map(&:name)).to eq [ 'Spell Effect: Angelic Halo' ]
      end

      it "should not put it on an enemy, whom it does not affect" do
        Pf2e::Auras.enter(reread, reread(@foe), halo['slug'], 'enemy')

        expect(Pf2e::ActiveEffects.on(reread(@foe))).to eq []
      end

      it "should not put it on anyone twice" do
        2.times { Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally') }

        expect(Pf2e::ActiveEffects.on(reread(@ally)).size).to eq 1
      end

      it "should take it away when they leave" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')
        Pf2e::Auras.leave(reread, reread(@ally), halo['slug'])

        expect(Pf2e::ActiveEffects.on(reread(@ally))).to eq []
      end

      it "should take it from everyone when the aura ends" do
        Pf2e::Auras.enter(reread, reread(@ally), halo['slug'], 'ally')
        Pf2e::ActiveEffects.remove_named(reread, 'Angelic Halo')

        expect(Pf2e::ActiveEffects.on(reread(@ally))).to eq []
      end
    end
  end
end
