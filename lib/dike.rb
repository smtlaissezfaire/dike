require "attributes"
require "orderedhash"

module Dike
  class LogFactory
    attribute "directory"
    attribute "current"

    def initialize directory = "dike"
      require "fileutils"
      FileUtils.mkdir_p directory
      @directory = directory
      list = Dir.glob(File.join(@directory, "*"))
      list = list.grep(%r/^[0-9]+$/).map{|entry| entry.to_i}
      @current = list.max || -1 
    end

    def next &block
      if block
        open File.join(@directory, self.next.to_s), "w", &block 
      else
        @current += 1
      end
    end
  end


  class << self
    def mark_birth object, stacktrace
      object_id = id object
      return if Objects[object_id]
      Objects[object_id] = stacktrace
      ObjectSpace.define_finalizer object, Finalizer
    end

    def id object
      Object::Methods["object_id"].bind(object).call
    end

    Objects = Hash.new

    Finalizer = lambda{|object_id| Objects.delete object_id}

    Ignore = Hash.new

    Ignore[Ignore.object_id] = true

    class << Ignore
      def transaction
        state = clone
        Ignore[state.object_id] = true
        yield
      ensure
        clear
        update state
        Ignore.delete state.object_id
        state = nil
      end
    end

    def ignore *list
      list.flatten.each do |object|
        object_id = ::Object::Methods["object_id"].bind(object).call
        Ignore[object_id] = true
        #ObjectSpace.define_finalizer object, &ignore_finalizer(object_id)
      end
    end

    def ignored &block
      object = block.call
      ignore object
      object
    end

    def ignore_finalizer object_id
      lambda{ Ignore.delete object_id }
    end

    attribute("filter"){ Object }
    attribute("threshold"){ Struct.new(:class, :code, :object)[42, 42, 1] }
    attribute("log"){ STDERR }
    attribute("logfactory"){ nil }
    
    def logfactory= value
      @logfactory =
        if value
          LogFactory === value ? value : LogFactory.new(value)
        else
          value
        end
    end

    def finger options = {} 
      Thread.critical = true

      begin
        GC.start

        count, code = :remembered 

        Ignore.transaction do
          count = Hash.new 0
          ignore count

          code = Hash.new do |h,k|
            sh = Hash.new 0
            ignore sh
            h[k] = sh 
          end
          ignore code
    
          ObjectSpace.each_object(filter) do |object|
            m = Object::Methods["object_id"].bind object
            ignore m
            object_id = m.call

            next if Ignore[object_id]

            m = Object::Methods["class"].bind object
            ignore m
            klass = m.call 

            defined_at = Objects[object_id]
            count[klass] += 1 
            code[klass][defined_at] += 1 
          end
        end

        GC.start

        worst_klasses =
          count.to_a.sort_by{|pair| pair.last}.last(threshold.class).reverse

        count.clear
        count = nil

=begin
        report = []
=end
        total = 0

        logging do |log|
          log.puts "---"

          worst_klasses.each do |klass, count|
            worst_code = code[klass].to_a.sort_by{|pair| pair.last}.last(threshold.code).reverse

            name = Class::Methods["name"].bind(klass).call.to_s
            name = Class::Methods["inspect"].bind(klass).call.to_s if name.empty?
            name = 'UNKNOWN' if name.empty?

            worst_code.each do |stacktrace, count|
              next unless count > threshold.object
=begin

  TODO - figure out why the hell yaml leaks so bad!

              report << OrderedHash[
                'class', name,
                'count', count,
                'stacktrace', (stacktrace ? stacktrace.clone : []),
              ]
=end
              trace = stacktrace ? stacktrace.clone : []

            ### roll our own because yaml leaks!
              log.puts "- class: #{ name }"
              log.puts "  count: #{ count }"
              if trace.empty?
                log.puts "  trace: []"
              else
                log.puts "  trace:"
                trace.each do |line|
                  log.puts "  - #{ line }"
                end
              end
            end

            worst_code.clear
            worst_code = nil

            total += count
          end
        end

=begin
        logging do |log|
          log.puts report.to_yaml
          log.flush
        end

        report.clear
        report = nil
        GC.start
=end

        worst_klasses.clear
        worst_klasses = nil

        code.clear
        code = nil

        GC.start

        total
      ensure
        Thread.critical = false 
      end
    end

    def logging &block
      logfactory ? logfactory.next(&block) : block.call(log)
    end
  end

  class ::Object
    Methods = instance_methods.inject(Hash.new){|h, m| h.update m => instance_method(m)}
    Methods["initialize"] = instance_method "initialize"
    Dike.ignore Methods
    Methods.each{|k,v| Dike.ignore k, v}

    verbose = $VERBOSE
    begin
      $VERBOSE = nil
      def initialize *a, &b
        Methods["initialize"].bind(self).call *a, &b
      ensure
        Dike.mark_birth self, caller rescue nil
      end
    ensure
      $VERBOSE = verbose 
    end
  end

  class ::Class
    Methods = instance_methods.inject(Hash.new){|h, m| h.update m => instance_method(m)}
    Dike.ignore Methods
    Methods.each{|k,v| Dike.ignore k, v}

    verbose = $VERBOSE
    begin
      $VERBOSE = nil
      def new *a, &b
        object = Methods["new"].bind(self).call *a, &b
      ensure
        Dike.mark_birth object, caller rescue nil
      end
      def allocate *a, &b
        object = Methods["allocate"].bind(self).call *a, &b
      ensure
        Dike.mark_birth object, caller rescue nil
      end
    ensure
      $VERBOSE = verbose 
    end
  end

  class ::Module
    Methods = instance_methods.inject(Hash.new){|h, m| h.update m => instance_method(m)}
    Dike.ignore Methods
    Methods.each{|k,v| Dike.ignore k, v}
  end
end


if defined? Rails 
  module Dike
    def self.on which = :rails
      case which.to_s
        when %r/^rails$/i 
          Dike.logfactory File.join(RAILS_ROOT, "log", "dike")

          ActionController::Base.module_eval do
            after_filter do |controller|
              Dike.finger
              true
            end
          end
      end
    end
  end
end
