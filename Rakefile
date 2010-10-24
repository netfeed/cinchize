# -*- coding: utf-8 -*-

require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "cinchize"
    gem.summary = %Q{Create dynamic Cinch IRC-bots and daemonize them}
    gem.description = %Q{Create dynamic Cinch IRC-bots and daemonize them, without the need of writing any code}
    gem.email = "victor.bergoo@gmail.com"
    gem.homepage = "http://github.com/netfeed/cinchize"
    gem.authors = ["Victor Bergöö"]
    gem.add_dependency "cinch"
    gem.add_dependency "daemons"
    gem.add_dependency "json"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end
