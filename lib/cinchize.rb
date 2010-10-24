# -*- coding: utf-8 -*-
# Copyright (c) 2010 Victor Bergöö
# This program is made available under the terms of the MIT License.

dir = File.dirname(__FILE__)
$LOAD_PATH.unshift(dir) unless $LOAD_PATH.include? dir

require 'cinch'
require 'daemons'
require 'json'

module Cinchize
  def self.run
    daemon_options, ntw, plugins, plugin_options = config 
    Daemons.run_proc(daemon_options[:app_name], daemon_options) do
      bot = Cinch::Bot.new do  
        configure do |c|
          ntw.keys.each do |key|
            c.send("#{key}=".to_sym, ntw[key])
          end
          
          c.plugins.plugins = plugins
          c.plugins.options = plugin_options
        end
      end
      
      bot.start
    end
  rescue ArgumentError => e
    puts "Error: #{e}"
    exit 1
  end
  
  def self.config
    cmd_options = []
    
    idx = ARGV.index "--"
    unless idx.nil?
      cmd_options = ARGV.dup.slice(idx+1..-1)
    end
    
    config_file = "/etc/cinchize.json"
    unless cmd_options.index("-f").nil?
      config_file = cmd_options[cmd_options.index("-f") + 1]
    end
    
    raise ArgumentError.new "the config file doesn't exist" unless File.exists? config_file
    raise ArgumentError.new "needs a network" if cmd_options[-1].nil?

    network = cmd_options[-1]
    
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

    dir_mode = cfg["options"]["dir_mode"].nil? ? "normal" : cfg["options"]["dir_mode"]

    cfg["options"] ||= {}
    daemon_options = {
      :dir_mode => dir_mode.to_sym,
      :dir => cfg["options"]["dir"] || Dir.getwd,
      :log_output => cfg["options"]["log_output"] || false,
      :app_name => "cinchize_#{network}"
    }

    [daemon_options, ntw, plugins, plugin_options]
  end
end
