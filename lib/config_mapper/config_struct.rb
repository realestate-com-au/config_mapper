require "forwardable"

module ConfigMapper

  # A configuration container
  #
  class ConfigStruct

    class << self

      # Defines reader and writer methods for the specified attribute.
      #
      # A `:default` value may be specified; otherwise, the attribute is
      # considered mandatory.
      #
      # If a block is provided, it will invoked in the writer-method to
      # validate the argument.
      #
      # @param name [Symbol] attribute name
      # @options options [String] :default (nil) default value
      # @yield type-coercion block
      #
      def attribute(name, options = {}, &coerce_block)
        name = name.to_sym
        if options.key?(:default)
          default_value = options.fetch(:default).freeze
          attribute_initializers[name] = proc { default_value }
        else
          required_attributes << name
        end
        attr_reader(name)
        if coerce_block
          define_method("#{name}=") do |arg|
            instance_variable_set("@#{name}", coerce_block.call(arg))
          end
        else
          attr_writer(name)
        end
      end

      # Defines a sub-component.
      #
      def component(name, options = {}, &block)
        name = name.to_sym
        declared_components << name
        type = options.fetch(:type, ConfigStruct)
        type = Class.new(type, &block) if block
        type = type.method(:new) if type.respond_to?(:new)
        attribute_initializers[name] = type
        attr_reader name
      end

      # Defines an associative array of sub-components.
      #
      def component_dict(name, options = {}, &block)
        name = name.to_sym
        declared_component_dicts << name
        type = options.fetch(:type, ConfigStruct)
        type = Class.new(type, &block) if block
        type = type.method(:new) if type.respond_to?(:new)
        attribute_initializers[name] = lambda do
          ConfigDict.new(type)
        end
        attr_reader name
      end

      def required_attributes
        @required_attributes ||= []
      end

      def attribute_initializers
        @attribute_initializers ||= {}
      end

      def declared_components
        @declared_components ||= []
      end

      def declared_component_dicts
        @declared_component_dicts ||= []
      end

    end

    def initialize
      self.class.attribute_initializers.each do |name, initializer|
        instance_variable_set("@#{name}", initializer.call)
      end
    end

    def config_errors
      missing_required_attribute_errors.merge(component_config_errors)
    end

    private

    def components
      {}.tap do |result|
        self.class.declared_components.each do |name|
          result[name] = instance_variable_get("@#{name}")
        end
        self.class.declared_component_dicts.each do |name|
          instance_variable_get("@#{name}").each do |key, value|
            result["#{name}[#{key.inspect}]"] = value
          end
        end
      end
    end

    NOT_SET = "no value provided".freeze

    def missing_required_attribute_errors
      {}.tap do |errors|
        self.class.required_attributes.each do |name|
          unless instance_variable_defined?("@#{name}")
            errors[name.to_s] = NOT_SET
          end
        end
      end
    end

    def component_config_errors
      {}.tap do |errors|
        components.each do |component_name, component_value|
          next unless component_value.respond_to?(:config_errors)
          component_value.config_errors.each do |key, value|
            errors["#{component_name}.#{key}"] = value
          end
        end
      end
    end

  end

  class ConfigDict

    def initialize(entry_type)
      @entry_type = entry_type
      @entries = {}
    end

    def [](key)
      @entries[key] ||= @entry_type.call
    end

    extend Forwardable

    def_delegators :@entries, :each, :empty?, :keys, :map, :size

    include Enumerable

  end

end
