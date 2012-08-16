#!/usr/bin/env ruby

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

require 'pp'
require 'json'

#TODO bundle
require 'twitter'
require 'mongo'

SETTING_FILE = File.join(File.expand_path(File.dirname(__FILE__)), '.env')

class NeroBot
  def initialize(setting_file = SETTING_FILE)
    setting_file
    setting_list = open(setting_file).each.map { |line|
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

    db = Mongo::Connection.new.db('nero_bot');
    @users = db['users']
    @mentions = db['mentions']
    @home_tl = db['home_tl']
    @bot_info = db['bot_info']
  end

  #TODO 取得と保存に分割
  def save_mentions
    options = { count: 200 }

    Twitter.mentions(options).each do |m|
      mention = m.to_hash
      id_str = mention[:id_str]
      next if @mentions.find_one({id: id_str})

      doc = {id: id_str, data: mention, finished: false};
      @mentions.insert(doc)
    end
  end

  def save_home_timeline
    options = { count: 200 }

    Twitter.home_timeline(options) do |s|
      status = s.to_hash
      id_str = status[:id_str]
      next if @home_tl.find_one({id: id_str})

      doc = {id: id_str, data: status}
      @home_tl.insert(doc)
    end
  end

  def create_user(tw_user)
    id_str = tw_user[:id_str]
    return false if @users.find_one({id: id_str})

    doc = {id: id_str, data: tw_user}
    @users.insert(doc)
  end

  attr_reader :config
end


if __FILE__ == $PROGRAM_NAME
  #TODO テスト

  bot = NeroBot.new
  #bot.save_home_timeline
end

