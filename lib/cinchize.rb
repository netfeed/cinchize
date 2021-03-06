# -*- coding: utf-8 -*-
# Copyright (c) 2010-2012 Victor Bergöö
# This program is made available under the terms of the MIT License.

dir = File.dirname(__FILE__)
$LOAD_PATH.unshift(dir) unless $LOAD_PATH.include? dir

require 'cinch'
require 'daemons'
require 'yaml'

module Cinchize
  VERSION = File.read(File.dirname(__FILE__) + "/../VERSION").chomp
  
  def self.config options, network
    config_file = options[:system] ? options[:system_config]: options[:local_config]
    
    raise ArgumentError.new "there's no config file located at: #{config_file}" unless File.exists? config_file
    raise ArgumentError.new "needs a network" if network.nil? or network.empty?

    cfg = YAML.load_file config_file
    
    raise ArgumentError.new "there's no server config in the config file" unless cfg.has_key? "servers"
    raise ArgumentError.new "there's no networks configured, please recheck #{config_file}" unless cfg["servers"]
    raise ArgumentError.new "the config file doesn't contain a config for #{network}" unless cfg["servers"].has_key? network
    
    ntw = cfg["servers"][network]
    
    plugins = []
    plugin_options = {}

    ntw["plugins"] ||= []
    ntw.delete("plugins").each do |plugin|
      begin
        raise NameError.new "the class can't be null" if plugin["class"].nil?
        
        require plugin["class"].downcase.gsub('::', '/')
      
        clazz = nil
        plugin["class"].split("::").inject(Object) { |m,n| clazz = m.const_get(n) }
        plugins << clazz 
      
        plugin_options[clazz] = plugin["options"] || {}
      rescue LoadError => e
        puts "error while loading the module: #{e}"
      rescue NameError => e
        puts "error while loading the class: #{e}"
      end
    end

    cfg["options"] ||= {}
    dir_mode = cfg["options"].key?("dir_mode") ? cfg["options"]["dir_mode"] : "normal"
        
    daemon_options = {
      :dir_mode => dir_mode.to_sym,
      :dir => cfg["options"]["dir"] || Dir.getwd,
      :log_output => cfg["options"]["log_output"] || false,
      :app_name => "cinchize_#{network}",
      :ontop => options[:ontop],
    }

    [daemon_options, ntw, plugins, plugin_options]
  end
  
  class Cinchize
    attr_reader :options
    
    def initialize options, network, plugins, plugin_options
      @network = network
      @plugins = plugins      
      @plugin_options = plugin_options
      @options = options
    end

    def app_name
      options[:app_name]
    end

    def dir
      options[:dir]
    end
    
    def clean_app_name
      app_name.split('_', 2).last
    end

    def restart
      stop
      start
    end

    def start 
      if running?
        raise ArgumentError.new "#{clean_app_name} is already running"      
      end

      puts "* starting #{clean_app_name}"

      daemon = Daemons::ApplicationGroup.new(app_name, {
        :ontop => options[:ontop],
        :dir => dir,
        :dir_mode => options[:dir_mode]
      })
      app = daemon.new_application :mode => :none, :log_output => options[:log_output]
      app.start

      network = _sym_hash(@network)
      plugins = @plugins
      plugin_options = @plugin_options

      loop do
        bot = Cinch::Bot.new do  
          configure do |c|
            c.load network

            c.plugins.plugins = plugins
            c.plugins.options = plugin_options
          end
        end

        bot.start
      end
    end
    
    def stop 
      unless running?
        puts "* #{clean_app_name} is not running"
        return
      end

      pidfile = Daemons::PidFile.new dir, app_name
      puts "* stopping #{clean_app_name}"

      Process.kill("QUIT", pidfile.pid)
      File.delete(pidfile.filename)
    end
    
    def status 
      if running?
        puts "* #{clean_app_name} is running"
      else
        puts "* #{clean_app_name} is not running"
      end
    end
    
    def running? 
      pidfile = Daemons::PidFile.new dir, app_name
      return false if pidfile.pid.nil?
      return Process.kill(0, pidfile.pid) != 0
    rescue Errno::ESRCH => e
      return false
    end

    def _sym_hash hsh
      hsh.keys.inject({}) do |memo, key| 
        if hsh[key].is_a? Hash
          memo[key.to_sym] = _sym_hash(hsh[key])
        else 
          memo[key.to_sym] = hsh[key]
        end
        memo 
      end
    end
  end
end

# We need to open up Daemons::Application#start_none so we can log the output
# The original code can be found at: 
# => http://github.com/ghazel/daemons/blob/master/lib/daemons/application.rb#L60
module Daemons
  class Application
    def start_none
      unless options[:ontop]
        Daemonize.daemonize(output_logfile, @group.app_name) # our change goes here
      else
        Daemonize.simulate
      end

      @pid.pid = Process.pid

      at_exit {
        begin; @pid.cleanup; rescue ::Exception; end
        if options[:backtrace] and not options[:ontop] and not $daemons_sigterm
          begin; exception_log(); rescue ::Exception; end
        end
      }
      trap(SIGNAL) {
        begin; @pid.cleanup; rescue ::Exception; end
        $daemons_sigterm = true

        if options[:hard_exit]
          exit!
        else
          exit
        end
      }
    end
  end
end

