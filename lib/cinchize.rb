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
    cmd_options = []
    
    idx = ARGV.index "--"
    unless idx.nil?
      cmd_options = ARGV.dup.slice(idx+1..-1)
    end
    
    config_file = "/etc/cinchize.json"
    unless cmd_options.index("-f").nil?
      config_file = cmd_options[cmd_options.index("-f") + 1]
    end
    
    raise ArgumentError "needs a network" if cmd_options[-1].nil?
    network = cmd_options[-1]
    
    cfg = JSON.parse File.open(config_file, "r").read()
    cfg_options = cfg["options"] || {}
    
    raise ArgumentError "there's no server config in the config file" unless cfg.has_key? "servers"
    raise ArgumentError "the config file doesn't contain a config for #{network}" unless cfg["servers"].has_key? network

    ntw_cfg = cfg["servers"]
    ntw = ntw_cfg[network]
    
    plugins = []
    plugin_options = {}
    
    ntw.delete("plugins").each do |plugin|
      require plugin["module"]
      
      clazz = nil
      plugin["class"].split("::").inject(Object) { |m,n| clazz = m.const_get(n) }
      plugins << clazz 
      
      plugin_options[plugin["class"]] = plugin["options"] || {}
    end

    name = "cinchize_#{network}"
    
    daemon_options = {
      :pid => cfg_options["pid"] || File.dirname(__FILE__),
      :app_name => name
    }
    
    Daemons.run_proc(name, daemon_options) do
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
    
  end
end