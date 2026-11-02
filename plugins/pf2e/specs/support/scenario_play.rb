module AresMUSH
  module Pf2e

    # What a played-encounter spec does around its runner: hears what the game emits, audits every roll,
    # defence and hit as it happens, and keeps the transcript and report where SCENARIO_OUT says.
    # Included in the spec's describe block.
    module ScenarioPlay

      # The room's emits, and what a player or the GM is told on their own, go to the runner's
      # transcript; the runner's staff member is the only admin, who is its GM unless the scenario seats
      # another kind.
      def heard_by(runner)
        allow_any_instance_of(Room).to receive(:emit) { |_room, message| runner.heard(message) }
        allow_any_instance_of(Room).to receive(:emit_ooc) { |_room, message| runner.heard(message) }
        allow(Login).to receive(:emit_ooc_if_logged_in) { |who, message| runner.heard(message, who&.name) }
        allow(Login).to receive(:emit_if_logged_in) { |who, message| runner.heard(message, who&.name) }
        allow_any_instance_of(Character).to receive(:is_admin?) { |char| char.id == runner.staff&.id }
      end

      # Every roll, defence and hit the fight makes, handed to the audit as it happens.
      def audited(audit)
        allow(Resolve).to receive(:roll).and_wrap_original do |original, check, **opts|
          result = original.call(check, **opts)
          audit.safely("roll #{check.kind}") { audit.rolled(check, opts[:dc], result) }
          result
        end

        allow(Resolve).to receive(:defence).and_wrap_original do |original, holder, against, **opts|
          result = original.call(holder, against, **opts)
          audit.safely("defence #{against}") { audit.defended(holder, against, result) }
          result
        end

        %i{of_instances of_formulas}.each do |name|
          allow(DamageRoll).to receive(name).and_wrap_original do |original, rows, critical, *rest|
            result = original.call(rows, critical, *rest)
            audit.safely("damage #{name}") { audit.dealt_rows(result, critical) }
            result
          end
        end

        # What each hit being dealt has landed after resistances, innermost last.
        landing = []

        allow(Acting).to receive(:deal).and_wrap_original do |original, scene, whom, rows, out, **opts|
          before = audit_dying(whom.holder)
          landing << 0
          result = begin
            original.call(scene, whom, rows, out, **opts)
          ensure
            dealt = landing.pop
          end
          # A blow not meant to kill knocks them out, and leaves them no nearer death.
          spared = out['lines'].any? { |line| line.is_a?(Hash) && line['key'] == 'pf2e.act_knocked_out' }
          audit.safely("hit on #{whom.label}") { audit.hit_dropped(whom.label, before, audit_dying(whom.holder), opts[:critical], dealt) } if before && !spared
          result
        end

        allow(Harm).to receive(:damage).and_wrap_original do |original, holder, amount, type = nil, **opts|
          before = audit_hp(holder)
          result = original.call(holder, amount, type, **opts)
          landing[-1] += result['amount'].to_i if landing.any? && result.is_a?(Hash)
          audit.safely("damage to #{holder.name}") { audit.landed(holder, amount, type, before, audit_hp(holder), result) }
          result
        end
      end

      # A character as a hit finds and leaves them, for what it does to their dying.
      def audit_dying(holder)
        fresh = holder.class[holder.id]

        return nil if Actors.of(fresh).creature?

        { 'hp' => Pf2eHP.get_current_hp(fresh), 'temp' => fresh.temp_hp.to_i, 'dying' => Pf2e.condition_level(fresh, 'Dying'),
          'wounded' => Pf2e.condition_level(fresh, 'Wounded'), 'doomed' => Pf2e.condition_level(fresh, 'Doomed'),
          'dead' => Pf2e.dead?(fresh) }
      end

      # Hit points with temporary ones, which take damage first.
      def audit_hp(holder)
        fresh = holder.class[holder.id]

        if Actors.of(fresh).creature?
          fresh.hp_left.to_i + fresh.temp_hp.to_i
        else
          Pf2eHP.get_current_hp(fresh) + fresh.temp_hp.to_i
        end
      end

      # The transcript and the report, and whatever else the runner wrote, by name.
      def keep(runner, stem, extra = {})
        dir = ENV['SCENARIO_OUT']

        return unless dir

        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{stem}-transcript.md"), runner.lines.join("\n"))
        File.write(File.join(dir, "#{stem}-report.md"), runner.report)
        extra.each { |suffix, text| File.write(File.join(dir, "#{stem}-#{suffix}.md"), text) }
      end
    end
  end
end
