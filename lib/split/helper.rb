module Split
  module Helper
    def ab_test(experiment_name, *alternatives)
      experiment = Split::Experiment.find_or_create(experiment_name, *alternatives)
      if experiment.winner
        ret = experiment.winner.name
      else
        if forced_alternative = override(experiment.name, alternatives)
          ret = forced_alternative
        else
          begin_experiment(experiment, experiment.control.name) if exclude_visitor?

          if ab_user[experiment.key]
            ret = ab_user[experiment.key]
          else
            alternative = experiment.next_alternative
            alternative.increment_participation
            begin_experiment(experiment, alternative.name)
            ret = alternative.name
          end
        end
      end

      if block_given?
        if defined?(capture) # a block in a rails view
          block = Proc.new { yield(ret) }
          concat(capture(ret, &block))
          false
        else
          yield(ret)
        end
      else
        ret
      end
    end

    def finished(experiment_name, options = {:reset => true})
      return if exclude_visitor?
      return unless (experiment = Split::Experiment.find(experiment_name))
      if alternative_name = ab_user[experiment.key]
        alternative = Split::Alternative.new(alternative_name, experiment_name)
        alternative.increment_completion

        if options[:reset]
          cookie_val = cookies[:split] || Hash.new.to_json
          hsh = JSON.parse(cookie_val)
          hsh.delete(experiment_name)
          cookies[:split] = {:value => hsh.to_json, :expires => 1.year.from_now.utc}
        end
      end
    end

    def override(experiment_name, alternatives)
      params[experiment_name] if defined?(params) && alternatives.include?(params[experiment_name])
    end

    def begin_experiment(experiment, alternative_name)
      #ab_user[experiment.key] = alternative_name
      cookie_val = cookies[:split] || Hash.new.to_json
      hsh = JSON.parse(cookie_val)
      hsh.store(experiment.key, alternative_name)

      cookies[:split] = {:value => hsh.to_json, :expires => 1.year.from_now.utc}
    end

    def ab_user
      #session[:split] ||= {}
      cookie_val = cookies[:split] || Hash.new.to_json
      JSON.parse(cookie_val)
    end

    def get_alternative_for_user(experiment_name, *alternatives)
      experiment = Split::Experiment.find_or_create(experiment_name, *alternatives)
      if experiment.winner && ab_user[experiment.key].present?
        ret = experiment.winner.name
      else
        if forced_alternative = override(experiment.name, alternatives)
          ret = forced_alternative
        else
          if ab_user[experiment.key]
            ret = ab_user[experiment.key]
          else
            ret = nil
          end
        end
      end
    end

    def exclude_visitor?
      is_robot? or is_ignored_ip_address?
    end

    def is_robot?
      request.user_agent =~ Split.configuration.robot_regex
    end

    def is_ignored_ip_address?
      if Split.configuration.ignore_ip_addresses.any?
        Split.configuration.ignore_ip_addresses.include?(request.ip)
      else
        false
      end
    end
  end
end