require "config_mapper"
require "config_mapper/config_dict"

module ConfigMapper

  # A set of configurable attributes.
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
      def attribute(name, options = {})
        name = name.to_sym
        required = true
        default_value = nil
        if options.key?(:default)
          default_value = options.fetch(:default).freeze
          required = false if default_value.nil?
        end
        attribute_initializers[name] = proc { default_value }
        required_attributes << name if required
        attr_reader(name)
        define_method("#{name}=") do |value|
          if value.nil?
            raise NoValueProvided if required
          else
            value = yield(value) if block_given?
          end
          instance_variable_set("@#{name}", value)
        end
      end

      # Defines a sub-component.
      #
      # If a block is be provided, it will be `class_eval`ed to define the
      # sub-components class.
      #
      # @param name [Symbol] component name
      # @options options [String] :type (ConfigMapper::ConfigStruct)
      #   component base-class
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
      # If a block is be provided, it will be `class_eval`ed to define the
      # sub-components class.
      #
      # @param name [Symbol] dictionary attribute name
      # @options options [Proc] :key_type
      #   function used to validate keys
      # @options options [String] :type (ConfigMapper::ConfigStruct)
      #   base-class for sub-component values
      #
      def component_dict(name, options = {}, &block)
        name = name.to_sym
        declared_component_dicts << name
        type = options.fetch(:type, ConfigStruct)
        type = Class.new(type, &block) if block
        type = type.method(:new) if type.respond_to?(:new)
        key_type = options[:key_type]
        key_type = key_type.method(:new) if key_type.respond_to?(:new)
        attribute_initializers[name] = lambda do
          ConfigDict.new(type, key_type)
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
      config_struct_ancestors.each do |klass|
        klass.attribute_initializers.each do |name, initializer|
          instance_variable_set("@#{name}", initializer.call)
        end
      end
    end

    def immediate_config_errors
      missing_required_attribute_errors
    end

    def config_errors
      immediate_config_errors.merge(component_config_errors)
    end

    # Configure with data.
    #
    # @param attribute_values [Hash] attribute values
    # @return [Hash] errors encountered, keyed by attribute path
    #
    def configure_with(attribute_values)
      errors = ConfigMapper.configure_with(attribute_values, self)
      config_errors.merge(errors)
    end

    # Return the configuration as a Hash.
    #
    # @return [Hash] serializable config data
    #
    def to_h
      {}.tap do |result|
        config_struct_ancestors.each do |klass|
          klass.attribute_initializers.keys.each do |attr_name|
            value = send(attr_name)
            if value && value.respond_to?(:to_h) && !value.is_a?(Array)
              value = value.to_h
            end
            result[attr_name.to_s] = value
          end
        end
      end
    end

    private

    def config_struct_ancestors
      self.class.ancestors.take_while { |c| c != ConfigStruct }
    end

    def components
      {}.tap do |result|
        config_struct_ancestors.each do |klass|
          klass.declared_components.each do |name|
            result[".#{name}"] = instance_variable_get("@#{name}")
          end
          klass.declared_component_dicts.each do |name|
            instance_variable_get("@#{name}").each do |key, value|
              result[".#{name}[#{key.inspect}]"] = value
            end
          end
        end
      end
    end

    class NoValueProvided < ArgumentError

      def initialize
        super("no value provided")
      end

    end

    def missing_required_attribute_errors
      {}.tap do |errors|
        config_struct_ancestors.each do |klass|
          klass.required_attributes.each do |name|
            if instance_variable_get("@#{name}").nil?
              errors[".#{name}"] = NoValueProvided.new
            end
          end
        end
      end
    end

    def component_config_errors
      {}.tap do |errors|
        components.each do |component_name, component_value|
          next unless component_value.respond_to?(:config_errors)
          component_value.config_errors.each do |key, value|
            errors["#{component_name}#{key}"] = value
          end
        end
      end
    end

  end

end
