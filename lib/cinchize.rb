# -*- coding: utf-8 -*-
# Copyright (c) 2010 Victor Bergöö
# This program is made available under the terms of the MIT License.

dir = File.dirname(__FILE__)
$LOAD_PATH.unshift(dir) unless $LOAD_PATH.include? dir

require 'cinch'
require 'daemons'
require 'json'
require 'optparse'

module Cinchize
  Options = {
    :ontop => true,
    :system => false,
    :local_config => File.join(Dir.pwd, 'cinchize.json'),
    :system_config => '/etc/cinchize.json',
    :action => nil,
  }
  
  def self.run
    options = Options.dup
    
    ARGV.options do |o|
      o.set_summary_indent '  '
      o.banner = "Usage: #{File.basename $0} [Options] network"
      
      o.on("-d", "--daemonize", "Daemonize") { 
        options[:ontop] = false
      }
      
      o.on("-s", "--system-config", "Use system config") { 
        options[:system] = true
      }
      
      o.on("--start", "Start the bot") {
        options[:action] = :start
      }

      o.on("--status", "Status of the bot") {
        options[:action] = :status
      }
      
      o.on("--stop", "Stop the bot") {
        options[:action] = :stop
      }
      
      o.on("--restart", "Restart the bot") {
        options[:action] = :restart
      }
      
      o.parse!
    end

    daemon = Cinchize.new *config(options, ARGV.first)
    daemon.send options[:action]
  rescue NoMethodError => e
    puts "Error: no such method"
    exit 1
  rescue ArgumentError => e
    puts "Error: #{e}"
    exit 1
  end

  def self.config options, network
    config_file = options[:system] ? options[:system_config]: options[:local_config]
    
    raise ArgumentError.new "the config file #{config_file} doesn't exist" unless File.exists? config_file
    raise ArgumentError.new "needs a network" if network.nil? or network.empty?

    cfg = JSON.parse File.open(config_file, "r").read()
    
    raise ArgumentError.new "there's no server config in the config file" unless cfg.has_key? "servers"
    raise ArgumentError.new "the config file doesn't contain a config for #{network}" unless cfg["servers"].has_key? network
    
    ntw = cfg["servers"][network]
    
    plugins = []
    plugin_options = {}
    
    ntw.delete("plugins").each do |plugin|
      begin
        raise LoadError.new "the module can't be null" if plugin["module"].nil?
        raise NameError.new "the class can't be null" if plugin["class"].nil?
        
        require plugin["module"]
      
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

    raise ArgumentError.new "no plugins loaded" if plugins.size == 0

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

      network = @network
      plugins = @plugins
      plugin_options = @plugin_options

      loop do
        bot = Cinch::Bot.new do  
          configure do |c|
            network.each_pair { |key, value| c.send("#{key}=".to_sym, value) }

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

      Process.kill(9, pidfile.pid)
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

