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

  def fetch_statuses(api_name)
    # TODO api_nameのホワイトリスト
    api_name = api_name.to_s

    options = {
      count: 200,
      since_id: since_id_of(api_name)
    }

    statuses = Twitter.method(api_name).call(options)
      .map{ |tw_status|
        status = tw_status.to_hash
        {id: status[:id_str], data: status}
      }

    return 0 if statuses.size == 0

    insert_each_when_absent(@db[api_name], statuses)
    since_id_of(api_name, statuses.first[:id])
  end

private

  def configure_twitter(settings)
    [
      'consumer_key',
      'consumer_secret',
      'oauth_token',
      'oauth_token_secret'
    ].each{ |key|
      Twitter.method("#{key}=").call settings[key]
    }
  end

  def configure_db
    @db = Mongo::Connection.new.db('nero_bot');
  end

  def load_settings(setting_file)
    list = open(setting_file)
      .each
      .map { |line|
        set = line.chomp.split('#')[0].split('=')
        set.size == 2 ?
          set : nil
      }
      .compact
      .flatten

    Hash[*list]
  end

  def since_id_of(name, update_id = nil)
    bot_info = @db['bot_info']
    condition = {name: name}

    if (update_id)
      # 更新
      doc = { since_id: update_id }
      insert_or_update(bot_info, condition, doc)
    else
      # 取得
      info = bot_info.find_one condition
      info ?
        info['since_id'] : 1
    end
  end

  def insert_or_update(collection, condition, doc)
    if collection.find_one condition
      # 更新
      collection.update(condition, {'$set' => doc})
    else
      # 新規作成
      collection.insert doc.merge(condition)
    end
  end

  def insert_each_when_absent(collection, docs)
    docs.each do |doc|
      # すでに同じidのdocが存在するならスキップ
      next if collection.find_one({id: doc[:id]})
      collection.insert(doc)
    end
  end

end


if __FILE__ == $PROGRAM_NAME
  #TODO テスト

  bot = NeroBot.new
  bot.fetch_statuses :mentions
  bot.fetch_statuses :home_timeline

end

