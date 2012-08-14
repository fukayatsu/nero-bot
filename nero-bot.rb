#!/usr/bin/env ruby
require 'pp'

class NeroBot
  def initialize
    array = open('.env').each.map { |line|
      kv = line.chomp.split('#')[0].split('=')
      kv.size == 2 ? kv : nil
    }.compact.flatten

    @config = Hash[*array]
  end

  attr_reader :config
end

nero_bot = NeroBot.new
pp nero_bot.config

