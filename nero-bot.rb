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
    since_id = @bot_info.find_one({name: 'mentions'})['since_id'] || 1
    options = {
      count: 200,
      since_id: since_id
    }

    mentions = Twitter.mentions(options).map{ |tw_mentions|
      tw_mentions.to_hash
    }

    return if mentions.size == 0

    mentions.each do |mention|
      id_str = mention[:id_str]
      next if @mentions.find_one({id: id_str})

      doc = {id: id_str, data: mention, finished: false};
      @mentions.insert(doc)
    end

    since_id = mentions.first[:id_str];

    # TODO bot_info用にinsert or update的なものが必要
    doc = { since_id: since_id }
    # TODO 重複をなくす
    if @bot_info.find_one({name: "mentions"})
      @bot_info.update({name: "mentions"}, {"$set" => doc}) #hash roket使いたくない
    else
      p doc[:name] = 'mentions'
      @bot_info.insert(doc);
    end
  end

  def save_home_timeline
    options = { count: 200 }

    home_timeline = Twitter.home_timeline(options)
      .map{ |timeline| timeline.to_hash }

    home_timeline.each do |s|
      status = s.to_hash
      id_str = status[:id_str]
      next if @home_tl.find_one({id: id_str})

      doc = {id: id_str, data: status}
      @home_tl.insert(doc)
    end

    # TODO @bot_infoのsince_idを更新
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

