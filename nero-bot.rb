#!/usr/bin/env ruby
#coding: utf-8

require 'pp'
require 'json'

#TODO bundle
require 'twitter'
require 'mongo'

Encoding.default_external = Encoding::UTF_8

BASE_PATH = File.expand_path(File.dirname(__FILE__))
SETTING_FILE = File.join(BASE_PATH, '.env')
DO_SLEEP_FILE = File.join(BASE_PATH, 'do-sleep.txt')

BOT_NAME = 'yoiko_ha_nero'

TASK_MENTION_PATTERN = /^@#{BOT_NAME} ([a-z0-9-]*)$/

class NeroBot
  def initialize setting_file = SETTING_FILE
    settings = load_settings setting_file

    configure_twitter settings
    configure_db
  end

  # TODO dbへの保存も行なっているのでメソッド名を修正する # もしくはブロックを受け取るようにする
  def fetch_statuses api_name
    valid_api_names = [:mentions, :home_timeline]
    unless valid_api_names.include? api_name.to_sym
      raise "invalid api name: #{api_name}"
    end

    api_name = api_name.to_s

    options = {
      count: 200,
      since_id: since_id(api_name)
    }

    statuses = Twitter.method(api_name).call(options)
      .map{ |tw_status|
        status = tw_status.to_hash

        { id: status[:id_str], data: status }
      }

    return 0 if statuses.size == 0

    insert_each_when_absent(@db[api_name], statuses)
    since_id(api_name, statuses.first[:id])
  end

  def process_mentions
    mentions = @db['mentions']
    tasks = mentions.find({state: {'$ne' => 'done'}})
      .map{ |mention|
        text = mention['data']['text']
        mt = text.match(TASK_MENTION_PATTERN) || []
        unless mt.size == 2
          # パターンにマッチしなければdbから削除
          mentions.remove(mention)
          next
        end

        message = mt[1]
        m_user = mention['data']['user']
        user = {id: m_user['id_str'], screen_name: m_user['screen_name']}

        { id: mention['id'], message: message, user: user }
      }.compact

    excecute_tasks tasks

    tasks.size
  end

  def process_home_timeline
    timeline = @db['home_timeline']
    users = @db['users']

    statuses = timeline.find({state: {'$ne' => 'done'}}).to_a

    statuses.map { |status|

      status_state :home_timeline, status['id'], :done # 処理済みにする

      user_id = status['data']['user']['id'].to_s
      user = users.find_one({id: user_id})

      if user
        #screen_nameが変更された場合の応急処置
        user['screen_name'] = status['data']['user']['screen_name']
      else
        nil
      end
    }.compact.select { |user|

      now = Time.now.strftime("%H%M").to_i
      sleep_time?(now, user['start'], user['end'])

    }.uniq.each do |user|

      screen_name = user['screen_name']
      #TODO replyにする?

      exclude = last_status
      do_sleep = open(DO_SLEEP_FILE).readlines
        .reject { |line| line.chomp == exclude }
        .shuffle
        .first
      Twitter.update("@#{screen_name} #{do_sleep}")
      last_status do_sleep
    end

    statuses.size
  end

private

  def sleep_time? (n_now, n_start, n_end)
    # 0000 (now:0300)  0600
    ((n_start < n_now) && (n_now < n_end)) ||

    # 2200 (now:2300) 0600
    ((n_end < n_start) && (n_start < n_now)) ||

    # 2200 (now:0100) 0600
    ((n_end < n_start) && (n_now < n_end))
  end

  def excecute_tasks valid_tasks
    valid_tasks.each do |task|
      case task[:message]
      when /^([0-9]{4})-([0-9]{4})$/
        # フォローしていなければフォロー開始
        user = task[:user]
        follow_user user[:id]

        update_user_info user, $1, $2

      when /^remove$/
        # TODO アンフォローして監視をやめる
        user_id = task[:user][:id]

        unfollow_user user_id
        remove_user_info user_id

      #when /^stop$/
        # TODO その日はそれ以上監視しない
      #when /^start$/
        # TODO 監視の一時停止を解除、もしくはデフォルト設定で開始(00:00-6:00)
      else
        # なにもしない
      end

      # 処理済みにする
      status_state :mentions, task[:id], :done
    end
  end

  def unfollow_user user_id
    Twitter.unfollow user_id.to_i
  end

  def follow_user user_id
    Twitter.follow user_id.to_i
  end

  def remove_user_info user_id
    @db['users'].remove({id: user_id})
  end

  def update_user_info user, t_start, t_end
    users = @db['users']

    condition = { id: user[:id] }
    doc       = condition.merge({
      screen_name:  user[:screen_name],
      start:        t_start.to_i,
      'end' =>      t_end.to_i  # TODO ここきもい
    })

    insert_or_update(users, condition, doc)
  end

  def status_state collection_name, id, update_state = nil
    collection = @db[collection_name.to_s]
    condition = { id: id }

    if update_state
      doc = {state: update_state.to_s}
      insert_or_update(collection, condition, doc)
    else
      collection.find_one(condition)['state']
    end
  end

  def configure_twitter settings
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

  def load_settings setting_file
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

  def since_id name, update_id = nil
    bot_info = @db['bot_info']
    condition = {name: name.to_s}

    if (update_id)
      # 更新
      doc = { since_id: update_id }
      insert_or_update(bot_info, condition, doc)
    else
      # 取得
      info = bot_info.find_one(condition)
      return 1 unless info

      info['since_id']
    end
  end

  # TODO since_idと重複している処理がある
public
  def last_status update_status = nil
    bot_info = @db['bot_info']
    condition = { name: 'last_status' }

    if (update_status)
      doc = { text: update_status }
      insert_or_update bot_info, condition, doc
    else
      info = bot_info.find_one(condition)
      return nil unless info

      info['text']
    end
  end

  def insert_or_update collection, condition, doc
    if collection.find_one condition
      # 更新
      collection.update(condition, { '$set' => doc })
    else
      # 新規作成
      collection.insert doc.merge(condition)
    end
  end

  def insert_each_when_absent collection, docs
    docs.each do |doc|
      # すでに同じidのdocが存在するならスキップ
      next if collection.find_one({ id: doc[:id] })
      collection.insert(doc)
    end
  end

end


if __FILE__ == $PROGRAM_NAME
  #TODO テスト

  bot = NeroBot.new

  puts 'start: ' + Time.now.to_s
  bot.fetch_statuses :mentions
  puts ' new mentions: ' + bot.process_mentions.to_s

  bot.fetch_statuses :home_timeline
  puts ' new tweet: ' + bot.process_home_timeline.to_s

  puts ' api remaining_hits: ' + Twitter.rate_limit_status[:remaining_hits].to_s
  puts '  end: ' + Time.now.to_s
end

