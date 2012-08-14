#!/usr/bin/env ruby
require 'pp'

#TODO bundle
require 'twitter'
require 'mongo'

class NeroBot
  def initialize
    setting_list = open('.env').each.map { |line|
      set = line.chomp.split('#')[0].split('=')
      set.size == 2 ? set : nil
    }.compact.flatten

    setting = Hash[*setting_list]

    # TODO ここもっと綺麗に書きたい
    Twitter.configure do |config|
      config.consumer_key       = setting['consumer_key']
      config.consumer_secret    = setting['consumer_secret']
      config.oauth_token        = setting['oauth_token']
      config.oauth_token_secret = setting['oauth_token_secret']
    end

    @db = Mongo::Connection.new.db('nero_bot');
    # users = @db['users']
    # users.insert({hoge: "piyo"})
  end

  def handle_mentions
    Twitter.mentions.map { |mention|
      mention.id
    }
  end

  attr_reader :config
end

bot = NeroBot.new
pp bot.handle_mentions
# pp Twitter.home_timeline.map{ |status|
#   status.user.name + " : " + status.text
# }

# TODO
#   sqlite

# 登録とか
#   前回以降のメンション取得
#     (@nero_bot set:23-06)   ... 寝る時間=つぶやかない時間をセット
#     (@nero_bot unfollow)    ... 使うのをやめる
#     (@nero_bot snooze)      ... 当日は一時停止
#     条件に合えば設定登録、フォロー開始
#
# 監視
#   前回以降のHomeタイムライン読み込み
#     条件に合えばメンション飛ばす
#     3回やってダメだったらアンフォロー or snooze
