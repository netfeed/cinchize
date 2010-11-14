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

    d_options, network, plugins, plugin_options = config(options, ARGV.first)

    case options[:action]
    when :start then 
      start(d_options, network, plugins, plugin_options)
    when :status then 
      status(d_options[:dir], d_options[:app_name])
    when :stop then 
      stop(d_options[:dir], d_options[:app_name])
    when :restart then 
      stop(d_options[:dir], d_options[:app_name])
      start(d_options, network, plugins, plugin_options)
    else
      puts "Error: no valid action supplied"
      exit 1
    end
  rescue ArgumentError => e
    puts "Error: #{e}"
    exit 1
  end
  
  def self.start d_options, network, plugins, plugin_options
    if running?(d_options[:dir], d_options[:app_name])
      raise ArgumentError.new "#{d_options[:app_name].split('_').last} is already running"      
    end

    puts "* starting #{d_options[:app_name].split('_').last}"
    
    daemon = Daemons::ApplicationGroup.new(d_options[:app_name], {
      :ontop => d_options[:ontop],
      :dir => d_options[:dir],
      :dir_mode => d_options[:dir_mode]
    })
    app = daemon.new_application :mode => :none, :log_output => d_options[:log_output]
    app.start
    
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
  
  def self.stop dir, app_name
    unless running?(dir, app_name)
      puts "* #{app_name.split('_').last} is not running"
      return
    end

    pidfile = Daemons::PidFile.new dir, app_name
    puts "* stopping #{app_name.split('_').last}"
    
    Process.kill(9, pidfile.pid)
    File.delete(pidfile.filename)
  end
  
  def self.status dir, app_name
    if running?(dir, app_name)
      puts "* #{app_name.split('_').last} is running"
    else
      puts "* #{app_name.split('_').last} is not running"
    end
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
    dir_mode = cfg["options"]["dir_mode"].nil? ? "normal" : cfg["options"]["dir_mode"]
    
    daemon_options = {
      :dir_mode => dir_mode.to_sym,
      :dir => cfg["options"]["dir"] || Dir.getwd,
      :log_output => cfg["options"]["log_output"] || false,
      :app_name => "cinchize_#{network}",
      :ontop => options[:ontop],
    }

    [daemon_options, ntw, plugins, plugin_options]
  end
  
  def self.running? dir, app_name
    pidfile = Daemons::PidFile.new dir, app_name
    return false if pidfile.pid.nil?
    return Process.kill(0, pidfile.pid) != 0
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

