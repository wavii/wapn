# # Configuration
require "wapn/provider"

module WAPN
  # This is extended into [`WAPN` proper](../wapn.html) to provide easy construction and access to
  # your configured providers.
  module Configuration

    # Returns the named provider.
    def provider(name)
      return nil unless @providers

      @providers[name.to_sym]
    end

    attr_reader :providers

    # ## WAPN.load_config
    #
    # Reads a config from YAML file, or passed as a Hash.  The configuration is a map of provider
    # names (identifiers used by your app) to the specific configuration values for that particular
    # provider (they are passed to [`Provider.new`](provider.html)).
    def load_config(path_or_hash)
      config = path_or_hash.is_a?(Hash) ? path_or_hash : load_yaml_config(path_or_hash)

      @providers ||= {}
      config.each do |name, options|
        @providers[name.to_sym] = Provider.new(options.merge(name: name))
      end
    end

  private

    def load_yaml_config(path)
      require "erb"
      require "yaml"

      # We do not execute this in SAFE mode to keep things simple.  It *is* a slim security risk,
      # but not one worth mitigating.
      #
      # For example, an attacker could point the config path to a remote URL (with open-uri loaded)
      # and enable themselves to execute code at configure time.  Of course, if they've accomplished
      # that, your app is likely already compromised.
      config_template = ERB.new(open(path).read)

      YAML.load(config_template.result)
    end

  end
end
