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
    settings = load_settings setting_file

    configure_twitter(settings)
    configure_db
  end

  def fetch_home_timeline
    options = {
      count: 200,
      since_id: since_id_of('home_timeline')
    }
    home_timeline =
      Twitter.home_timeline(options)
        .map{ |tw_status|
          status = tw_status.to_hash
          {id: status[:id_str], data: status}
        }

    return if home_timeline.size == 0

    insert_each_when_absent(@home_timeline, home_timeline)
    since_id_of('home_timeline', home_timeline.first[:id])
  end

  def fetch_mentions
    options = {
      count: 200,
      since_id: since_id_of('mentions')
    }
    mentions =
      Twitter.mentions(options)
        .map{ |tw_mention|
          mention = tw_mention.to_hash
          {id: mention[:id_str], data: mention}
        }

    return if mentions.size == 0

    insert_each_when_absent(@mentions, mentions)
    since_id_of('mentions', mentions.first[:id])
  end

private

  def configure_twitter(settings)
    # ここもっと綺麗に書きたい
    Twitter.configure do |config|
      config.consumer_key       = settings['consumer_key']
      config.consumer_secret    = settings['consumer_secret']
      config.oauth_token        = settings['oauth_token']
      config.oauth_token_secret = settings['oauth_token_secret']
    end
  end

  def configure_db
    db = Mongo::Connection.new.db('nero_bot');
    @users          = db['users']
    @mentions       = db['mentions']
    @home_timeline  = db['home_timeline']
    @bot_info       = db['bot_info']
  end

  def load_settings(setting_file)
    list = open(setting_file)
      .each
      .map { |line|
        set = line.chomp.split('#')[0].split('=')
        set.size == 2 ?
          set : nil
      }.compact.flatten
    Hash[*list]
  end

  def since_id_of(name, update_id = nil)
    if (update_id)
      condition = {name: name}
      doc = { since_id: update_id }
      insert_or_update(@bot_info, condition, doc)
    else
      info = @bot_info.find_one({name: name})
      return 1 unless info
      info['since_id'] || 1
    end
  end

  def insert_or_update(collection, condition, doc)
    if collection.find_one condition
      collection.update(condition, {'$set' => doc})
    else
      collection.insert doc.merge(condition)
    end
  end

  def insert_each_when_absent(collection, docs)
    docs.each do |doc|
      next if collection.find_one({id: doc[:id]})
      collection.insert(doc)
    end
  end

end


if __FILE__ == $PROGRAM_NAME
  #TODO テスト

  bot = NeroBot.new
  #bot.fetch_mentions
  #bot.fetch_home_timeline

end

