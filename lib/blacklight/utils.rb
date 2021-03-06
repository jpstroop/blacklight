require 'ostruct'
module Blacklight
  ##
  # An OpenStruct that responds to common Hash methods
  class OpenStructWithHashAccess < OpenStruct
    delegate :keys, :each, :map, :has_key?, :empty?, :delete, :length, :reject!, :select!, :include, :fetch, :to_json, :as_json, :to => :to_h

    if ::RUBY_VERSION < '2.0'
      def []=(key, value)
        send "#{key}=", value
      end

      def [](key)
        send key
      end
    end

    ##
    # Expose the internal hash
    # @return [Hash]
    def to_h
      @table
    end

    ##
    # Merge the values of this OpenStruct with another OpenStruct or Hash
    # @param [Hash,#to_h]
    # @return [OpenStructWithHashAccess] a new instance of an OpenStructWithHashAccess
    def merge other_hash
      self.class.new to_h.merge((other_hash if other_hash.is_a? Hash) || other_hash.to_h)
    end

    ##
    # Merge the values of another OpenStruct or Hash into this object
    # @param [Hash,#to_h]
    # @return [OpenStructWithHashAccess] a new instance of an OpenStructWithHashAccess
    def merge! other_hash
      @table.merge!((other_hash if other_hash.is_a? Hash) || other_hash.to_h)
    end 
  end


  ##
  # An OpenStruct refinement that converts any hash-keys into  
  # additional instances of NestedOpenStructWithHashAccess
  class NestedOpenStructWithHashAccess < OpenStructWithHashAccess
    attr_reader :nested_class
    delegate :default_proc=, :to => :to_h

    def initialize klass, *args
      @nested_class = klass
      hash = {}

      hashes_and_keys = args.flatten
      lazy_configs = hashes_and_keys.extract_options!

      args.each do |v|
        if v.is_a? Hash
          key = v.first
          value = v[key]

          hash[key] = nested_class.new value
        else
          hash[v] = nested_class.new
        end
      end

      lazy_configs.each do |k,v|
        hash[k] = nested_class.new v
      end

      super hash
      set_default_proc!
    end

    ##
    # Add an new key to the object, with a default default
    def << key
      @table[key]
    end

    ##
    # Add a new key/value to the object; if it's a Hash, turn it
    # into another NestedOpenStructWithHashAccess
    def []=(key, value)
      if value.is_a? Hash
        send "#{key}=", nested_class.new(value)
      elsif ::RUBY_VERSION < '2.0'
        send "#{key}=", value
      else
        super
      end
    end

    ##
    # Before serializing, we need to reset the default proc
    # so it can be serialized appropriately
    def marshal_dump
      h = to_h.dup
      h.default = nil

      [nested_class, h]
    end

    ##
    # After deserializing, we need to re-add the default proc
    # to the internal hash
    def marshal_load x
      @nested_class = x.first
      super x.last
      set_default_proc!
    end

    private
    def set_default_proc!
      self.default_proc = lambda do |hash, key|
        hash[key] = self.nested_class.new
      end
    end
  end
end
